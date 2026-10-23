const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const authRouter = require('../routes/auth');

async function startAuthApp() {
  const app = express();
  app.use(express.json());
  app.use('/auth', authRouter);

  return new Promise((resolve) => {
    const server = app.listen(0, () => resolve(server));
  });
}

test('request-otp sends a WhatsApp code via Wawp and stores it for verification', async () => {
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
    return new Response(JSON.stringify({ id: 'abc123', sent: true }), {
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
      'https://api.wawp.net/v2/send/text?instance_id=demo-instance&access_token=demo-token',
    );
    assert.equal(sentPayload.chatId, '967771234567@c.us');
    assert.equal(sentPayload.reply_to, undefined);
    assert.match(sentPayload.message, /رمز التحقق/i);
    assert.match(sentPayload.message, /5 دقائق/);

    const otp = authRouter.otpStore.get('+967771234567');
    assert.ok(otp && otp.code.length === 6);
    assert.ok(otp.expiresAt > Date.now());
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
    return new Response(JSON.stringify({ sent: true }), { status: 200 });
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
    assert.equal(sentPayload.chatId, '967771831482@c.us');
  } finally {
    server.close();
    global.fetch = originalFetch;
    if (originalApiUrl === undefined) delete process.env.WAWP_API_URL; else process.env.WAWP_API_URL = originalApiUrl;
    if (originalInstanceId === undefined) delete process.env.WAWP_INSTANCE_ID; else process.env.WAWP_INSTANCE_ID = originalInstanceId;
    if (originalToken === undefined) delete process.env.WAWP_ACCESS_TOKEN; else process.env.WAWP_ACCESS_TOKEN = originalToken;
  }
});

test('verify-otp accepts the matching code for the same phone number', async () => {
  const originalFetch = global.fetch;
  const originalApiUrl = process.env.WAWP_API_URL;
  const originalInstanceId = process.env.WAWP_INSTANCE_ID;
  const originalToken = process.env.WAWP_ACCESS_TOKEN;

  process.env.WAWP_API_URL = 'https://api.wawp.net';
  process.env.WAWP_INSTANCE_ID = 'demo-instance';
  process.env.WAWP_ACCESS_TOKEN = 'demo-token';

  global.fetch = async (url, options) => {
    const requestUrl = String(url);
    if (!requestUrl.includes('api.wawp.net')) {
      return originalFetch(url, options);
    }

    return new Response(JSON.stringify({ id: 'abc123', sent: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  };

  const server = await startAuthApp();
  const { port } = server.address();

  try {
    await fetch(`http://127.0.0.1:${port}/auth/request-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '771234567' }),
    });

    const otp = authRouter.otpStore.get('+967771234567');
    assert.ok(otp && otp.code);

    const response = await fetch(`http://127.0.0.1:${port}/auth/verify-otp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '771234567', otp: otp.code }),
    });

    const json = await response.json();
    assert.equal(response.status, 200);
    assert.equal(json.success, true);
    assert.equal(json.phone, '+967771234567');
  } finally {
    server.close();
    global.fetch = originalFetch;
    if (originalApiUrl === undefined) delete process.env.WAWP_API_URL; else process.env.WAWP_API_URL = originalApiUrl;
    if (originalInstanceId === undefined) delete process.env.WAWP_INSTANCE_ID; else process.env.WAWP_INSTANCE_ID = originalInstanceId;
    if (originalToken === undefined) delete process.env.WAWP_ACCESS_TOKEN; else process.env.WAWP_ACCESS_TOKEN = originalToken;
  }
});

test('request-otp reports Wawp delivery failures without storing the code', async () => {
  const originalFetch = global.fetch;
  const originalApiUrl = process.env.WAWP_API_URL;
  const originalInstanceId = process.env.WAWP_INSTANCE_ID;
  const originalToken = process.env.WAWP_ACCESS_TOKEN;

  process.env.WAWP_API_URL = 'https://api.wawp.net';
  process.env.WAWP_INSTANCE_ID = 'demo-instance';
  process.env.WAWP_ACCESS_TOKEN = 'demo-token';
  authRouter.otpStore.delete('+967771234567');
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
    assert.equal(authRouter.otpStore.has('+967771234567'), false);
  } finally {
    server.close();
    global.fetch = originalFetch;
    if (originalApiUrl === undefined) delete process.env.WAWP_API_URL; else process.env.WAWP_API_URL = originalApiUrl;
    if (originalInstanceId === undefined) delete process.env.WAWP_INSTANCE_ID; else process.env.WAWP_INSTANCE_ID = originalInstanceId;
    if (originalToken === undefined) delete process.env.WAWP_ACCESS_TOKEN; else process.env.WAWP_ACCESS_TOKEN = originalToken;
  }
});
