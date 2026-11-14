const express = require('express');
const crypto = require('crypto');
const {
  getFirebaseAuth,
  getFirebaseDatabase,
} = require('../services/firebase_admin');
const {
  normalizeYemenPhoneKey,
  passwordMatches,
} = require('../services/auth_utils');

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

function createFirebaseDependencies() {
  const readProfile = async (profileId) => {
    const snapshot = await getFirebaseDatabase()
      .ref(`profiles/${profileId}`).once('value');
    return snapshot.val();
  };
  const readAuthIndex = async (uid) => {
    const snapshot = await getFirebaseDatabase()
      .ref(`auth_index/${uid}`).once('value');
    return snapshot.val() ?? {};
  };

  return {
    readProfile,
    createCustomToken: (uid, claims) =>
      getFirebaseAuth().createCustomToken(uid, claims),
    verifyIdToken: (token) => getFirebaseAuth().verifyIdToken(token),
    resolveProfile: async (uid, claims) => {
      const authIndex = await readAuthIndex(uid);
      let profileId = String(claims.profile_id ?? '').trim();
      let profile = profileId ? await readProfile(profileId) : null;
      if (profile) return { profileId, profile, authIndex };

      profileId = String(authIndex.profile_id ?? '').trim() ||
        normalizeYemenPhoneKey(authIndex.phone) || uid;
      profile = await readProfile(profileId);
      return { profileId, profile, authIndex };
    },
    syncAuthIndex: (uid, profileId, profile) =>
      getFirebaseDatabase().ref(`auth_index/${uid}`).update({
        phone: profile.phone ?? null,
        email: profile.email ?? null,
        profile_id: profileId,
        role: String(profile.role ?? 'customer').trim().toLowerCase(),
      }),
    updateCustomClaims: async (uid, claims) => {
      const auth = getFirebaseAuth();
      const user = await auth.getUser(uid);
      return auth.setCustomUserClaims(uid, {
        ...user.customClaims,
        ...claims,
      });
    },
    updateProfilePassword: (profileId, passwordHash) =>
      getFirebaseDatabase().ref(`profiles/${profileId}`)
        .update({ password_hash: passwordHash }),
    updateAuthPassword: (uid, password) =>
      getFirebaseAuth().updateUser(uid, { password }),
  };
}

function createAuthRouter(dependencies = createFirebaseDependencies()) {
  const router = express.Router();
  const {
    readProfile,
    createCustomToken,
    verifyIdToken,
    resolveProfile,
    syncAuthIndex,
    updateCustomClaims,
    updateProfilePassword,
    updateAuthPassword,
  } = dependencies;

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

      const phoneKey = normalizeYemenPhoneKey(phone);
      const forSignup = req.body?.for_signup === true;
      const forPasswordReset = req.body?.for_password_reset === true;
      if (forSignup || forPasswordReset) {
        const profile = await readProfile(phoneKey);
        if (forSignup && profile) {
          return res.status(409).json({
            success: false,
            error_code: 'account_exists',
            error: 'رقم الهاتف مسجل مسبقاً. سجّل الدخول إلى حسابك.',
          });
        }
        if (forPasswordReset && !profile) {
          return res.status(404).json({
            success: false,
            error_code: 'account_not_found',
            error: 'لا يوجد حساب مرتبط بهذا الرقم',
          });
        }
      }

      await sendWhatsAppOtp(phone);
      return res.json({
        success: true,
        message: 'تم إرسال رمز التحقق عبر واتساب.',
        phone,
      });
    } catch (error) {
      const isWawpError = error instanceof WawpError;
      const code = isWawpError
        ? error.code
        : error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED'
          ? error.code
          : 'AUTH_LOOKUP_FAILED';
      console.error(
        'WhatsApp OTP delivery failed:',
        code,
        error.message,
      );

      const status = isWawpError
        ? error.statusCode
        : error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED' ? 503 : 500;
      return res.status(status).json({
        success: false,
        error_code: code,
        error: code === 'FIREBASE_ADMIN_NOT_CONFIGURED'
          ? 'خدمة المصادقة غير مُهيأة على الخادم.'
          : code === 'WAWP_NOT_CONFIGURED'
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
      const phoneKey = normalizeYemenPhoneKey(phone);
      const otp = String(req.body?.otp ?? '').replace(/\D/g, '');

      if (!phone || !phoneKey) {
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
      const profile = await readProfile(phoneKey);
      const uid = String(
        profile?.auth_uid || profile?.authUid || profile?.id || phoneKey,
      ).trim();
      const customToken = await createCustomToken(uid, {
        profile_id: String(profile?.id ?? phoneKey),
        role: String(profile?.role ?? 'customer').trim().toLowerCase(),
        otp_verified: true,
      });
      return res.json({
        success: true,
        message: 'تم التحقق من رقم الهاتف بنجاح',
        phone,
        custom_token: customToken,
        user: { phone },
      });

    } catch (error) {
      const isWawpError = error instanceof WawpError;
      const code = isWawpError
        ? error.code
        : error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED'
          ? error.code
          : 'OTP_SESSION_FAILED';
      console.error('WhatsApp OTP verification failed:', code, error.message);
      const status = isWawpError
        ? error.statusCode
        : error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED' ? 503 : 500;
      return res.status(status).json({
          success: false,
          error_code: code,
          error: code === 'FIREBASE_ADMIN_NOT_CONFIGURED'
            ? 'خدمة المصادقة غير مُهيأة على الخادم.'
            : code === 'OTP_SESSION_FAILED'
              ? 'تعذر تهيئة جلسة الحساب بعد التحقق.'
              : code === 'WAWP_NOT_CONFIGURED'
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

  router.post('/sync-session', async (req, res) => {
    const authorization = req.headers.authorization ?? '';
    const match = /^Bearer\s+(.+)$/i.exec(authorization);
    if (!match) {
      return res.status(401).json({ error_code: 'authentication_required' });
    }

    try {
      const user = await verifyIdToken(match[1]);
      const { profileId, profile } = await resolveProfile(user.uid, user);
      if (!profile || !profileId) {
        return res.status(404).json({ error_code: 'account_not_found' });
      }

      const linkedUid = String(profile.auth_uid || profile.authUid || '').trim();
      const isLinked = linkedUid === user.uid ||
        user.uid === profileId ||
        String(user.profile_id ?? '') === profileId;
      if (!isLinked) {
        return res.status(403).json({ error_code: 'forbidden' });
      }

      const role = String(profile.role ?? 'customer').trim().toLowerCase();
      await syncAuthIndex(user.uid, profileId, profile);
      await updateCustomClaims(user.uid, {
        profile_id: profileId,
        role,
      });
      return res.json({ success: true, profile_id: profileId, role });
    } catch (error) {
      console.error('Firebase session sync failed:', error.code ?? 'unknown');
      const status = error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED' ? 503 : 500;
      return res.status(status).json({
        error_code: status === 503
          ? 'auth_not_configured'
          : 'session_sync_failed',
      });
    }
  });

  router.post('/password/change', async (req, res) => {
    const authorization = req.headers.authorization ?? '';
    const match = /^Bearer\s+(.+)$/i.exec(authorization);
    if (!match) {
      return res.status(401).json({ error_code: 'authentication_required' });
    }

    const newPassword = String(req.body?.new_password ?? '').trim();
    const currentPassword = String(req.body?.current_password ?? '');
    if (newPassword.length < 6) {
      return res.status(400).json({ error_code: 'invalid_new_password' });
    }

    try {
      const user = await verifyIdToken(match[1]);
      const { profileId, profile } = await resolveProfile(user.uid, user);
      if (!profile || !profileId) {
        return res.status(404).json({ error_code: 'account_not_found' });
      }

      const linkedUid = String(profile.auth_uid || profile.authUid || '').trim();
      if (linkedUid && linkedUid !== user.uid && user.uid !== profileId) {
        return res.status(403).json({ error_code: 'forbidden' });
      }

      if (user.otp_verified !== true &&
          !passwordMatches(
            profile.password_hash ?? profile.passwordHash,
            currentPassword,
          )) {
        return res.status(401).json({ error_code: 'invalid_credentials' });
      }

      const previousHash = profile.password_hash ?? profile.passwordHash;
      const passwordHash = crypto.createHash('sha256')
        .update(newPassword)
        .digest('hex');
      await updateProfilePassword(profileId, passwordHash);
      try {
        await updateAuthPassword(user.uid, newPassword);
      } catch (error) {
        if (typeof previousHash === 'string') {
          await updateProfilePassword(profileId, previousHash);
        }
        throw error;
      }

      return res.json({ success: true });
    } catch (error) {
      console.error(
        'Password change failed:',
        error.code ?? 'unknown',
      );
      const status = error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED' ? 503 : 500;
      return res.status(status).json({
        error_code: status === 503
          ? 'auth_not_configured'
          : 'password_change_failed',
      });
    }
  });

  return router;
}

const router = createAuthRouter();
router.createAuthRouter = createAuthRouter;
module.exports = router;
