const express = require('express');
const router = express.Router();

class WawpError extends Error {
  constructor(message, code, statusCode) {
    super(message);
    this.name = 'WawpError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

const normalizePhone = (value = '') => {
  const digits = String(value)
    .trim()
    .replace(/[\u0660-\u0669\u06F0-\u06F9]/g, (char) => {
      const code = char.charCodeAt(0);
      const base = code >= 0x06f0 ? 0x06f0 : 0x0660;
      return String.fromCharCode(0x30 + (code - base));
    })
    .replace(/\D/g, '');

  if (!digits) return '';
  const withoutPrefix = digits.startsWith('00') ? digits.slice(2) : digits;
  const withoutCountry = withoutPrefix.startsWith('967')
    ? withoutPrefix.slice(3)
    : withoutPrefix.startsWith('0')
      ? withoutPrefix.slice(1)
      : withoutPrefix;

  if (!withoutCountry || withoutCountry.length !== 9) return '';
  return `+967${withoutCountry}`;
};

const getWawpConfig = () => {
  const apiUrl = (process.env.WAWP_API_URL || 'https://api.wawp.net')
    .replace(/\/+$/, '');
  const instanceId = process.env.WAWP_INSTANCE_ID;
  const accessToken = process.env.WAWP_ACCESS_TOKEN;

  if (!instanceId || !accessToken) {
    throw new WawpError(
      'Wawp credentials are not configured',
      'WAWP_NOT_CONFIGURED',
      503,
    );
  }

  return { apiUrl, instanceId, accessToken };
};

const callWawp = async (path, payload) => {
  const { apiUrl, instanceId, accessToken } = getWawpConfig();
  const endpoint = new URL(`${apiUrl}${path}`);
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    signal: AbortSignal.timeout(15000),
    body: JSON.stringify({
      instance_id: instanceId,
      access_token: accessToken,
      ...payload,
    }),
  });

  const responseText = await response.text();
  let data;
  try {
    data = responseText ? JSON.parse(responseText) : null;
  } catch {
    if (response.ok) {
      throw new WawpError(
        'Wawp returned a non-JSON success response',
        'WAWP_INVALID_RESPONSE',
        502,
      );
    }
  }

  if (!response.ok) {
    const providerCode = String(data?.code ?? data?.error_code ?? '')
      .toLowerCase();
    const code = response.status === 401
      ? 'WAWP_AUTH_FAILED'
      : response.status === 429
        ? 'WAWP_RATE_LIMITED'
        : response.status === 400
          ? 'WAWP_OTP_INVALID'
      : response.status === 404 &&
          ['invalid_session', 'session_not_found'].includes(providerCode)
        ? 'WAWP_SESSION_NOT_FOUND'
        : `WAWP_HTTP_${response.status}`;
    throw new WawpError(
      `Wawp request failed with status ${response.status}`,
      code,
      code === 'WAWP_RATE_LIMITED' ? 429
        : code === 'WAWP_OTP_INVALID' ? 400 : 502,
    );
  }

  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new WawpError(
      'Wawp returned an invalid response',
      'WAWP_INVALID_RESPONSE',
      502,
    );
  }

  const providerCode = String(data.code ?? '').toLowerCase();
  if (
    providerCode !== 'success' ||
    data.error ||
    data.success === false ||
    ['error', 'failed', 'failure'].includes(
      String(data.status ?? '').toLowerCase(),
    )
  ) {
    const isInvalidOtp = [
      'invalid_otp',
      'invalid_code',
      'otp_expired',
      'expired_otp',
    ].includes(providerCode);
    throw new WawpError(
      `Wawp rejected the request: ${providerCode || 'unknown'}`,
      isInvalidOtp ? 'WAWP_OTP_INVALID' : 'WAWP_REQUEST_REJECTED',
      isInvalidOtp ? 400 : 502,
    );
  }

  return data;
};

const sendWhatsAppOtp = (phone) => callWawp('/v2/auth/otp/send', {
  chatId: phone.replace(/^\+/, ''),
  lang: 'ar',
  message: 'رمز التحقق الخاص بك من SHEM هو {{otp}}. صالح لمدة 5 دقائق.',
});

const verifyWhatsAppOtp = (phone, code) => callWawp('/v2/auth/otp/verify', {
  chatId: phone.replace(/^\+/, ''),
  code,
});

router.post('/request-otp', async (req, res) => {
  try {
    const rawPhone = req.body?.phone ?? '';
    const phone = normalizePhone(rawPhone);

    if (!phone || !/^\+967[0-9]{9}$/.test(phone)) {
      return res.status(400).json({
        success: false,
        error: 'يرجى إدخال رقم الهاتف اليمني الصحيح',
      });
    }

    await sendWhatsAppOtp(phone);
    return res.json({
      success: true,
      message: 'تم إرسال رمز التحقق عبر واتساب.',
      phone,
    });
  } catch (error) {
    const code = error instanceof WawpError
      ? error.code
      : 'WAWP_DELIVERY_FAILED';
    console.error(
      'WhatsApp OTP delivery failed:',
      code,
      error.message,
    );

    return res.status(error instanceof WawpError ? error.statusCode : 502).json({
      success: false,
      error_code: code,
      error: code === 'WAWP_NOT_CONFIGURED'
        ? 'خدمة واتساب غير مُهيأة على الخادم. يرجى التواصل مع الدعم.'
        : code === 'WAWP_AUTH_FAILED'
          ? 'بيانات اتصال واتساب غير صالحة. يرجى التواصل مع الدعم.'
          : code === 'WAWP_SESSION_NOT_FOUND'
            ? 'جلسة واتساب غير موجودة أو غير نشطة. تحقق من WAWP_INSTANCE_ID وحالة الجلسة في لوحة Wawp.'
            : code === 'WAWP_RATE_LIMITED'
              ? 'تم طلب رمز تحقق مؤخرًا. انتظر قليلًا ثم حاول مرة أخرى.'
          : 'تعذر إرسال رمز التحقق عبر واتساب. حاول مرة أخرى لاحقًا.',
    });
  }
});

router.post('/verify-otp', async (req, res) => {
  try {
    const phone = normalizePhone(req.body?.phone ?? '');
    const otp = String(req.body?.otp ?? '').replace(/\D/g, '');

    if (!phone) {
      return res.status(400).json({
        success: false,
        error: 'رقم الهاتف غير صالح',
      });
    }

    if (otp.length !== 6) {
      return res.status(400).json({
        success: false,
        error: 'رمز التحقق غير صحيح',
      });
    }

    await verifyWhatsAppOtp(phone, otp);
    return res.json({
      success: true,
      message: 'تم التحقق من رقم الهاتف بنجاح',
      phone,
      access_token: `wa-${Date.now()}`,
      user: { phone },
    });
  } catch (error) {
    const code = error instanceof WawpError
      ? error.code
      : 'WAWP_VERIFICATION_FAILED';
    console.error('WhatsApp OTP verification failed:', code, error.message);
    return res.status(error instanceof WawpError ? error.statusCode : 502)
      .json({
        success: false,
        error_code: code,
        error: code === 'WAWP_NOT_CONFIGURED'
          ? 'خدمة واتساب غير مُهيأة على الخادم. يرجى التواصل مع الدعم.'
          : code === 'WAWP_AUTH_FAILED'
            ? 'بيانات اتصال واتساب غير صالحة. يرجى التواصل مع الدعم.'
            : code === 'WAWP_RATE_LIMITED'
              ? 'تجاوزت عدد محاولات التحقق. انتظر قليلًا ثم حاول مرة أخرى.'
              : code === 'WAWP_SESSION_NOT_FOUND'
                ? 'جلسة واتساب غير موجودة أو غير نشطة. تحقق من الإعدادات.'
                : 'رمز التحقق غير صحيح أو انتهت صلاحيته.',
      });
  }
});

module.exports = router;
