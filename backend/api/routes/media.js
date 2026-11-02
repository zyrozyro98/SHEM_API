const express = require('express');
const multer = require('multer');
const fetch = require('node-fetch');
const { v4: uuidv4 } = require('uuid');

const router = express.Router();
const maxImageBytes = 2 * 1024 * 1024;
const maxVideoBytes = 12 * 1024 * 1024;
const mediaDirectories = {
  products: process.env.GITHUB_PRODUCTS_DIRECTORY?.trim() || 'assets/products',
  promotions:
    process.env.GITHUB_PROMOTIONS_DIRECTORY?.trim() || 'assets/promotions',
  receipts: process.env.GITHUB_RECEIPTS_DIRECTORY?.trim() || 'assets/receipts',
  profiles: process.env.GITHUB_PROFILES_DIRECTORY?.trim() || 'assets/profiles',
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

function requireUploadToken(req, res, next) {
  const localUploadsEnabled = process.env.MEDIA_ALLOW_LOCAL_UPLOADS === 'true';
  const hasValidToken = process.env.MEDIA_UPLOAD_TOKEN &&
      req.headers['x-media-upload-token'] === process.env.MEDIA_UPLOAD_TOKEN;
  if (!hasValidToken && !localUploadsEnabled) {
    return res.status(401).json({ error: 'Invalid media upload token' });
  }
  next();
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

router.post('/upload', requireUploadToken, parseUpload, async (req, res) => {
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

module.exports = router;
