const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const mediaModulePath = require.resolve('../routes/media');
const nodeFetchPath = require.resolve('node-fetch');
const originalNodeFetch = require(nodeFetchPath);
const maxVideoBytes = 12 * 1024 * 1024;
const validIdToken = 'test-firebase-id-token';

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

function hashPassword(password) {
  return require('crypto').createHash('sha256')
    .update(password.trim())
    .digest('hex');
}

async function postSession({ phone, password }) {
  let linkedAccount;
  const app = express();
  app.use(express.json());
  app.use('/media', require(mediaModulePath).createMediaRouter({
    readProfile: async (phoneKey) => phoneKey === '967771234567'
      ? {
          id: phoneKey,
          password_hash: hashPassword('correct horse'),
        }
      : null,
    createCustomToken: async (uid) => `custom-token-${uid}`,
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
});

test('phone/password media session rejects invalid credentials', async () => {
  const result = await postSession({
    phone: '+967771234567',
    password: 'wrong password',
  });

  assert.equal(result.status, 401);
  assert.equal(result.body.error_code, 'invalid_credentials');
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