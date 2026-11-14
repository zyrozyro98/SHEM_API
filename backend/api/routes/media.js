const express = require('express');
const multer = require('multer');
const fetch = require('node-fetch');
const { v4: uuidv4 } = require('uuid');
const {
  getFirebaseAuth,
  getFirebaseDatabase,
} = require('../services/firebase_admin');
const {
  normalizeYemenPhoneKey,
  passwordMatches,
} = require('../services/auth_utils');

const maxImageBytes = 2 * 1024 * 1024;
const maxVideoBytes = 12 * 1024 * 1024;
const mediaDirectories = {
  products: process.env.GITHUB_PRODUCTS_DIRECTORY?.trim() || 'assets/products',
  promotions:
    process.env.GITHUB_PROMOTIONS_DIRECTORY?.trim() || 'assets/promotions',
  receipts: process.env.GITHUB_RECEIPTS_DIRECTORY?.trim() || 'assets/receipts',
  profiles: process.env.GITHUB_PROFILES_DIRECTORY?.trim() || 'assets/profiles',
  wallets: process.env.GITHUB_WALLETS_DIRECTORY?.trim() || 'assets/wallets',
};
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: maxVideoBytes },
  fileFilter: (_req, file, callback) => {
    callback(
      null,
      /^image\/(jpeg|png|webp|avif)$/i.test(file.mimetype) ||
        file.mimetype === 'video/mp4',
    );
  },
});

function createFirebaseDependencies() {
  return {
    readProfile: async (phoneKey) => {
      const snapshot = await getFirebaseDatabase()
        .ref(`profiles/${phoneKey}`).once('value');
      return snapshot.val();
    },
    createCustomToken: (uid) => getFirebaseAuth().createCustomToken(uid),
    verifyIdToken: (token) => getFirebaseAuth().verifyIdToken(token),
    linkAuthUid: async (phoneKey, uid, profile) => {
      const updates = {
        [`auth_index/${uid}`]: {
          phone: profile.phone ?? `+${phoneKey}`,
          email: profile.email ?? null,
        },
      };
      if (!profile.auth_uid && !profile.authUid) {
        updates[`profiles/${phoneKey}/auth_uid`] = uid;
      }
      await getFirebaseDatabase().ref().update(updates);
    },
  };
}

function createMediaRouter(dependencies = createFirebaseDependencies()) {
  const router = express.Router();
  const failedSessions = new Map();
  const {
    readProfile,
    createCustomToken,
    verifyIdToken,
    linkAuthUid = async () => {},
  } = dependencies;

  router.post('/session', async (req, res) => {
    const phoneKey = normalizeYemenPhoneKey(req.body?.phone);
    const password = String(req.body?.password ?? '');
    if (!phoneKey || !password.trim()) {
      return res.status(400).json({ error_code: 'invalid_request' });
    }

    const attemptKey = `${req.ip}:${phoneKey}`;
    const now = Date.now();
    const previousAttempts = failedSessions.get(attemptKey);
    if (previousAttempts && now - previousAttempts.startedAt < 15 * 60 * 1000 &&
        previousAttempts.count >= 5) {
      return res.status(429).json({ error_code: 'too_many_attempts' });
    }

    try {
      const profile = await readProfile(phoneKey);
      if (!profile || !passwordMatches(
        profile.password_hash ?? profile.passwordHash,
        password,
      )) {
        const attempts = previousAttempts &&
            now - previousAttempts.startedAt < 15 * 60 * 1000
          ? previousAttempts
          : { startedAt: now, count: 0 };
        failedSessions.set(attemptKey, {
          startedAt: attempts.startedAt,
          count: attempts.count + 1,
        });
        return res.status(401).json({ error_code: 'invalid_credentials' });
      }

      const uid = String(
        profile.auth_uid || profile.authUid || profile.id || phoneKey,
      ).trim();
      if (!uid || uid.length > 128) {
        return res.status(401).json({ error_code: 'invalid_credentials' });
      }

      failedSessions.delete(attemptKey);
      const customToken = await createCustomToken(uid);
      await linkAuthUid(phoneKey, uid, profile);
      return res.json({ success: true, custom_token: customToken });
    } catch (error) {
      console.error('Media session creation failed:', error.code ?? 'unknown');
      const status = error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED' ? 503 : 500;
      return res.status(status).json({
        error_code: status === 503
          ? 'media_auth_not_configured'
          : 'media_session_failed',
      });
    }
  });

  async function requireFirebaseUser(req, res, next) {
    if (process.env.MEDIA_ALLOW_LOCAL_UPLOADS === 'true') return next();

    const authorization = req.headers.authorization ?? '';
    const match = /^Bearer\s+(.+)$/i.exec(authorization);
    if (!match) {
      return res.status(401).json({ error_code: 'authentication_required' });
    }

    try {
      req.firebaseUser = await verifyIdToken(match[1]);
      return next();
    } catch (_) {
      return res.status(401).json({ error_code: 'invalid_authentication' });
    }
  }

  function parseUpload(req, res, next) {
    upload.single('file')(req, res, (error) => {
      if (error instanceof multer.MulterError) {
        const status = error.code === 'LIMIT_FILE_SIZE' ? 413 : 400;
        return res.status(status).json({ error: 'Invalid or oversized media file' });
      }
      if (error) {
        return res.status(400).json({ error: 'Invalid media file' });
      }
      next();
    });
  }

  router.post('/upload', requireFirebaseUser, parseUpload, async (req, res) => {
    if (!process.env.GITHUB_TOKEN || !process.env.GITHUB_REPOSITORY) {
      return res.status(503).json({ error: 'GitHub image storage is not configured' });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'A supported media file is required' });
    }

    const mediaType = (req.body.media_type || req.body.mediaType || 'products')
      .toString()
      .trim()
      .toLowerCase();
    if (!Object.prototype.hasOwnProperty.call(mediaDirectories, mediaType)) {
      return res.status(400).json({ error: 'Invalid media type' });
    }

    const isVideo = req.file.mimetype === 'video/mp4';
    if (isVideo && mediaType !== 'products') {
      return res.status(400).json({ error: 'Videos are only allowed for products' });
    }
    if (isVideo && req.file.buffer.toString('ascii', 4, 8) !== 'ftyp') {
      return res.status(400).json({ error: 'The uploaded file is not a valid MP4' });
    }
    if (!isVideo && req.file.size > maxImageBytes) {
      return res.status(413).json({ error: 'Image exceeds the 2 MiB limit' });
    }

    try {
      const extension = isVideo
        ? 'mp4'
        : req.file.mimetype.split('/')[1].replace('jpeg', 'jpg');
      const directory = mediaDirectories[mediaType]
        .replace(/^\/+|\/+$/g, '');
      const path = `${directory}/${uuidv4()}.${extension}`;
      const encodedPath = path.split('/').map(encodeURIComponent).join('/');
      const response = await fetch(
        `https://api.github.com/repos/${process.env.GITHUB_REPOSITORY}/contents/${encodedPath}`,
        {
          method: 'PUT',
          body: JSON.stringify({
            message: `Upload media ${path}`,
            content: req.file.buffer.toString('base64'),
            branch: process.env.GITHUB_BRANCH || 'main',
          }),
          headers: {
            Accept: 'application/vnd.github+json',
            Authorization: `Bearer ${process.env.GITHUB_TOKEN}`,
            'X-GitHub-Api-Version': '2022-11-28',
            'Content-Type': 'application/json',
          },
        },
      );
      const payload = await response.json();
      const [owner, repository] = process.env.GITHUB_REPOSITORY.split('/');
      const url = `https://raw.githubusercontent.com/${owner}/${repository}/${
        encodeURIComponent(process.env.GITHUB_BRANCH || 'main')
      }/${encodedPath}`;
      if (!response.ok || !url) {
        console.error('GitHub upload error', response.status, payload);
        return res.status(502).json({
          error: 'GitHub media upload failed',
          provider_status: response.status,
          provider_message: payload?.message || 'Unknown GitHub error',
        });
      }

      return res.status(201).json({ url });
    } catch (error) {
      console.error('Media upload error', error);
      return res.status(502).json({ error: 'Media provider unavailable' });
    }
  });

  return router;
}

const router = createMediaRouter();
router.createMediaRouter = createMediaRouter;
module.exports = router;
