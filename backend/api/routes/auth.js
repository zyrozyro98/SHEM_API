const express = require('express');
const { randomInt } = require('node:crypto');

const router = express.Router();
const otpStore = new Map();

function normalizePhone(value = '') {
  const digits = String(value)
    .replace(/[\u0660-\u0669\u06F0-\u06F9]/g, (char) => {
      const code = char.charCodeAt(0);
      const base = code >= 0x06f0 ? 0x06f0 : 0x0660;
      return String.fromCharCode(0x30 + code - base);
    })
    .replace(/\D/g, '');

  if (!digits) return '';

  const withoutPrefix = digits.startsWith('00') ? digits.slice(2) : digits;
  const localNumber = withoutPrefix.startsWith('967')
    ? withoutPrefix.slice(3)
    : withoutPrefix.startsWith('0')
      ? withoutPrefix.slice(1)
      : withoutPrefix;

  return /^\d{9}$/.test(localNumber) ? `+967${localNumber}` : '';
}

async function sendWhatsAppOtp(phone, code) {
  const apiUrl = (process.env.WAWP_API_URL || 'https://api.wawp.net')
    .replace(/\/+$/, '');
  const instanceId = process.env.WAWP_INSTANCE_ID;
  const accessToken = process.env.WAWP_ACCESS_TOKEN;

  if (!instanceId || !accessToken) {
    throw new Error('WAWP_INSTANCE_ID or WAWP_ACCESS_TOKEN is not configured');
  }

  const response = await fetch(`${apiUrl}/v2/send/text`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({
      instance_id: instanceId,
      access_token: accessToken,
      chatId: `${phone.slice(1)}@c.us`,
      message: `رمز التحقق الخاص بك من SHEM هو ${code}. صالح لمدة 5 دقائق.`,
    }),
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok || data.error || data.success === false) {
    throw new Error(`Wawp returned HTTP ${response.status}`);
  }
}

router.post('/request-otp', async (req, res) => {
  const phone = normalizePhone(req.body?.phone);

  if (!phone) {
    return res.status(400).json({
      success: false,
      error: 'يرجى إدخال رقم الهاتف اليمني الصحيح',
    });
  }

  try {
    const code = String(randomInt(100000, 1000000));
    await sendWhatsAppOtp(phone, code);
    otpStore.set(phone, { code, expiresAt: Date.now() + 5 * 60 * 1000 });

    return res.json({
      success: true,
      message: 'تم إرسال رمز التحقق عبر واتساب.',
      phone,
    });
  } catch (error) {
    console.error('WhatsApp OTP delivery failed:', error.message);
    return res.status(502).json({
      success: false,
      error: 'تعذر إرسال رمز التحقق عبر واتساب. حاول مرة أخرى لاحقًا.',
    });
  }
});

router.post('/verify-otp', (req, res) => {
  const phone = normalizePhone(req.body?.phone);
  const otp = String(req.body?.otp ?? '')
    .replace(/[\u0660-\u0669\u06F0-\u06F9]/g, (char) => {
      const code = char.charCodeAt(0);
      const base = code >= 0x06f0 ? 0x06f0 : 0x0660;
      return String.fromCharCode(0x30 + code - base);
    })
    .replace(/\D/g, '');

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

  if (!/^\d{6}$/.test(otp) || otp !== record.code) {
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
    user: { phone },
  });
});

module.exports = router;
