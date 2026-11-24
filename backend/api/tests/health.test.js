const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const healthRouter = require('../routes/health');

async function startHealthApp() {
  const app = express();
  app.use('/health', healthRouter);
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  return server;
}

test('readiness reports missing and invalid production configuration', async () => {
  const originalEnvironment = Object.fromEntries([
    'FIREBASE_DATABASE_URL',
    'FIREBASE_SERVICE_ACCOUNT_JSON',
    'GITHUB_TOKEN',
    'GITHUB_REPOSITORY',
    'WAWP_INSTANCE_ID',
    'WAWP_ACCESS_TOKEN',
  ].map((key) => [key, process.env[key]]));
  for (const key of Object.keys(originalEnvironment)) delete process.env[key];
  process.env.FIREBASE_SERVICE_ACCOUNT_JSON = '{invalid';

  const server = await startHealthApp();
  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/health/ready`,
    );
    const body = await response.json();

    assert.equal(response.status, 503);
    assert.deepEqual(body.missing_configuration, [
      'FIREBASE_DATABASE_URL',
      'GITHUB_TOKEN',
      'GITHUB_REPOSITORY',
      'WAWP_INSTANCE_ID',
      'WAWP_ACCESS_TOKEN',
      'FIREBASE_SERVICE_ACCOUNT_JSON',
    ]);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    for (const [key, value] of Object.entries(originalEnvironment)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
});

test('readiness succeeds when required configuration is present', () => {
  assert.deepEqual(
    healthRouter.getMissingConfiguration({
      FIREBASE_DATABASE_URL: 'https://example.firebaseio.com',
      FIREBASE_SERVICE_ACCOUNT_JSON:
        '{"project_id":"test","client_email":"test@test.iam.gserviceaccount.com","private_key":"-----BEGIN PRIVATE KEY-----\\nkey\\n-----END PRIVATE KEY-----"}',
      GITHUB_TOKEN: 'configured',
      GITHUB_REPOSITORY: 'owner/repo',
      WAWP_INSTANCE_ID: 'configured',
      WAWP_ACCESS_TOKEN: 'configured',
    }),
    [],
  );
});
