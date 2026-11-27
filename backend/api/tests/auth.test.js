const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const express = require('express');

const authRouter = require('../routes/auth');

async function startAuthApp(dependencies = {}) {
  const app = express();
  app.use(express.json());
  app.use('/auth', authRouter.createAuthRouter({
    readProfile: async () => null,
    createCustomToken: async (uid) => `custom-token-${uid}`,
    verifyIdToken: async () => ({ uid: 'test-user' }),
    resolveProfile: async () => ({ profileId: '', profile: null }),
    syncAuthIndex: async () => {},
    syncVerifiedEmail: async () => {},
    updateCustomClaims: async () => {},
    updateProfilePassword: async () => {},
    updateAuthPassword: async () => {},
    ...dependencies,
  }));

  return new Promise((resolve) => {
    const server = app.listen(0, () => resolve(server));
  });
}

function hashPassword(password) {
  return crypto.createHash('sha256').update(password.trim()).digest('hex');
}

test('request-otp sends a WhatsApp code through the Wawp OTP API', async () => {
  const originalFetch = global.fetch;
  const originalApiUrl = process.env.WAWP_API_URL;
  const originalInstanceId = process.env.WAWP_INSTANCE_ID;
  const originalToken = process.env.WAWP_ACCESS_TOKEN;

  let sentUrl = null;
  let sentPayload = null;

  global.fetch = async (url, options) => {
    const requestUrl = String(url);
    if (!requestUrl.includes('api.wawp.net')) {
      return originalFetch(url, options);
    }

    sentUrl = requestUrl;
    sentPayload = JSON.parse(options.body);
    assert.equal(options.headers.Authorization, undefined);
    return new Response(JSON.stringify({
      code: 'success',
      message: 'Verification code sent successfully',
      expires_in: 300,
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  };

  process.env.WAWP_API_URL = 'https://api.wawp.net';
  process.env.WAWP_INSTANCE_ID = 'demo-instance';
  process.env.WAWP_ACCESS_TOKEN = 'demo-token';

  const server = await startAuthApp();
  const { port } = server.address();

  try {
    const response = await fetch(`http://127.0.0.1:${port}/auth/request-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '0771234567' }),
    });

    const json = await response.json();
    assert.equal(response.status, 200);
    assert.equal(json.success, true);
    assert.match(json.message, /تم إرسال/i);
    assert.equal(
      sentUrl,
      'https://api.wawp.net/v2/auth/otp/send',
    );
    assert.equal(sentPayload.instance_id, 'demo-instance');
    assert.equal(sentPayload.access_token, 'demo-token');
    assert.equal(sentPayload.chatId, '967771234567');
    assert.equal(sentPayload.lang, 'ar');
    assert.equal(
      sentPayload.message,
      'رمز التحقق الخاص بك من SHEM هو {{otp}}. صالح لمدة 5 دقائق.',
    );
  } finally {
    server.close();
    global.fetch = originalFetch;
    if (originalApiUrl === undefined) delete process.env.WAWP_API_URL; else process.env.WAWP_API_URL = originalApiUrl;
    if (originalInstanceId === undefined) delete process.env.WAWP_INSTANCE_ID; else process.env.WAWP_INSTANCE_ID = originalInstanceId;
    if (originalToken === undefined) delete process.env.WAWP_ACCESS_TOKEN; else process.env.WAWP_ACCESS_TOKEN = originalToken;
  }
});

test('request-otp accepts a full international Yemeni phone number', async () => {
  const originalFetch = global.fetch;
  const originalApiUrl = process.env.WAWP_API_URL;
  const originalInstanceId = process.env.WAWP_INSTANCE_ID;
  const originalToken = process.env.WAWP_ACCESS_TOKEN;

  let sentPayload = null;
  process.env.WAWP_API_URL = 'https://api.wawp.net';
  process.env.WAWP_INSTANCE_ID = 'demo-instance';
  process.env.WAWP_ACCESS_TOKEN = 'demo-token';
  global.fetch = async (url, options) => {
    if (!String(url).includes('api.wawp.net')) {
      return originalFetch(url, options);
    }

    sentPayload = JSON.parse(options.body);
    return new Response(JSON.stringify({ code: 'success' }), { status: 200 });
  };

  const server = await startAuthApp();
  const { port } = server.address();

  try {
    const response = await fetch(`http://127.0.0.1:${port}/auth/request-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '967771831482' }),
    });
    const json = await response.json();

    assert.equal(response.status, 200);
    assert.equal(json.success, true);
    assert.equal(json.phone, '+967771831482');
    assert.equal(sentPayload.chatId, '967771831482');
  } finally {
    server.close();
    global.fetch = originalFetch;
    if (originalApiUrl === undefined) delete process.env.WAWP_API_URL; else process.env.WAWP_API_URL = originalApiUrl;
    if (originalInstanceId === undefined) delete process.env.WAWP_INSTANCE_ID; else process.env.WAWP_INSTANCE_ID = originalInstanceId;
    if (originalToken === undefined) delete process.env.WAWP_ACCESS_TOKEN; else process.env.WAWP_ACCESS_TOKEN = originalToken;
  }
});

test('signup OTP requests reject an existing profile before contacting Wawp', async () => {
  let requestedProfileKey;
  const server = await startAuthApp({
    readProfile: async (profileKey) => {
      requestedProfileKey = profileKey;
      return { id: profileKey };
    },
  });

  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/auth/request-otp`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          phone: '0771234567',
          for_signup: true,
        }),
      },
    );
    const json = await response.json();

    assert.equal(response.status, 409);
    assert.equal(json.error_code, 'account_exists');
    assert.equal(requestedProfileKey, '967771234567');
  } finally {
    server.close();
  }
});

test('verify-otp verifies the code with Wawp for the normalized phone number', async () => {
  const originalFetch = global.fetch;
  const originalApiUrl = process.env.WAWP_API_URL;
  const originalInstanceId = process.env.WAWP_INSTANCE_ID;
  const originalToken = process.env.WAWP_ACCESS_TOKEN;

  process.env.WAWP_API_URL = 'https://api.wawp.net';
  process.env.WAWP_INSTANCE_ID = 'demo-instance';
  process.env.WAWP_ACCESS_TOKEN = 'demo-token';

  let sentUrl = null;
  let sentPayload = null;
  global.fetch = async (url, options) => {
    const requestUrl = String(url);
    if (!requestUrl.includes('api.wawp.net')) {
      return originalFetch(url, options);
    }

    sentUrl = requestUrl;
    sentPayload = JSON.parse(options.body);
    return new Response(JSON.stringify({ code: 'success' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  };

  let tokenRequest;
  const server = await startAuthApp({
    createCustomToken: async (uid, claims) => {
      tokenRequest = { uid, claims };
      return 'otp-custom-token';
    },
  });
  const { port } = server.address();

  try {
    const response = await fetch(`http://127.0.0.1:${port}/auth/verify-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '771234567', otp: '123456' }),
    });

    const json = await response.json();
    assert.equal(response.status, 200);
    assert.equal(json.success, true);
    assert.equal(json.phone, '+967771234567');
    assert.equal(json.custom_token, 'otp-custom-token');
    assert.deepEqual(tokenRequest, {
      uid: '967771234567',
      claims: {
        profile_id: '967771234567',
        role: 'customer',
        otp_verified: true,
      },
    });
    assert.equal(sentUrl, 'https://api.wawp.net/v2/auth/otp/verify');
    assert.equal(sentPayload.instance_id, 'demo-instance');
    assert.equal(sentPayload.access_token, 'demo-token');
    assert.equal(sentPayload.chatId, '967771234567');
    assert.equal(sentPayload.code, '123456');
  } finally {
    server.close();
    global.fetch = originalFetch;
    if (originalApiUrl === undefined) delete process.env.WAWP_API_URL; else process.env.WAWP_API_URL = originalApiUrl;
    if (originalInstanceId === undefined) delete process.env.WAWP_INSTANCE_ID; else process.env.WAWP_INSTANCE_ID = originalInstanceId;
    if (originalToken === undefined) delete process.env.WAWP_ACCESS_TOKEN; else process.env.WAWP_ACCESS_TOKEN = originalToken;
  }
});

test('password change requires a valid Firebase session and current password', async () => {
  const profile = {
    id: '967771234567',
    auth_uid: 'test-user',
    password_hash: hashPassword('old-password'),
  };
  let savedHash;
  let savedAuthPassword;
  const server = await startAuthApp({
    verifyIdToken: async (token) => {
      assert.equal(token, 'valid-id-token');
      return { uid: 'test-user', profile_id: '967771234567' };
    },
    resolveProfile: async () => ({
      profileId: '967771234567',
      profile,
    }),
    updateProfilePassword: async (_profileId, passwordHash) => {
      savedHash = passwordHash;
    },
    updateAuthPassword: async (_uid, password) => {
      savedAuthPassword = password;
    },
  });

  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/auth/password/change`,
      {
        method: 'POST',
        headers: {
          Authorization: 'Bearer valid-id-token',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          current_password: 'old-password',
          new_password: 'new-password',
        }),
      },
    );
    const json = await response.json();

    assert.equal(response.status, 200);
    assert.equal(json.success, true);
    assert.equal(savedHash, hashPassword('new-password'));
    assert.equal(savedAuthPassword, 'new-password');
  } finally {
    server.close();
  }
});

test('password change rejects an incorrect current password', async () => {
  let updated = false;
  const server = await startAuthApp({
    verifyIdToken: async () => ({
      uid: 'test-user',
      profile_id: '967771234567',
    }),
    resolveProfile: async () => ({
      profileId: '967771234567',
      profile: {
        id: '967771234567',
        auth_uid: 'test-user',
        password_hash: hashPassword('old-password'),
      },
    }),
    updateProfilePassword: async () => {
      updated = true;
    },
  });

  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/auth/password/change`,
      {
        method: 'POST',
        headers: {
          Authorization: 'Bearer valid-id-token',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          current_password: 'incorrect-password',
          new_password: 'new-password',
        }),
      },
    );

    assert.equal(response.status, 401);
    assert.equal(updated, false);
  } finally {
    server.close();
  }
});

test('OTP-authenticated password change does not require the old password', async () => {
  let updated = false;
  const server = await startAuthApp({
    verifyIdToken: async () => ({
      uid: 'test-user',
      profile_id: '967771234567',
      otp_verified: true,
    }),
    resolveProfile: async () => ({
      profileId: '967771234567',
      profile: {
        id: '967771234567',
        auth_uid: 'test-user',
        password_hash: hashPassword('old-password'),
      },
    }),
    updateProfilePassword: async () => {
      updated = true;
    },
  });

  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/auth/password/change`,
      {
        method: 'POST',
        headers: {
          Authorization: 'Bearer valid-id-token',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ new_password: 'new-password' }),
      },
    );

    assert.equal(response.status, 200);
    assert.equal(updated, true);
  } finally {
    server.close();
  }
});

test('session sync grants claims only for a profile linked to the Firebase UID', async () => {
  let syncedIndex;
  let syncedClaims;
  const server = await startAuthApp({
    verifyIdToken: async () => ({
      uid: 'linked-user',
      profile_id: 'merchant-profile',
    }),
    resolveProfile: async () => ({
      profileId: 'merchant-profile',
      profile: {
        id: 'merchant-profile',
        auth_uid: 'linked-user',
        phone: '+967771234567',
        role: 'merchant',
      },
    }),
    syncAuthIndex: async (...args) => {
      syncedIndex = args;
    },
    updateCustomClaims: async (...args) => {
      syncedClaims = args;
    },
  });

  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/auth/sync-session`,
      {
        method: 'POST',
        headers: { Authorization: 'Bearer valid-id-token' },
      },
    );
    const json = await response.json();

    assert.equal(response.status, 200);
    assert.equal(json.profile_id, 'merchant-profile');
    assert.equal(json.role, 'merchant');
    assert.deepEqual(syncedIndex, [
      'linked-user',
      'merchant-profile',
      {
        id: 'merchant-profile',
        auth_uid: 'linked-user',
        phone: '+967771234567',
        role: 'merchant',
      },
    ]);
    assert.deepEqual(syncedClaims, [
      'linked-user',
      { profile_id: 'merchant-profile', role: 'merchant' },
    ]);
  } finally {
    server.close();
  }
});

test('session sync persists a verified Firebase email on its linked profile', async () => {
  const profile = {
    id: 'customer-profile',
    auth_uid: 'linked-user',
    phone: '+967771234567',
    email: 'old@example.com',
    email_verified: false,
    pending_email: 'new@example.com',
    role: 'customer',
  };
  let syncedProfileEmail;
  let syncedIndex;
  const server = await startAuthApp({
    verifyIdToken: async () => ({
      uid: 'linked-user',
      email: 'New@Example.com',
      email_verified: true,
    }),
    resolveProfile: async () => ({
      profileId: 'customer-profile',
      profile,
    }),
    syncVerifiedEmail: async (...args) => {
      syncedProfileEmail = args;
    },
    syncAuthIndex: async (...args) => {
      syncedIndex = args;
    },
  });

  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/auth/sync-session`,
      {
        method: 'POST',
        headers: { Authorization: 'Bearer valid-id-token' },
      },
    );

    assert.equal(response.status, 200);
    assert.deepEqual(syncedProfileEmail, [
      'customer-profile',
      'new@example.com',
    ]);
    assert.deepEqual(syncedIndex, [
      'linked-user',
      'customer-profile',
      {
        ...profile,
        email: 'new@example.com',
        email_verified: true,
        pending_email: null,
      },
    ]);
  } finally {
    server.close();
  }
});

test('session sync ignores email claims that Firebase has not verified', async () => {
  let emailSynced = false;
  const server = await startAuthApp({
    verifyIdToken: async () => ({
      uid: 'linked-user',
      email: 'unverified@example.com',
      email_verified: false,
    }),
    resolveProfile: async () => ({
      profileId: 'customer-profile',
      profile: {
        id: 'customer-profile',
        auth_uid: 'linked-user',
        email: 'current@example.com',
        email_verified: true,
        role: 'customer',
      },
    }),
    syncVerifiedEmail: async () => {
      emailSynced = true;
    },
  });

  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/auth/sync-session`,
      {
        method: 'POST',
        headers: { Authorization: 'Bearer valid-id-token' },
      },
    );

    assert.equal(response.status, 200);
    assert.equal(emailSynced, false);
  } finally {
    server.close();
  }
});

test('session sync rejects an auth-index mapping without a verified profile link', async () => {
  let synced = false;
  const server = await startAuthApp({
    verifyIdToken: async () => ({ uid: 'attacker' }),
    resolveProfile: async () => ({
      profileId: 'victim-profile',
      profile: {
        id: 'victim-profile',
        phone: '+967771234567',
        role: 'admin',
      },
    }),
    syncAuthIndex: async () => {
      synced = true;
    },
    updateCustomClaims: async () => {
      synced = true;
    },
  });

  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/auth/sync-session`,
      {
        method: 'POST',
        headers: { Authorization: 'Bearer valid-id-token' },
      },
    );

    assert.equal(response.status, 403);
    assert.equal(synced, false);
  } finally {
    server.close();
  }
});

test('verify-otp rejects a code that Wawp reports as invalid', async () => {
  const originalFetch = global.fetch;
  const originalApiUrl = process.env.WAWP_API_URL;
  const originalInstanceId = process.env.WAWP_INSTANCE_ID;
  const originalToken = process.env.WAWP_ACCESS_TOKEN;

  process.env.WAWP_API_URL = 'https://api.wawp.net';
  process.env.WAWP_INSTANCE_ID = 'demo-instance';
  process.env.WAWP_ACCESS_TOKEN = 'demo-token';
  global.fetch = async (url, options) => {
    if (!String(url).includes('api.wawp.net')) {
      return originalFetch(url, options);
    }

    return new Response(JSON.stringify({ code: 'invalid_otp' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  };

  const server = await startAuthApp();
  const { port } = server.address();

  try {
    const response = await fetch(`http://127.0.0.1:${port}/auth/verify-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '0771234567', otp: '123456' }),
    });
    const json = await response.json();

    assert.equal(response.status, 400);
    assert.equal(json.success, false);
    assert.equal(json.error_code, 'WAWP_OTP_INVALID');
    assert.match(json.error, /غير صحيح/);
  } finally {
    server.close();
    global.fetch = originalFetch;
    if (originalApiUrl === undefined) delete process.env.WAWP_API_URL; else process.env.WAWP_API_URL = originalApiUrl;
    if (originalInstanceId === undefined) delete process.env.WAWP_INSTANCE_ID; else process.env.WAWP_INSTANCE_ID = originalInstanceId;
    if (originalToken === undefined) delete process.env.WAWP_ACCESS_TOKEN; else process.env.WAWP_ACCESS_TOKEN = originalToken;
  }
});

test('request-otp reports Wawp delivery failures', async () => {
  const originalFetch = global.fetch;
  const originalApiUrl = process.env.WAWP_API_URL;
  const originalInstanceId = process.env.WAWP_INSTANCE_ID;
  const originalToken = process.env.WAWP_ACCESS_TOKEN;

  process.env.WAWP_API_URL = 'https://api.wawp.net';
  process.env.WAWP_INSTANCE_ID = 'demo-instance';
  process.env.WAWP_ACCESS_TOKEN = 'demo-token';
  global.fetch = async (url, options) => {
    if (!String(url).includes('api.wawp.net')) {
      return originalFetch(url, options);
    }

    return new Response(JSON.stringify({ success: false, error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  };

  const server = await startAuthApp();
  const { port } = server.address();

  try {
    const response = await fetch(`http://127.0.0.1:${port}/auth/request-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '0771234567' }),
    });

    const json = await response.json();
    assert.equal(response.status, 502);
    assert.equal(json.success, false);
    assert.equal(json.error_code, 'WAWP_AUTH_FAILED');
  } finally {
    server.close();
    global.fetch = originalFetch;
    if (originalApiUrl === undefined) delete process.env.WAWP_API_URL; else process.env.WAWP_API_URL = originalApiUrl;
    if (originalInstanceId === undefined) delete process.env.WAWP_INSTANCE_ID; else process.env.WAWP_INSTANCE_ID = originalInstanceId;
    if (originalToken === undefined) delete process.env.WAWP_ACCESS_TOKEN; else process.env.WAWP_ACCESS_TOKEN = originalToken;
  }
});

test('request-otp explains when Wawp cannot find the configured session', async () => {
  const originalFetch = global.fetch;
  const originalApiUrl = process.env.WAWP_API_URL;
  const originalInstanceId = process.env.WAWP_INSTANCE_ID;
  const originalToken = process.env.WAWP_ACCESS_TOKEN;

  process.env.WAWP_API_URL = 'https://api.wawp.net';
  process.env.WAWP_INSTANCE_ID = 'missing-instance';
  process.env.WAWP_ACCESS_TOKEN = 'demo-token';
  global.fetch = async (url, options) => {
    if (!String(url).includes('api.wawp.net')) {
      return originalFetch(url, options);
    }

    return new Response(JSON.stringify({
      code: 'invalid_session',
      message: 'Session not found',
    }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  };

  const server = await startAuthApp();
  const { port } = server.address();

  try {
    const response = await fetch(`http://127.0.0.1:${port}/auth/request-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '0771234567' }),
    });
    const json = await response.json();

    assert.equal(response.status, 502);
    assert.equal(json.success, false);
    assert.equal(json.error_code, 'WAWP_SESSION_NOT_FOUND');
    assert.match(json.error, /WAWP_INSTANCE_ID/);
  } finally {
    server.close();
    global.fetch = originalFetch;
    if (originalApiUrl === undefined) delete process.env.WAWP_API_URL; else process.env.WAWP_API_URL = originalApiUrl;
    if (originalInstanceId === undefined) delete process.env.WAWP_INSTANCE_ID; else process.env.WAWP_INSTANCE_ID = originalInstanceId;
    if (originalToken === undefined) delete process.env.WAWP_ACCESS_TOKEN; else process.env.WAWP_ACCESS_TOKEN = originalToken;
  }
});

test('request-otp reports missing Wawp credentials without sending a request', async () => {
  const originalFetch = global.fetch;
  const originalInstanceId = process.env.WAWP_INSTANCE_ID;
  const originalToken = process.env.WAWP_ACCESS_TOKEN;

  delete process.env.WAWP_INSTANCE_ID;
  delete process.env.WAWP_ACCESS_TOKEN;
  global.fetch = async (url, options) => {
    if (!String(url).includes('api.wawp.net')) {
      return originalFetch(url, options);
    }
    throw new Error('Wawp fetch should not be called without credentials');
  };

  const server = await startAuthApp();
  const { port } = server.address();

  try {
    const response = await fetch(`http://127.0.0.1:${port}/auth/request-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '0771234567' }),
    });
    const json = await response.json();

    assert.equal(response.status, 503);
    assert.equal(json.success, false);
    assert.equal(json.error_code, 'WAWP_NOT_CONFIGURED');
  } finally {
    server.close();
    global.fetch = originalFetch;
    if (originalInstanceId === undefined) delete process.env.WAWP_INSTANCE_ID; else process.env.WAWP_INSTANCE_ID = originalInstanceId;
    if (originalToken === undefined) delete process.env.WAWP_ACCESS_TOKEN; else process.env.WAWP_ACCESS_TOKEN = originalToken;
  }
});

test('request-otp rejects a non-JSON successful Wawp response', async () => {
  const originalFetch = global.fetch;
  const originalApiUrl = process.env.WAWP_API_URL;
  const originalInstanceId = process.env.WAWP_INSTANCE_ID;
  const originalToken = process.env.WAWP_ACCESS_TOKEN;

  process.env.WAWP_API_URL = 'https://api.wawp.net';
  process.env.WAWP_INSTANCE_ID = 'demo-instance';
  process.env.WAWP_ACCESS_TOKEN = 'demo-token';
  global.fetch = async (url, options) => {
    if (!String(url).includes('api.wawp.net')) {
      return originalFetch(url, options);
    }

    return new Response('message sent', { status: 200 });
  };

  const server = await startAuthApp();
  const { port } = server.address();

  try {
    const response = await fetch(`http://127.0.0.1:${port}/auth/request-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '0771234567' }),
    });
    const json = await response.json();

    assert.equal(response.status, 502);
    assert.equal(json.success, false);
    assert.equal(json.error_code, 'WAWP_INVALID_RESPONSE');
  } finally {
    server.close();
    global.fetch = originalFetch;
    if (originalApiUrl === undefined) delete process.env.WAWP_API_URL; else process.env.WAWP_API_URL = originalApiUrl;
    if (originalInstanceId === undefined) delete process.env.WAWP_INSTANCE_ID; else process.env.WAWP_INSTANCE_ID = originalInstanceId;
    if (originalToken === undefined) delete process.env.WAWP_ACCESS_TOKEN; else process.env.WAWP_ACCESS_TOKEN = originalToken;
  }
});
