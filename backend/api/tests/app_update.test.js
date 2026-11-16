const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { createAppUpdateRouter } = require('../routes/app_update');

test('public update endpoint returns only the notice fields', async () => {
  const app = express();
  app.use('/app-update', createAppUpdateRouter({
    getDatabase: () => ({
      ref: (path) => {
        assert.equal(path, 'app_settings/app_update_notice');
        return {
          once: async () => ({
            val: () => ({
              active: true,
              latest_version: '2.0.0',
              title: 'Update',
              message: 'Please update',
              download_url: 'https://example.com/app.apk',
              target_roles: ['customer'],
              importance: 'mandatory',
              updated_at: 'private metadata',
              internal_note: 'must not be exposed',
            }),
          }),
        };
      },
    }),
  }));
  const server = app.listen(0, '127.0.0.1');

  try {
    await new Promise((resolve) => server.once('listening', resolve));
    const address = server.address();
    const response = await fetch(
      `http://127.0.0.1:${address.port}/app-update/notice`,
    );

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      active: true,
      latest_version: '2.0.0',
      title: 'Update',
      message: 'Please update',
      download_url: 'https://example.com/app.apk',
      target_roles: ['customer'],
      importance: 'mandatory',
    });
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
});
