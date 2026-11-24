const express = require('express');

const requiredEnvironment = [
  'FIREBASE_DATABASE_URL',
  'FIREBASE_SERVICE_ACCOUNT_JSON',
  'GITHUB_TOKEN',
  'GITHUB_REPOSITORY',
  'WAWP_INSTANCE_ID',
  'WAWP_ACCESS_TOKEN',
];

function getMissingConfiguration(environment = process.env) {
  const missing = requiredEnvironment.filter(
    (key) => !String(environment[key] ?? '').trim(),
  );
  const serviceAccount = String(
    environment.FIREBASE_SERVICE_ACCOUNT_JSON ?? '',
  ).trim();

  if (serviceAccount) {
    try {
      const parsed = JSON.parse(serviceAccount);
      if (
        !parsed ||
        typeof parsed !== 'object' ||
        typeof parsed.project_id !== 'string' ||
        !parsed.project_id.trim() ||
        typeof parsed.client_email !== 'string' ||
        !/^[^@\s]+@[^@\s]+\.iam\.gserviceaccount\.com$/.test(
          parsed.client_email,
        ) ||
        typeof parsed.private_key !== 'string' ||
        !parsed.private_key.includes('-----BEGIN PRIVATE KEY-----')
      ) {
        missing.push('FIREBASE_SERVICE_ACCOUNT_JSON');
      }
    } catch {
      missing.push('FIREBASE_SERVICE_ACCOUNT_JSON');
    }
  }

  return [...new Set(missing)];
}

const router = express.Router();

router.get('/ready', (_req, res) => {
  const missing = getMissingConfiguration();
  if (missing.length > 0) {
    return res.status(503).json({
      ok: false,
      missing_configuration: missing,
    });
  }
  return res.json({ ok: true });
});

router.get('/', (_req, res) => res.json({ ok: true }));

router.getMissingConfiguration = getMissingConfiguration;
module.exports = router;
