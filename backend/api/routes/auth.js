const express = require('express');
const { randomInt } = require('node:crypto');
const router = express.Router();

const otpStore = new Map();

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
    throw new Error('Wawp env vars missing: set WAWP_INSTANCE_ID and WAWP_ACCESS_TOKEN.');
  }

  return { apiUrl, instanceId, accessToken };
};

const sendWhatsAppOtp = async (phone, code) => {
  const { apiUrl, instanceId, accessToken } = getWawpConfig();
  const endpoint = new URL(`${apiUrl}/v2/send/text`);
  endpoint.search = new URLSearchParams({
    instance_id: instanceId,
    access_token: accessToken,
  }).toString();
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({
      chatId: `${phone.replace(/^\+/, '')}@c.us`,
      message: `رمز التحقق الخاص بك من SHEM هو ${code}. صالح لمدة 5 دقائق.`,
    }),
  });

  const responseText = await response.text();
  let data = {};
  try {
    data = responseText ? JSON.parse(responseText) : {};
  } catch (_) {
    data = {};
  }

  if (!response.ok || data?.error || data?.success === false) {
    throw new Error(`Wawp request failed with status ${response.status}`);
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
    otpStore.set(phone, {
      code,
      expiresAt: Date.now() + 5 * 60 * 1000,
    });

    await sendWhatsAppOtp(phone, code);
    return res.json({
      success: true,
      message: 'تم إرسال رمز التحقق عبر واتساب.',
      phone,
    });
  } catch (error) {
    const phone = normalizePhone(req.body?.phone ?? '');
    if (phone) otpStore.delete(phone);
    console.error('WhatsApp OTP delivery failed:', error.message);

    return res.status(502).json({
      success: false,
      error: 'تعذر إرسال رمز التحقق عبر واتساب. حاول مرة أخرى لاحقًا.',
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
