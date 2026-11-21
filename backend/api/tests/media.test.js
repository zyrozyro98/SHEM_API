const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const mediaModulePath = require.resolve('../routes/media');
const nodeFetchPath = require.resolve('node-fetch');
const firebaseAdmin = require('../services/firebase_admin');
const originalNodeFetch = require(nodeFetchPath);
const maxVideoBytes = 12 * 1024 * 1024;
const validIdToken = 'test-firebase-id-token';

firebaseAdmin.getFirebaseAuth = () => ({});
firebaseAdmin.getFirebaseDatabase = () => ({});

async function postMedia({
  bytes,
  contentType = 'video/mp4',
  mediaType = 'products',
  fileName = 'sample.mp4',
  idToken = validIdToken,
  legacyUploadToken,
}) {
  const originalEnvironment = {
    GITHUB_TOKEN: process.env.GITHUB_TOKEN,
    GITHUB_REPOSITORY: process.env.GITHUB_REPOSITORY,
    MEDIA_ALLOW_LOCAL_UPLOADS: process.env.MEDIA_ALLOW_LOCAL_UPLOADS,
  };
  let githubRequest;

  process.env.GITHUB_TOKEN = 'test-github-token';
  process.env.GITHUB_REPOSITORY = 'owner/repository';
  process.env.MEDIA_ALLOW_LOCAL_UPLOADS = 'false';
  require.cache[nodeFetchPath].exports = async (url, options) => {
    githubRequest = { url: String(url), options, body: JSON.parse(options.body) };
    return new Response(JSON.stringify({ content: {} }), { status: 201 });
  };
  delete require.cache[mediaModulePath];

  const app = express();
  app.use(express.json());
  app.use('/media', require(mediaModulePath).createMediaRouter({
    readProfile: async (phoneKey) => ({
      id: phoneKey,
      password_hash: hashPassword('correct horse'),
    }),
    createCustomToken: async (uid) => `custom-token-${uid}`,
    verifyIdToken: async (token) => {
      if (token !== validIdToken) throw new Error('Invalid token');
      return { uid: 'user-1' };
    },
    linkAuthUid: async () => {},
  }));
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const { port } = server.address();

  try {
    const form = new FormData();
    form.append('file', new Blob([bytes], { type: contentType }), fileName);
    form.append('media_type', mediaType);

    const headers = {};
    if (idToken) headers.Authorization = `Bearer ${idToken}`;
    if (legacyUploadToken) {
      headers['x-media-upload-token'] = legacyUploadToken;
    }
    const response = await fetch(`http://127.0.0.1:${port}/media/upload`, {
      method: 'POST',
      headers,
      body: form,
    });

    return {
      status: response.status,
      body: await response.json(),
      githubRequest,
    };
  } finally {
    await new Promise((resolve) => server.close(resolve));
    delete require.cache[mediaModulePath];
    require.cache[nodeFetchPath].exports = originalNodeFetch;
    for (const [key, value] of Object.entries(originalEnvironment)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

async function postSwitchSession({
  path,
  body,
  expired = false,
  refreshFails = false,
  attempts = 1,
}) {
  const sessionId = '123e4567-e89b-12d3-a456-426614174000';
  const sessionSecret = 'a'.repeat(64);
  const hashSecret = (secret) => require('crypto').createHash('sha256')
    .update(secret)
    .digest('hex');
  const profile = {
    id: 'profile-1',
    auth_uid: 'user-1',
    role: 'merchant',
    full_name: 'Test Merchant',
  };
  const storedSession = {
    uid: 'user-1',
    profile_id: 'profile-1',
    secret_hash: hashSecret(sessionSecret),
    expires_at_ms: Date.now() + (expired ? -1_000 : 60_000),
    absolute_expires_at_ms: Date.now() + 60_000,
  };
  const calls = {};
  const app = express();
  app.use(express.json());
  app.use('/media', require(mediaModulePath).createMediaRouter({
    readProfile: async (profileId) =>
      profileId === 'profile-1' ? profile : null,
    resolveProfile: async () => ({ profileId: 'profile-1', profile }),
    createCustomToken: async (uid) => `custom-token-${uid}`,
    verifyIdToken: async (token) => {
      if (token !== validIdToken) throw new Error('Invalid token');
      return { uid: 'user-1', profile_id: 'profile-1' };
    },
    createSwitchSession: async (input) => {
      calls.create = input;
      return {
        sessionId,
        sessionSecret,
        expiresAt: new Date(Date.now() + 60_000).toISOString(),
      };
    },
    readSwitchSession: async () => storedSession,
    refreshSwitchSession: async (input) => {
      calls.refresh = input;
      calls.refreshCount = (calls.refreshCount ?? 0) + 1;
      return refreshFails ? null : storedSession;
    },
    revokeSwitchSession: async (input) => {
      calls.revoke = input;
      return true;
    },
  }));
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));

  try {
    const responses = [];
    for (let attempt = 0; attempt < attempts; attempt++) {
      const response = await fetch(
        `http://127.0.0.1:${server.address().port}/media${path}`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${validIdToken}`,
          },
          body: JSON.stringify(body),
        },
      );
      responses.push({
        status: response.status,
        body: await response.json(),
      });
    }
    return {
      ...responses[responses.length - 1],
      responses,
      calls,
      sessionId,
      sessionSecret,
      hashSecret,
    };
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function hashPassword(password) {
  return require('crypto').createHash('sha256')
    .update(password.trim())
    .digest('hex');
}

async function postSession({ phone, password }) {
  let linkedAccount;
  let customTokenClaims;
  const app = express();
  app.use(express.json());
  app.use('/media', require(mediaModulePath).createMediaRouter({
    readProfile: async (phoneKey) => phoneKey === '967771234567'
      ? {
          id: phoneKey,
          password_hash: hashPassword('correct horse'),
          role: 'merchant',
        }
      : null,
    createCustomToken: async (uid, claims) => {
      customTokenClaims = claims;
      return `custom-token-${uid}`;
    },
    verifyIdToken: async () => ({ uid: 'user-1' }),
    linkAuthUid: async (phoneKey, uid) => {
      linkedAccount = { phoneKey, uid };
    },
  }));
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));

  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/media/session`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone, password }),
      },
    );
    return {
      status: response.status,
      body: await response.json(),
      linkedAccount,
      customTokenClaims,
    };
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('phone/password media session returns a Firebase custom token', async () => {
  const result = await postSession({
    phone: '٠٧٧١٢٣٤٥٦٧',
    password: 'correct horse',
  });

  assert.equal(result.status, 200);
  assert.deepEqual(result.body, {
    success: true,
    custom_token: 'custom-token-967771234567',
  });
  assert.deepEqual(result.linkedAccount, {
    phoneKey: '967771234567',
    uid: '967771234567',
  });
  assert.deepEqual(result.customTokenClaims, {
    profile_id: '967771234567',
    role: 'merchant',
    otp_verified: false,
  });
});

test('phone/password media session rejects invalid credentials', async () => {
  const result = await postSession({
    phone: '+967771234567',
    password: 'wrong password',
  });

  assert.equal(result.status, 401);
  assert.equal(result.body.error_code, 'invalid_credentials');
});

test('switch account session is bound to the authenticated profile', async () => {
  const result = await postSwitchSession({
    path: '/switch-sessions',
    body: {},
  });

  assert.equal(result.status, 201);
  assert.equal(result.body.success, true);
  assert.equal(result.body.session_id, result.sessionId);
  assert.equal(result.body.session_secret, result.sessionSecret);
  assert.deepEqual(result.calls.create, {
    uid: 'user-1',
    profileId: 'profile-1',
    role: 'merchant',
  });
});

test('restoring a saved account refreshes expiration without rotating its secret', async () => {
  const result = await postSwitchSession({
    path: '/switch-sessions/restore',
    body: {
      session_id: '123e4567-e89b-12d3-a456-426614174000',
      session_secret: 'a'.repeat(64),
    },
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.success, true);
  assert.equal(result.body.custom_token, 'custom-token-user-1');
  assert.equal(result.body.session_secret, result.sessionSecret);
  assert.equal(
    result.calls.refresh.secretHash,
    result.hashSecret(result.sessionSecret),
  );
  assert.equal(result.calls.refreshCount, 1);
});

test('restoring a saved account can be retried with the same secret', async () => {
  const result = await postSwitchSession({
    path: '/switch-sessions/restore',
    body: {
      session_id: '123e4567-e89b-12d3-a456-426614174000',
      session_secret: 'a'.repeat(64),
    },
    attempts: 2,
  });

  assert.deepEqual(
    result.responses.map((response) => response.status),
    [200, 200],
  );
  assert.deepEqual(
    result.responses.map((response) => response.body.session_secret),
    [result.sessionSecret, result.sessionSecret],
  );
  assert.equal(result.calls.refreshCount, 2);
});

test('restoring a saved account rejects an incorrect secret without rotating', async () => {
  const result = await postSwitchSession({
    path: '/switch-sessions/restore',
    body: {
      session_id: '123e4567-e89b-12d3-a456-426614174000',
      session_secret: 'b'.repeat(64),
    },
  });

  assert.equal(result.status, 401);
  assert.equal(result.body.error_code, 'invalid_switch_session');
  assert.equal(result.body.reason, 'secret_mismatch');
  assert.equal(result.calls.refresh, undefined);
});

test('restoring an expired saved account does not issue a custom token', async () => {
  const result = await postSwitchSession({
    path: '/switch-sessions/restore',
    body: {
      session_id: '123e4567-e89b-12d3-a456-426614174000',
      session_secret: 'a'.repeat(64),
    },
    expired: true,
  });

  assert.equal(result.status, 401);
  assert.equal(result.body.error_code, 'invalid_switch_session');
  assert.equal(result.body.reason, 'session_expired');
  assert.equal(result.calls.refresh, undefined);
});

test('a failed session refresh is reported as retryable', async () => {
  const result = await postSwitchSession({
    path: '/switch-sessions/restore',
    body: {
      session_id: '123e4567-e89b-12d3-a456-426614174000',
      session_secret: 'a'.repeat(64),
    },
    refreshFails: true,
  });

  assert.equal(result.status, 401);
  assert.equal(result.body.error_code, 'invalid_switch_session');
  assert.equal(result.body.reason, 'refresh_failed');
});

test('session refresh waits for the Firebase value before starting its transaction', async () => {
  const sessionSecret = 'a'.repeat(64);
  const secretHash = require('crypto').createHash('sha256')
    .update(sessionSecret)
    .digest('hex');
  const now = Date.now();
  let storedSession = {
    uid: 'user-1',
    profile_id: 'profile-1',
    secret_hash: secretHash,
    expires_at_ms: now + 60_000,
    absolute_expires_at_ms: now + 120_000,
  };
  let listener;
  const reference = {
    on: (_event, callback) => {
      listener = callback;
      setImmediate(() => {
        callback({ val: () => null });
        setImmediate(() => callback({ val: () => storedSession }));
      });
    },
    off: (_event, callback) => {
      if (listener === callback) listener = null;
    },
    transaction: async (update) => {
      assert.ok(listener);
      const updated = update(storedSession);
      if (updated === undefined) {
        return { committed: false, snapshot: { val: () => storedSession } };
      }
      storedSession = updated;
      return { committed: true, snapshot: { val: () => storedSession } };
    },
  };
  const dependencies = require(mediaModulePath).createFirebaseDependencies({
    database: () => ({
      ref: (path) => {
        assert.equal(path, 'auth_switch_sessions/session-1');
        return reference;
      },
    }),
  });

  const refreshed = await dependencies.refreshSwitchSession({
    sessionId: 'session-1',
    secretHash,
    now,
  });

  assert.equal(refreshed.secret_hash, secretHash);
  assert.ok(refreshed.expires_at_ms > now + 60_000);
  assert.equal(listener, null);
});

test('removing a saved account revokes its matching server session', async () => {
  const result = await postSwitchSession({
    path: '/switch-sessions/revoke',
    body: {
      session_id: '123e4567-e89b-12d3-a456-426614174000',
      session_secret: 'a'.repeat(64),
    },
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.success, true);
  assert.deepEqual(result.calls.revoke, {
    sessionId: result.sessionId,
    secretHash: result.hashSecret(result.sessionSecret),
  });
});

test('media upload rejects requests without a Firebase ID token', async () => {
  const bytes = Buffer.alloc(32);
  Buffer.from('ftyp').copy(bytes, 4);

  const result = await postMedia({ bytes, idToken: null });

  assert.equal(result.status, 401);
  assert.equal(result.body.error_code, 'authentication_required');
  assert.equal(result.githubRequest, undefined);
});

test('media upload does not accept the former shared upload token', async () => {
  const bytes = Buffer.alloc(32);
  Buffer.from('ftyp').copy(bytes, 4);

  const result = await postMedia({
    bytes,
    idToken: null,
    legacyUploadToken: 'former-shared-token',
  });

  assert.equal(result.status, 401);
  assert.equal(result.githubRequest, undefined);
});

test('media upload stores validated MP4 videos with an MP4 URL', async () => {
  const bytes = Buffer.alloc(32);
  Buffer.from('ftyp').copy(bytes, 4);

  const result = await postMedia({ bytes });

  assert.equal(result.status, 201);
  assert.match(result.githubRequest.url, /assets\/products\/.+\.mp4$/);
  assert.match(result.body.url, /raw\.githubusercontent\.com.+\.mp4$/);
  assert.equal(
    Buffer.from(result.githubRequest.body.content, 'base64')
      .toString('ascii', 4, 8),
    'ftyp',
  );
});

test('media upload rejects videos larger than 12 MiB', async () => {
  const bytes = Buffer.alloc(maxVideoBytes + 1);
  Buffer.from('ftyp').copy(bytes, 4);

  const result = await postMedia({ bytes });

  assert.equal(result.status, 413);
  assert.equal(result.githubRequest, undefined);
});

test('media upload stores product images in the products directory', async () => {
  const result = await postMedia({
    bytes: Buffer.from('product image'),
    contentType: 'image/jpeg',
    fileName: 'product.jpg',
  });

  assert.equal(result.status, 201);
  assert.match(result.githubRequest.url, /assets\/products\/.+\.jpg$/);
  assert.match(result.body.url, /raw\.githubusercontent\.com.+\.jpg$/);
});

test('media upload stores payment proof images in the receipts directory', async () => {
  const result = await postMedia({
    bytes: Buffer.from('payment proof'),
    contentType: 'image/jpeg',
    mediaType: 'receipts',
    fileName: 'receipt.jpg',
  });

  assert.equal(result.status, 201);
  assert.match(result.githubRequest.url, /assets\/receipts\/.+\.jpg$/);
  assert.match(result.body.url, /raw\.githubusercontent\.com.+\.jpg$/);
});

test('media upload stores promotion images in the promotions directory', async () => {
  const result = await postMedia({
    bytes: Buffer.from('promotion image'),
    contentType: 'image/png',
    mediaType: 'promotions',
    fileName: 'promotion.png',
  });

  assert.equal(result.status, 201);
  assert.match(result.githubRequest.url, /assets\/promotions\/.+\.png$/);
  assert.match(result.body.url, /raw\.githubusercontent\.com.+\.png$/);
});

test('media upload rejects videos for promotion images', async () => {
  const bytes = Buffer.alloc(32);
  Buffer.from('ftyp').copy(bytes, 4);

  const result = await postMedia({ bytes, mediaType: 'promotions' });

  assert.equal(result.status, 400);
  assert.equal(result.githubRequest, undefined);
});

test('media upload stores wallet logos in the wallets directory', async () => {
  const result = await postMedia({
    bytes: Buffer.from('wallet logo'),
    contentType: 'image/jpeg',
    mediaType: 'wallets',
    fileName: 'wallet-logo.jpg',
  });

  assert.equal(result.status, 201);
  assert.match(result.githubRequest.url, /assets\/wallets\/.+\.jpg$/);
  assert.match(result.body.url, /raw\.githubusercontent\.com.+\.jpg$/);
});