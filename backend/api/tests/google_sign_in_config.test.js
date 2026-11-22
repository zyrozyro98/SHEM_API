const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const {
  createGoogleSignInConfigRouter,
} = require('../routes/google_sign_in_config');

async function withGoogleConfig(getClientId, callback) {
  const app = express();
  app.use('/config', createGoogleSignInConfigRouter({ getClientId }));
  const server = app.listen(0, '127.0.0.1');

  try {
    await new Promise((resolve) => server.once('listening', resolve));
    const address = server.address();
    const response = await fetch(
      `http://127.0.0.1:${address.port}/config/google-sign-in`,
    );
    await callback(response);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
}

test('public Google config returns only the web client ID', async () => {
  await withGoogleConfig(
    () => 'shem-web.apps.googleusercontent.com',
    async (response) => {
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {
        client_id: 'shem-web.apps.googleusercontent.com',
      });
      assert.equal(response.headers.get('cache-control'), 'no-store');
    },
  );
});

test('Google config reports missing Render variable explicitly', async () => {
  await withGoogleConfig(
    () => '',
    async (response) => {
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), {
        error: 'Google web sign-in is not configured',
      });
    },
  );
});
