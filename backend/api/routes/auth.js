const express = require('express');
const { randomInt } = require('node:crypto');
const router = express.Router();

const otpStore = new Map();
const OTP_LIFETIME_MS = 5 * 60 * 1000;

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

const sendWhatsAppOtp = async (phone, code) => {
  const { apiUrl, instanceId, accessToken } = getWawpConfig();
  const endpoint = new URL(`${apiUrl}/v2/send/text`);
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
      chatId: `${phone.replace(/^\+/, '')}@c.us`,
      message: `رمز التحقق الخاص بك من SHEM هو ${code}. صالح لمدة 5 دقائق.`,
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
    const code = response.status === 401
      ? 'WAWP_AUTH_FAILED'
      : `WAWP_HTTP_${response.status}`;
    throw new WawpError(
      `Wawp request failed with status ${response.status}`,
      code,
      502,
    );
  }

  const resultStatus = String(data?.status ?? '').toLowerCase();
  if (
    !data ||
    typeof data !== 'object' ||
    data.error ||
    data.success === false ||
    ['error', 'failed', 'failure'].includes(resultStatus)
  ) {
    throw new WawpError(
      'Wawp rejected the message',
      'WAWP_MESSAGE_REJECTED',
      502,
    );
  }

  return data;
};

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

    const code = String(randomInt(100000, 1000000));
    await sendWhatsAppOtp(phone, code);
    otpStore.set(phone, {
      code,
      expiresAt: Date.now() + OTP_LIFETIME_MS,
    });
    return res.json({
      success: true,
      message: 'تم إرسال رمز التحقق عبر واتساب.',
      phone,
    });
  } catch (error) {
    const phone = normalizePhone(req.body?.phone ?? '');
    if (phone) otpStore.delete(phone);
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
          : 'تعذر إرسال رمز التحقق عبر واتساب. حاول مرة أخرى لاحقًا.',
    });
  }
});

router.post('/verify-otp', (req, res) => {
  try {
    const phone = normalizePhone(req.body?.phone ?? '');
    const otp = String(req.body?.otp ?? '').replace(/\D/g, '');

    if (!phone) {
      return res.status(400).json({
        success: false,
        error: 'رقم الهاتف غير صالح',
      });
    }

    const record = otpStore.get(phone);
    if (!record) {
      return res.status(400).json({
        success: false,
        error: 'لم يتم إرسال رمز تحقق لهذا الرقم',
      });
    }

    if (Date.now() > record.expiresAt) {
      otpStore.delete(phone);
      return res.status(400).json({
        success: false,
        error: 'انتهت صلاحية رمز التحقق. أعد الطلب من جديد.',
      });
    }

    if (otp.length !== 6 || otp !== record.code) {
      return res.status(400).json({
        success: false,
        error: 'رمز التحقق غير صحيح',
      });
    }

    otpStore.delete(phone);
    return res.json({
      success: true,
      message: 'تم التحقق من رقم الهاتف بنجاح',
      phone,
      access_token: `wa-${Date.now()}`,
      user: { phone },
    });
  } catch (error) {
    return res.status(400).json({
      success: false,
      error: error.message || 'فشل التحقق',
    });
  }
});

router.otpStore = otpStore;
module.exports = router;
