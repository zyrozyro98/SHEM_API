const crypto = require('crypto');
const express = require('express');
const {
  getFirebaseAuth,
  getFirebaseDatabase,
  getFirebaseStorage,
} = require('../services/firebase_admin');
const { normalizePhone, passwordMatches } = require('../services/auth_utils');

const terminalCustomerStatuses = new Set(['delivered', 'cancelled']);
const terminalMerchantStatuses = new Set([
  'delivered',
  'cancelled',
  'rejected',
]);
const terminalDriverStatuses = new Set([
  'delivered',
  'cancelled',
  'rejected',
  'completed',
]);

function normalizeRole(profile) {
  return String(profile?.role ?? 'customer').trim().toLowerCase();
}

function toObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value
    : {};
}

function identitySet(...values) {
  return new Set(values.map((value) => String(value ?? '').trim()).filter(Boolean));
}

function canonicalPhone(value) {
  let digits = normalizePhone(value);
  if (digits.startsWith('967') && digits.length === 12) {
    digits = digits.slice(3);
  } else if (digits.startsWith('0') && digits.length === 10) {
    digits = digits.slice(1);
  }
  return digits;
}

function phonesMatch(first, second) {
  const firstCanonical = canonicalPhone(first);
  const secondCanonical = canonicalPhone(second);
  return firstCanonical !== '' &&
    secondCanonical !== '' &&
    firstCanonical === secondCanonical;
}

function notificationBelongsToIdentity(notification, identityIds, phoneIds) {
  const value = toObject(notification);
  const recipientId = String(
    value.profile_id ?? value.profileId ?? value.user_id ??
      value.userId ?? value.recipient_id ?? value.recipientId ?? '',
  ).trim();
  return identityIds.has(recipientId) ||
    phoneIds.has(normalizePhone(recipientId));
}

function refundBelongsToIdentity(refund, identityIds, phoneIds) {
  const value = toObject(refund);
  const customerId = String(
    value.customer_id ?? value.customerId ?? value.profile_id ?? value.profileId ?? '',
  ).trim();
  return identityIds.has(customerId) ||
    phoneIds.has(normalizePhone(customerId));
}

function productOwners(products) {
  const owners = new Map();
  for (const [key, value] of Object.entries(products)) {
    const product = toObject(value);
    const ownerId = String(
      product.merchant_id ?? product.merchantId ?? product.owner_id ??
      product.ownerId ?? '',
    ).trim();
    if (!ownerId) continue;
    owners.set(key, ownerId);
    const productId = String(product.id ?? '').trim();
    if (productId) owners.set(productId, ownerId);
  }
  return owners;
}

function itemBelongsToMerchant(item, merchantIds, owners) {
  const productId = String(item.product_id ?? item.productId ?? '').trim();
  const itemMerchantId = String(item.merchant_id ?? item.merchantId ?? '').trim();
  return merchantIds.has(itemMerchantId) ||
    (productId !== '' && merchantIds.has(owners.get(productId)));
}

function hasActiveCustomerOrder(orders, customerOrders, customerIds, phoneIds) {
  const allOrders = [
    ...Object.values(toObject(orders)),
    ...Object.values(toObject(customerOrders)),
  ];
  return allOrders.some((value) => {
    const order = toObject(value);
    const orderCustomerId = String(
      order.customer_id ?? order.customerId ?? '',
    ).trim();
    const isCustomerOrder = customerIds.has(orderCustomerId) ||
      phoneIds.has(normalizePhone(orderCustomerId));
    const status = String(order.status ?? 'new').trim().toLowerCase();
    return isCustomerOrder && !terminalCustomerStatuses.has(status);
  });
}

function hasActiveMerchantOrder(orders, merchantIds, owners) {
  return Object.values(toObject(orders)).some((value) => {
    const order = toObject(value);
    const status = String(order.status ?? 'new').trim().toLowerCase();
    if (terminalMerchantStatuses.has(status)) return false;

    const items = Array.isArray(order.items) ? order.items : [];
    if (items.some((value) => {
      const item = toObject(value);
      return String(item.status ?? 'available').trim().toLowerCase() !==
          'rejected' &&
        itemBelongsToMerchant(item, merchantIds, owners);
    })) {
      return true;
    }

    const orderMerchantId = String(
      order.merchant_id ?? order.merchantId ?? '',
    ).trim();
    return items.length === 0 && merchantIds.has(orderMerchantId);
  });
}

function hasActiveDriverOrder(orders, driverIds, driverPhone) {
  return Object.values(toObject(orders)).some((value) => {
    const order = toObject(value);
    const orderDriverId = String(
      order.driver_id ?? order.driverId ?? '',
    ).trim();
    const matchesDriver = driverIds.has(orderDriverId) ||
      (driverPhone !== '' &&
        normalizePhone(order.driver_phone ?? order.driverPhone) === driverPhone);
    if (!matchesDriver) return false;
    const status = String(
      order.driver_status ?? order.status ?? 'new',
    ).trim().toLowerCase();
    return !terminalDriverStatuses.has(status);
  });
}

function createFirebaseDependencies() {
  return {
    read: async (path) => {
      const snapshot = await getFirebaseDatabase().ref(path).once('value');
      return snapshot.val() ?? {};
    },
    update: (updates) => getFirebaseDatabase().ref().update(updates),
    deleteAuthUser: (uid) => getFirebaseAuth().deleteUser(uid),
    deleteAccountMedia: async ({ profileId, profileIdAlias, uid }) => {
      const bucket = getFirebaseStorage().bucket();
      const prefixes = new Set([
        `private/profiles/${uid}/`,
        `private/driver-licenses/${profileId}/${uid}/`,
        `private/driver-licenses/${profileIdAlias}/${uid}/`,
      ]);
      await Promise.all(
        [...prefixes].map((prefix) => bucket.deleteFiles({ prefix })),
      );
    },
    submitDeletionRequest: async (request) => {
      const requestRef = getFirebaseDatabase()
        .ref('account_deletion_requests')
        .push();
      await requestRef.set({ ...request, id: requestRef.key });
      return requestRef.key;
    },
  };
}

function createAccountsRouter(dependencies = createFirebaseDependencies()) {
  const router = express.Router();
  const {
    read,
    update,
    deleteAuthUser,
    deleteAccountMedia = async () => {},
    submitDeletionRequest,
  } = dependencies;
  const failedReauthentication = new Map();
  const deletionRequestAttempts = new Map();

  router.post('/deletion-requests', async (req, res) => {
    const rawPhone = req.body?.phone;
    const phoneDigits = normalizePhone(rawPhone);
    const accountType = String(req.body?.account_type ?? '').trim();
    const reason = typeof req.body?.reason === 'string'
      ? req.body.reason.trim()
      : '';
    const honeypot = req.body?.website;

    if (
      typeof rawPhone !== 'string' ||
      !/^[1-9]\d{7,14}$/.test(phoneDigits) ||
      !['customer', 'merchant', 'driver'].includes(accountType) ||
      reason.length > 1000 ||
      (honeypot != null &&
        (typeof honeypot !== 'string' || honeypot.trim().length > 0))
    ) {
      return res.status(400).json({ error_code: 'invalid_deletion_request' });
    }

    const now = Date.now();
    const windowMs = 60 * 60 * 1000;
    const attemptKey = crypto
      .createHash('sha256')
      .update(`${req.ip}:${phoneDigits}`)
      .digest('hex');
    const previousAttempts = deletionRequestAttempts.get(attemptKey);
    if (previousAttempts && now - previousAttempts.startedAt < windowMs &&
        previousAttempts.count >= 3) {
      return res.status(429).json({ error_code: 'too_many_requests' });
    }
    if (deletionRequestAttempts.size > 5000) {
      for (const [key, attempts] of deletionRequestAttempts) {
        if (now - attempts.startedAt >= windowMs) {
          deletionRequestAttempts.delete(key);
        }
      }
    }
    const attempts = previousAttempts && now - previousAttempts.startedAt < windowMs
      ? previousAttempts
      : { startedAt: now, count: 0 };
    deletionRequestAttempts.set(attemptKey, {
      startedAt: attempts.startedAt,
      count: attempts.count + 1,
    });

    try {
      const createdAt = new Date(now).toISOString();
      const requestId = await submitDeletionRequest({
        phone: `+${phoneDigits}`,
        account_type: accountType,
        reason,
        status: 'pending_verification',
        identity_verified: false,
        source: 'web',
        created_at: createdAt,
        updated_at: createdAt,
      });
      if (!requestId) {
        throw new Error('Deletion request storage returned no request ID');
      }
      return res.status(202).json({
        success: true,
        request_id: requestId,
      });
    } catch (error) {
      console.error(
        'Account deletion request could not be stored:',
        error?.code ?? error?.name ?? 'unknown',
      );
      return res.status(503).json({
        error_code: 'deletion_requests_unavailable',
      });
    }
  });

  router.delete('/:profileId', async (req, res) => {
    const profileId = String(req.params.profileId ?? '').trim();
    const requesterPhone = normalizePhone(req.body?.requester_phone);
    const requesterPassword = String(req.body?.requester_password ?? '');
    if (!profileId || !requesterPhone || !requesterPassword.trim()) {
      return res.status(400).json({ error_code: 'invalid_request' });
    }
    const attemptKey = `${req.ip}:${requesterPhone}`;
    const now = Date.now();
    const previousAttempts = failedReauthentication.get(attemptKey);
    if (previousAttempts && now - previousAttempts.startedAt < 15 * 60 * 1000 &&
        previousAttempts.count >= 5) {
      return res.status(429).json({ error_code: 'too_many_attempts' });
    }

    try {
      const profiles = toObject(await read('profiles'));
      const requesterEntry = Object.entries(profiles).find(([, value]) => {
        return normalizePhone(toObject(value).phone) === requesterPhone;
      });
      if (!requesterEntry || !passwordMatches(
        toObject(requesterEntry[1]).password_hash ??
          toObject(requesterEntry[1]).passwordHash,
        requesterPassword,
      )) {
        const attempts = previousAttempts &&
            now - previousAttempts.startedAt < 15 * 60 * 1000
          ? previousAttempts
          : { startedAt: now, count: 0 };
        failedReauthentication.set(attemptKey, {
          startedAt: attempts.startedAt,
          count: attempts.count + 1,
        });
        return res.status(401).json({ error_code: 'invalid_credentials' });
      }
      failedReauthentication.delete(attemptKey);

      const [targetEntry] = Object.entries(profiles).find(([key, value]) => {
        return key === profileId || String(toObject(value).id ?? '') === profileId;
      }) ?? [];
      if (!targetEntry) {
        return res.status(404).json({ error_code: 'account_not_found' });
      }

      const [targetKey, rawTarget] = Object.entries(profiles).find(([key, value]) => {
        return key === profileId || String(toObject(value).id ?? '') === profileId;
      });
      const target = toObject(rawTarget);
      const requester = toObject(requesterEntry[1]);
      const requesterRole = normalizeRole(requester);
      const targetRole = normalizeRole(target);
      const isAdmin = requesterRole === 'admin';
      const isSelf = requesterEntry[0] === targetKey;

      if (!isAdmin && (!isSelf ||
          !['customer', 'merchant', 'driver'].includes(requesterRole))) {
        return res.status(403).json({ error_code: 'forbidden' });
      }
      if (targetRole === 'admin') {
        return res.status(403).json({ error_code: 'admin_account_protected' });
      }

      const products = targetRole === 'merchant'
        ? toObject(await read('products'))
        : {};
      const orders = await read('orders');
      if (targetRole === 'customer') {
        const targetPhone = normalizePhone(target.phone);
        const identityIds = new Set([
          targetKey,
          String(target.id ?? ''),
          targetPhone,
        ].filter(Boolean));
        const phoneIds = new Set([targetPhone].filter(Boolean));
        const customerOrders = await read(`customers/${targetKey}/orders`);
        if (hasActiveCustomerOrder(
          orders,
          customerOrders,
          identityIds,
          phoneIds,
        )) {
          return res.status(409).json({
            error_code: 'customer_active_orders',
          });
        }
      } else if (targetRole === 'merchant') {
        const merchantIds = new Set([
          targetKey,
          String(target.id ?? ''),
        ].filter(Boolean));
        if (hasActiveMerchantOrder(orders, merchantIds, productOwners(products))) {
          return res.status(409).json({
            error_code: 'merchant_active_orders',
          });
        }
      } else if (targetRole === 'driver') {
        const driverIds = new Set([
          targetKey,
          String(target.id ?? ''),
        ].filter(Boolean));
        if (hasActiveDriverOrder(
          orders,
          driverIds,
          normalizePhone(target.phone),
        )) {
          return res.status(409).json({
            error_code: 'driver_active_orders',
          });
        }
      }

      const authIndex = toObject(await read('auth_index'));
      const targetPhone = normalizePhone(target.phone);
      const authIndexEntry = Object.entries(authIndex).find(([, value]) => {
        return normalizePhone(toObject(value).phone) === targetPhone;
      });
      const authUid = String(
        target.auth_uid ?? target.authUid ?? authIndexEntry?.[0] ?? '',
      ).trim();
      const customerIds = [...new Set([
        targetKey,
        targetPhone,
        targetPhone.replace(/\D/g, ''),
      ].filter(Boolean))];
      const customerData = targetRole === 'customer'
        ? await Promise.all(customerIds.map(async (id) => [
            id,
            await read(`customers/${id}`),
          ]))
        : [];
      const identityIds = identitySet(
        targetKey,
        String(target.id ?? ''),
        targetPhone,
        targetPhone.replace(/\D/g, ''),
      );
      const phoneIds = identitySet(targetPhone);
      const [
        notifications,
        authSwitchSessions,
        refundRequests,
        productRatings,
        driverPreferences,
        merchantWithdrawals,
        withdrawalRequests,
        deletionRequests,
      ] = await Promise.all([
        read('notifications'),
        read('auth_switch_sessions'),
        read('refund_requests'),
        read('product_ratings'),
        read('driver_preferences'),
        read('merchant_withdrawals'),
        read('merchant_withdrawal_requests'),
        read('account_deletion_requests'),
      ]);

      const updates = {
        [`profiles/${targetKey}`]: null,
      };
      const restoreUpdates = {
        [`profiles/${targetKey}`]: target,
      };
      if (authUid) {
        updates[`auth_index/${authUid}`] = null;
        if (authIndex[authUid] !== undefined) {
          restoreUpdates[`auth_index/${authUid}`] = authIndex[authUid];
        }
      }
      for (const [id] of customerData) {
        updates[`customers/${id}`] = null;
      }
      for (const [id, data] of customerData) {
        if (Object.keys(toObject(data)).length > 0) {
          restoreUpdates[`customers/${id}`] = data;
        }
      }

      for (const [id, value] of Object.entries(toObject(notifications))) {
        if (notificationBelongsToIdentity(value, identityIds, phoneIds)) {
          updates[`notifications/${id}`] = null;
          restoreUpdates[`notifications/${id}`] = value;
        }
      }
      for (const [id, value] of Object.entries(toObject(authSwitchSessions))) {
        const session = toObject(value);
        const sessionUid = String(session.uid ?? '').trim();
        const sessionProfileId = String(session.profile_id ?? session.profileId ?? '').trim();
        if (identityIds.has(sessionUid) ||
            identityIds.has(sessionProfileId) ||
            (authUid && sessionUid === authUid)) {
          updates[`auth_switch_sessions/${id}`] = null;
          restoreUpdates[`auth_switch_sessions/${id}`] = value;
        }
      }
      for (const [id, value] of Object.entries(toObject(refundRequests))) {
        if (refundBelongsToIdentity(value, identityIds, phoneIds)) {
          updates[`refund_requests/${id}`] = null;
          restoreUpdates[`refund_requests/${id}`] = value;
        }
      }
      for (const [id, value] of Object.entries(toObject(driverPreferences))) {
        if (identityIds.has(id) ||
            identityIds.has(String(toObject(value).profile_id ?? '').trim())) {
          updates[`driver_preferences/${id}`] = null;
          restoreUpdates[`driver_preferences/${id}`] = value;
        }
      }
      for (const [productId, ratingsValue] of Object.entries(toObject(productRatings))) {
        const ratings = toObject(ratingsValue);
        for (const [ratingId, ratingValue] of Object.entries(ratings)) {
          const rating = toObject(ratingValue);
          const ratingCustomerId = String(
            rating.customer_id ?? rating.customerId ?? ratingId,
          ).trim();
          if (identityIds.has(ratingCustomerId) ||
              phoneIds.has(normalizePhone(ratingCustomerId))) {
            updates[`product_ratings/${productId}/${ratingId}/customer_id`] = null;
            updates[`product_ratings/${productId}/${ratingId}/customerId`] = null;
            updates[`product_ratings/${productId}/${ratingId}/comment`] = null;
            restoreUpdates[`product_ratings/${productId}/${ratingId}`] = ratingValue;
          }
        }
      }
      for (const [id, value] of Object.entries(toObject(deletionRequests))) {
        const request = toObject(value);
        if (phonesMatch(request.phone, targetPhone) &&
            String(request.account_type ?? '').trim().toLowerCase() === targetRole) {
          updates[`account_deletion_requests/${id}/phone`] = null;
          updates[`account_deletion_requests/${id}/reason`] = null;
          updates[`account_deletion_requests/${id}/status`] = 'completed';
          updates[`account_deletion_requests/${id}/personal_data_anonymized_at`] =
            new Date().toISOString();
          restoreUpdates[`account_deletion_requests/${id}`] = value;
        }
      }
      if (targetRole === 'merchant') {
        for (const [id, value] of Object.entries(toObject(merchantWithdrawals))) {
          if (identityIds.has(id)) {
            updates[`merchant_withdrawals/${id}`] = null;
            restoreUpdates[`merchant_withdrawals/${id}`] = value;
          }
        }
        for (const [id, value] of Object.entries(toObject(withdrawalRequests))) {
          const request = toObject(value);
          const merchantId = String(request.merchant_id ?? request.merchantId ?? '').trim();
          if (identityIds.has(merchantId)) {
            updates[`merchant_withdrawal_requests/${id}`] = null;
            restoreUpdates[`merchant_withdrawal_requests/${id}`] = value;
          }
        }
      }

      if (targetRole === 'merchant') {
        const archivedAt = new Date().toISOString();
        for (const [key, value] of Object.entries(products)) {
          const product = toObject(value);
          const ownerId = String(
            product.merchant_id ?? product.merchantId ?? '',
          ).trim();
          if (!new Set([targetKey, String(target.id ?? '')]).has(ownerId)) {
            continue;
          }
          updates[`products/${key}/available`] = false;
          updates[`products/${key}/requested_available`] = false;
          updates[`products/${key}/is_archived`] = true;
          updates[`products/${key}/archived_at`] = archivedAt;
          for (const field of [
            'available',
            'requested_available',
            'is_archived',
            'archived_at',
          ]) {
            restoreUpdates[`products/${key}/${field}`] =
              product[field] === undefined ? null : product[field];
          }
        }
      }

      if (authUid) {
        await deleteAccountMedia({
          profileId: targetKey,
          profileIdAlias: String(target.id ?? targetKey),
          uid: authUid,
        });
      }
      await update(updates);
      if (authUid) {
        try {
          await deleteAuthUser(authUid);
        } catch (error) {
          if (error.code !== 'auth/user-not-found') {
            await update(restoreUpdates);
            throw error;
          }
        }
      }

      return res.json({ success: true });
    } catch (error) {
      const errorCode = error?.code;
      const errorMessage = error instanceof Error
        ? error.message
        : String(error);
      console.error(
        'Account deletion failed:',
        errorCode ?? 'unknown',
        errorMessage,
      );
      const status = errorCode === 'FIREBASE_ADMIN_NOT_CONFIGURED' ? 503 : 500;
      return res.status(status).json({
        error_code: status === 503
          ? 'account_deletion_not_configured'
          : 'account_deletion_failed',
      });
    }
  });

  return router;
}

const router = createAccountsRouter();
router.createAccountsRouter = createAccountsRouter;
module.exports = router;