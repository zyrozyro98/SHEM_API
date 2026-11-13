const express = require('express');
const {
  getFirebaseAuth,
  getFirebaseDatabase,
} = require('../services/firebase_admin');
const { normalizePhone, passwordMatches } = require('../services/auth_utils');

const terminalCustomerStatuses = new Set(['delivered', 'cancelled']);
const terminalMerchantStatuses = new Set([
  'delivered',
  'cancelled',
  'rejected',
]);

function normalizeRole(profile) {
  return String(profile?.role ?? 'customer').trim().toLowerCase();
}

function toObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value
    : {};
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

function createFirebaseDependencies() {
  return {
    read: async (path) => {
      const snapshot = await getFirebaseDatabase().ref(path).once('value');
      return snapshot.val() ?? {};
    },
    update: (updates) => getFirebaseDatabase().ref().update(updates),
    deleteAuthUser: (uid) => getFirebaseAuth().deleteUser(uid),
  };
}

function createAccountsRouter(dependencies = createFirebaseDependencies()) {
  const router = express.Router();
  const { read, update, deleteAuthUser } = dependencies;
  const failedReauthentication = new Map();

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
          !['customer', 'merchant'].includes(requesterRole))) {
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