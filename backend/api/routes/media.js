const express = require('express');
const crypto = require('crypto');
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

const switchSessionIdleLifetimeMs = 30 * 24 * 60 * 60 * 1000;
const switchSessionAbsoluteLifetimeMs = 180 * 24 * 60 * 60 * 1000;

function hashSwitchSecret(secret) {
  return crypto.createHash('sha256').update(secret).digest('hex');
}

function hashesMatch(first, second) {
  if (!/^[a-f0-9]{64}$/i.test(first) || !/^[a-f0-9]{64}$/i.test(second)) {
    return false;
  }
  return crypto.timingSafeEqual(
    Buffer.from(first, 'hex'),
    Buffer.from(second, 'hex'),
  );
}

function publicProfile(profile) {
  const safeProfile = { ...profile };
  delete safeProfile.password_hash;
  delete safeProfile.passwordHash;
  delete safeProfile.auth_uid;
  delete safeProfile.authUid;
  return safeProfile;
}

function createFirebaseDependencies() {
  return {
    readProfile: async (phoneKey) => {
      const snapshot = await getFirebaseDatabase()
        .ref(`profiles/${phoneKey}`).once('value');
      return snapshot.val();
    },
    resolveProfile: async (uid, claims) => {
      const database = getFirebaseDatabase();
      const authIndexSnapshot = await database.ref(`auth_index/${uid}`)
        .once('value');
      const authIndex = authIndexSnapshot.val() ?? {};
      const profileId = String(
        claims.profile_id ||
        authIndex.profile_id ||
        normalizeYemenPhoneKey(authIndex.phone) ||
        uid,
      ).trim();
      return {
        profileId,
        profile: await (async () => {
          const snapshot = await database.ref(`profiles/${profileId}`)
            .once('value');
          return snapshot.val();
        })(),
      };
    },
    createCustomToken: (uid, claims) =>
      getFirebaseAuth().createCustomToken(uid, claims),
    verifyIdToken: (token) => getFirebaseAuth().verifyIdToken(token),
    linkAuthUid: async (phoneKey, uid, profile) => {
      const updates = {
        [`auth_index/${uid}`]: {
          phone: profile.phone ?? `+${phoneKey}`,
          email: profile.email ?? null,
          profile_id: String(profile.id ?? phoneKey),
          role: String(profile.role ?? 'customer').trim().toLowerCase(),
        },
      };
      if (!profile.auth_uid && !profile.authUid) {
        updates[`profiles/${phoneKey}/auth_uid`] = uid;
      }
      await getFirebaseDatabase().ref().update(updates);
    },
    createSwitchSession: async ({ uid, profileId, role }) => {
      const database = getFirebaseDatabase();
      const sessionId = uuidv4();
      const sessionSecret = crypto.randomBytes(32).toString('hex');
      const now = Date.now();
      const expiresAt = now + switchSessionIdleLifetimeMs;
      const absoluteExpiresAt = now + switchSessionAbsoluteLifetimeMs;
      await database.ref(`auth_switch_sessions/${sessionId}`).set({
        uid,
        profile_id: profileId,
        role,
        secret_hash: hashSwitchSecret(sessionSecret),
        created_at: new Date(now).toISOString(),
        last_used_at: new Date(now).toISOString(),
        expires_at_ms: expiresAt,
        absolute_expires_at_ms: absoluteExpiresAt,
      });
      return {
        sessionId,
        sessionSecret,
        expiresAt: new Date(expiresAt).toISOString(),
      };
    },
    readSwitchSession: async (sessionId) => {
      const snapshot = await getFirebaseDatabase()
        .ref(`auth_switch_sessions/${sessionId}`).once('value');
      return snapshot.val();
    },
    rotateSwitchSession: async ({
      sessionId,
      oldSecretHash,
      newSecretHash,
      now,
    }) => {
      const reference = getFirebaseDatabase()
        .ref(`auth_switch_sessions/${sessionId}`);
      const result = await reference.transaction((current) => {
        if (!current ||
            !hashesMatch(current.secret_hash ?? '', oldSecretHash) ||
            Number(current.expires_at_ms) <= now ||
            Number(current.absolute_expires_at_ms) <= now) {
          return;
        }
        return {
          ...current,
          secret_hash: newSecretHash,
          last_used_at: new Date(now).toISOString(),
          expires_at_ms: Math.min(
            now + switchSessionIdleLifetimeMs,
            Number(current.absolute_expires_at_ms),
          ),
        };
      }, undefined, false);
      return result.committed ? result.snapshot.val() : null;
    },
    revokeSwitchSession: async ({ sessionId, secretHash }) => {
      const reference = getFirebaseDatabase()
        .ref(`auth_switch_sessions/${sessionId}`);
      const result = await reference.transaction((current) => {
        if (!current ||
            !hashesMatch(current.secret_hash ?? '', secretHash)) {
          return;
        }
        return null;
      }, undefined, false);
      return result.committed && result.snapshot.val() == null;
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
    resolveProfile,
    linkAuthUid = async () => {},
    createSwitchSession,
    readSwitchSession,
    rotateSwitchSession,
    revokeSwitchSession,
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
      const customToken = await createCustomToken(uid, {
        profile_id: String(profile.id ?? phoneKey),
        role: String(profile.role ?? 'customer').trim().toLowerCase(),
        otp_verified: false,
      });
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

  router.post('/switch-sessions', async (req, res) => {
    const authorization = req.headers.authorization ?? '';
    const match = /^Bearer\s+(.+)$/i.exec(authorization);
    if (!match) {
      return res.status(401).json({ error_code: 'authentication_required' });
    }

    try {
      const user = await verifyIdToken(match[1]);
      const { profileId, profile } = await resolveProfile(user.uid, user);
      if (!profile || !profileId) {
        return res.status(404).json({ error_code: 'account_not_found' });
      }

      const linkedUid = String(profile.auth_uid || profile.authUid || '').trim();
      if (
        (linkedUid && linkedUid !== user.uid) ||
        (user.uid !== profileId && String(user.profile_id ?? '') !== profileId)
      ) {
        return res.status(403).json({ error_code: 'forbidden' });
      }
      if (typeof createSwitchSession !== 'function') {
        return res.status(503).json({ error_code: 'switch_sessions_unavailable' });
      }

      const role = String(profile.role ?? 'customer').trim().toLowerCase();
      const session = await createSwitchSession({
        uid: user.uid,
        profileId,
        role,
      });
      return res.status(201).json({
        success: true,
        session_id: session.sessionId,
        session_secret: session.sessionSecret,
        expires_at: session.expiresAt,
      });
    } catch (error) {
      console.error('Persistent account session creation failed:',
        error.code ?? 'unknown');
      const status = error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED' ? 503 : 500;
      return res.status(status).json({
        error_code: status === 503
          ? 'media_auth_not_configured'
          : 'switch_session_creation_failed',
      });
    }
  });

  router.post('/switch-sessions/restore', async (req, res) => {
    const sessionId = String(req.body?.session_id ?? '').trim();
    const sessionSecret = String(req.body?.session_secret ?? '').trim();
    if (
      !/^[0-9a-f-]{36}$/i.test(sessionId) ||
      !/^[0-9a-f]{64}$/i.test(sessionSecret)
    ) {
      return res.status(400).json({ error_code: 'invalid_switch_session' });
    }
    if (
      typeof readSwitchSession !== 'function' ||
      typeof rotateSwitchSession !== 'function'
    ) {
      return res.status(503).json({ error_code: 'switch_sessions_unavailable' });
    }

    try {
      const session = await readSwitchSession(sessionId);
      const now = Date.now();
      if (!session ||
          Number(session.expires_at_ms) <= now ||
          Number(session.absolute_expires_at_ms) <= now ||
          !hashesMatch(
            String(session.secret_hash ?? ''),
            hashSwitchSecret(sessionSecret),
          )) {
        return res.status(401).json({ error_code: 'invalid_switch_session' });
      }

      const profileId = String(session.profile_id ?? '').trim();
      const uid = String(session.uid ?? '').trim();
      const profile = profileId ? await readProfile(profileId) : null;
      if (!profile || !uid) {
        return res.status(401).json({ error_code: 'account_not_found' });
      }

      const linkedUid = String(profile.auth_uid || profile.authUid || '').trim();
      if (linkedUid && linkedUid !== uid && uid !== profileId) {
        return res.status(401).json({ error_code: 'invalid_switch_session' });
      }

      const role = String(profile.role ?? 'customer').trim().toLowerCase();
      const customToken = await createCustomToken(uid, {
        profile_id: profileId,
        role,
        otp_verified: false,
      });
      const nextSecret = crypto.randomBytes(32).toString('hex');
      const nextExpiresAt = Math.min(
        now + switchSessionIdleLifetimeMs,
        Number(session.absolute_expires_at_ms),
      );
      const rotated = await rotateSwitchSession({
        sessionId,
        oldSecretHash: hashSwitchSecret(sessionSecret),
        newSecretHash: hashSwitchSecret(nextSecret),
        now,
      });
      if (!rotated) {
        return res.status(401).json({ error_code: 'invalid_switch_session' });
      }

      return res.json({
        success: true,
        custom_token: customToken,
        profile_id: profileId,
        role,
        session_secret: nextSecret,
        expires_at: new Date(nextExpiresAt).toISOString(),
        profile: publicProfile(profile),
      });
    } catch (error) {
      console.error('Persistent account session restore failed:',
        error.code ?? 'unknown');
      const status = error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED' ? 503 : 500;
      return res.status(status).json({
        error_code: status === 503
          ? 'media_auth_not_configured'
          : 'switch_session_restore_failed',
      });
    }
  });

  router.post('/switch-sessions/revoke', async (req, res) => {
    const sessionId = String(req.body?.session_id ?? '').trim();
    const sessionSecret = String(req.body?.session_secret ?? '').trim();
    if (
      !/^[0-9a-f-]{36}$/i.test(sessionId) ||
      !/^[0-9a-f]{64}$/i.test(sessionSecret)
    ) {
      return res.status(400).json({ error_code: 'invalid_switch_session' });
    }
    if (typeof revokeSwitchSession !== 'function') {
      return res.status(503).json({ error_code: 'switch_sessions_unavailable' });
    }

    try {
      const revoked = await revokeSwitchSession({
        sessionId,
        secretHash: hashSwitchSecret(sessionSecret),
      });
      if (!revoked) {
        return res.status(401).json({ error_code: 'invalid_switch_session' });
      }
      return res.json({ success: true });
    } catch (error) {
      console.error('Persistent account session revocation failed:',
        error.code ?? 'unknown');
      const status = error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED' ? 503 : 500;
      return res.status(status).json({
        error_code: status === 503
          ? 'media_auth_not_configured'
          : 'switch_session_revoke_failed',
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
