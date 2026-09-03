const express = require('express');
const multer = require('multer');
const fetch = require('node-fetch');
const { v4: uuidv4 } = require('uuid');

const router = express.Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter: (_req, file, callback) => {
    callback(null, /^image\/(jpeg|png|webp|avif)$/i.test(file.mimetype));
  },
});

router.post('/upload', upload.single('file'), async (req, res) => {
  const localUploadsEnabled = process.env.MEDIA_ALLOW_LOCAL_UPLOADS === 'true';
  const hasValidToken = process.env.MEDIA_UPLOAD_TOKEN &&
      req.headers['x-media-upload-token'] === process.env.MEDIA_UPLOAD_TOKEN;
  if (!hasValidToken && !localUploadsEnabled) {
    return res.status(401).json({ error: 'Invalid media upload token' });
  }
  if (!process.env.GITHUB_TOKEN || !process.env.GITHUB_REPOSITORY) {
    return res.status(503).json({ error: 'GitHub image storage is not configured' });
  }
  if (!req.file) {
    return res.status(400).json({ error: 'An image file is required' });
  }

  try {
    const extension = req.file.mimetype.split('/')[1].replace('jpeg', 'jpg');
    const directory = (process.env.GITHUB_MEDIA_DIRECTORY || 'assets/uploads')
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
        error: 'GitHub image upload failed',
        provider_status: response.status,
        provider_message: payload?.message || 'Unknown GitHub error',
      });
    }

    return res.status(201).json({ url });
  } catch (error) {
    console.error('Media upload error', error);
    return res.status(502).json({ error: 'Image provider unavailable' });
  }
});

module.exports = router;
