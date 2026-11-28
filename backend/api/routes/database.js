const crypto = require('crypto');
const express = require('express');
const {
  getFirebaseAuth,
  getFirebaseDatabase,
} = require('../services/firebase_admin');
const { getVisiblePromotions } = require('./promotions');

const publicReadRoots = new Set([
  'products',
  'product_categories',
  'merchant_categories',
  'promotions',
]);
const publicReadPaths = new Set([
  'settings/pricing',
  'settings/currency',
  'settings/currencies',
  'settings/payment',
  'settings/payment_wallets',
  'payment_wallets',
  'wallets',
]);
const publicProfileFields = [
  'id',
  'full_name',
  'role',
  'shop_category',
  'shop_name',
  'shop_region',
  'merchant_display_delivery_fee',
  'shop_location',
  'shop_contact_phones',
  'shop_wallets',
  'shop_banner',
  'profile_image',
  'is_verified',
];
const publicProductFields = [
  'id',
  'name',
  'alternative_names',
  'alternativeNames',
  'brand',
  'brand_name',
  'submitted_at',
  'submittedAt',
  'price',
  'merchant_claimed_original_price',
  'category',
  'main_category_id',
  'main_category',
  'main_category_sort_order',
  'subcategory_id',
  'subcategory',
  'description',
  'colors',
  'color_image_urls',
  'sizes',
  'has_sizes',
  'image_url',
  'image_urls',
  'video_url',
  'available',
  'merchant_id',
  'merchant_name',
  'currency_code',
  'currency_symbol',
  'currency_name',
  'vat_rate',
  'vat_exempt',
  'commission_mode_override',
  'commission_value_override',
  'effective_commission_mode',
  'effective_commission_value',
  'discount_mode',
  'discount_value',
];
const customerProfileFields = new Set([
  'full_name',
  'city',
  'address',
  'delivery_addresses',
  'selected_delivery_address_id',
  'current_location',
  'profile_image',
]);
const merchantProfileFields = new Set([
  ...customerProfileFields,
  'shop_category',
  'shop_name',
  'shop_region',
  'merchant_display_delivery_fee',
  'shop_location',
  'shop_contact_phones',
  'shop_wallets',
  'shop_banner',
]);
const customerOrderFields = new Set([
  'status',
  'updated_at',
  'cancelled_at',
  'cancellation_reason',
]);
const merchantOrderFields = new Set([
  'status',
  'updated_at',
  'merchant_note',
]);
const driverOrderFields = new Set([
  'status',
  'updated_at',
  'driver_note',
]);
const merchantProductFields = new Set([
  'name',
  'alternative_names',
  'brand',
  'price',
  'merchant_retail_price',
  'merchant_claimed_original_price',
  'category',
  'main_category_id',
  'main_category',
  'main_category_sort_order',
  'subcategory_id',
  'subcategory',
  'description',
  'colors',
  'color_image_urls',
  'sizes',
  'has_sizes',
  'image_url',
  'image_urls',
  'video_url',
  'available',
  'stock',
  'currency_code',
  'currency_symbol',
  'currency_name',
  'updated_at',
]);
const merchantProductCreateFields = new Set([
  ...merchantProductFields,
  'id',
  'merchant_id',
  'alternative_names',
  'categories',
  'colorImageUrls',
  'imageUrl',
  'imageUrls',
  'images',
  'cover_image_url',
  'coverImageUrl',
  'cover_images',
  'videoUrl',
  'has_sizes',
  'requested_available',
  'approval_status',
  'submitted_at',
  'discount_mode',
  'discount_value',
  'price_change_status',
  'requested_price',
  'price_change_previous_price',
  'price_change_requested_at',
  'price_change_review_reason',
  'price_change_reviewed_at',
  'commission_mode_override',
  'commission_value_override',
  'review_reason',
  'reviewed_at',
]);
const orderSecretFields = new Set([
  'pickup_otp',
  'pickupOtp',
  'pickup_otp_hash',
  'pickupOtpHash',
  'pickup_otp_salt',
  'pickupOtpSalt',
  'pickup_otp_expires_at',
  'pickupOtpExpiresAt',
  'pickup_otp_attempts',
  'pickupOtpAttempts',
  'pickup_otp_locked',
  'pickupOtpLocked',
  'customer_delivery_otp',
  'customerDeliveryOtp',
  'customer_delivery_otp_hash',
  'customerDeliveryOtpHash',
  'customer_delivery_otp_salt',
  'customerDeliveryOtpSalt',
  'customer_delivery_otp_expires_at',
  'customerDeliveryOtpExpiresAt',
  'customer_delivery_otp_attempts',
  'customerDeliveryOtpAttempts',
  'customer_delivery_otp_locked',
  'customerDeliveryOtpLocked',
  'delivery_otp',
  'deliveryOtp',
  'delivery_otp_hash',
  'deliveryOtpHash',
  'delivery_otp_salt',
  'deliveryOtpSalt',
  'delivery_otp_expires_at',
  'deliveryOtpExpiresAt',
  'delivery_otp_attempts',
  'deliveryOtpAttempts',
  'delivery_otp_locked',
  'deliveryOtpLocked',
]);

function normalizePath(value) {
  if (typeof value !== 'string') return null;
  const path = value.trim().replace(/^\/+|\/+$/g, '');
  if (!path || path.length > 512) return null;
  const segments = path.split('/');
  if (
    segments.length > 8 ||
    segments.some((segment) =>
      !segment ||
      segment.length > 128 ||
      /[.#$\[\]\u0000-\u001f\u007f]/.test(segment)
    )
  ) {
    return null;
  }
  return path;
}

function parseFirebaseQueryValue(value) {
  if (typeof value !== 'string') throw new TypeError('Invalid database query');
  try {
    return JSON.parse(value);
  } catch {
    throw new TypeError('Invalid database query');
  }
}

function applyFirebaseQuery(ref, queryParameters) {
  const keys = Object.keys(queryParameters).filter((key) => key !== 'path');
  if (keys.length === 0) return ref;
  const supported = new Set([
    'orderBy',
    'equalTo',
    'startAt',
    'endAt',
    'limitToFirst',
    'limitToLast',
  ]);
  if (keys.some((key) => !supported.has(key)) ||
      !queryParameters.orderBy) {
    throw new TypeError('Invalid database query');
  }

  const orderBy = parseFirebaseQueryValue(queryParameters.orderBy);
  let query = orderBy === '$key'
    ? ref.orderByKey()
    : orderBy === '$value'
      ? ref.orderByValue()
      : typeof orderBy === 'string' && orderBy.length > 0
        ? ref.orderByChild(orderBy)
        : null;
  if (!query) throw new TypeError('Invalid database query');

  for (const key of ['equalTo', 'startAt', 'endAt']) {
    if (queryParameters[key] === undefined) continue;
    const value = parseFirebaseQueryValue(queryParameters[key]);
    query = query[key](value);
  }
  for (const key of ['limitToFirst', 'limitToLast']) {
    if (queryParameters[key] === undefined) continue;
    const limit = Number.parseInt(queryParameters[key], 10);
    if (!Number.isInteger(limit) || limit < 1 || limit > 1000) {
      throw new TypeError('Invalid database query');
    }
    query = query[key](limit);
  }
  return query;
}

function isPublicRead(path) {
  const parts = path.split('/');
  const [root] = parts;
  return publicReadRoots.has(root) ||
    publicReadPaths.has(path) ||
    (root === 'product_ratings' && parts.length === 2) ||
    (path.split('/').length === 3 &&
      path.startsWith('settings/payment_wallets/')) ||
    ['wallets', 'payment_wallets'].includes(root);
}

function isPublicProfilePath(path) {
  const parts = path.split('/');
  return parts[0] === 'profiles' && parts.length <= 2;
}

function isAdmin(caller) {
  return caller.role === 'admin';
}

function orderHasMerchant(order, profileId) {
  if (String(order.merchant_id ?? order.merchantId ?? '') === profileId) {
    return true;
  }
  return Array.isArray(order.items) && order.items.some((item) =>
    String(item?.merchant_id ?? item?.merchantId ?? '') === profileId
  );
}

function orderBelongsToCaller(order, caller) {
  if (!order || typeof order !== 'object') return false;
  if (String(order.customer_id ?? order.customerId ?? '') === caller.profileId) {
    return true;
  }
  if (caller.role === 'merchant' && orderHasMerchant(order, caller.profileId)) {
    return true;
  }
  if (caller.role === 'driver' &&
      String(order.driver_id ?? order.driverId ?? '') === caller.profileId) {
    return true;
  }
  return caller.role === 'dispatcher';
}

function publicProfile(profile) {
  if (!profile || typeof profile !== 'object' ||
      String(profile.role ?? '').toLowerCase() !== 'merchant' ||
      profile.is_verified !== true) {
    return null;
  }
  return Object.fromEntries(
    publicProfileFields
      .filter((key) => Object.prototype.hasOwnProperty.call(profile, key))
      .map((key) => [key, profile[key]]),
  );
}

function productIsPublished(product) {
  if (!product || typeof product !== 'object' ||
      product.is_archived === true || product.is_active === false ||
      product.is_approved === false) {
    return false;
  }
  const approvalStatus = String(
    product.approval_status ?? product.approvalStatus ?? '',
  ).trim().toLowerCase();
  return !approvalStatus || approvalStatus === 'approved';
}

function publicProduct(product) {
  if (!product || typeof product !== 'object') return null;
  return Object.fromEntries(
    Object.entries(product).filter(([key]) => publicProductFields.includes(key)),
  );
}

function publicProducts(products, caller, path) {
  const parts = path.split('/');
  if (parts.length > 1) {
    const product = products;
    if (!productIsPublished(product) &&
        !(caller?.role === 'merchant' &&
          String(product?.merchant_id ?? product?.merchantId ?? '') ===
            caller.profileId)) {
      return null;
    }
    return caller?.role === 'admin' ||
        (caller?.role === 'merchant' &&
          String(product?.merchant_id ?? product?.merchantId ?? '') ===
            caller.profileId)
      ? product
      : publicProduct(product);
  }
  if (!products || typeof products !== 'object') return products;
  return Object.fromEntries(
    Object.entries(products)
      .filter(([, product]) =>
        productIsPublished(product) ||
        (caller?.role === 'merchant' &&
          String(product?.merchant_id ?? product?.merchantId ?? '') ===
            caller.profileId)
      )
      .map(([id, product]) => [
        id,
        caller?.role === 'admin' ||
            (caller?.role === 'merchant' &&
              String(product?.merchant_id ?? product?.merchantId ?? '') ===
                caller.profileId)
          ? product
          : publicProduct(product),
      ]),
  );
}

function publicProductRatingSummary(ratings) {
  const values = Object.values(
    ratings && typeof ratings === 'object' && !Array.isArray(ratings)
      ? ratings
      : {},
  )
    .map((entry) => Number(entry?.rating))
    .filter((rating) => Number.isFinite(rating) && rating >= 1 && rating <= 5);
  const count = values.length;
  const average = count === 0
    ? 0
    : values.reduce((total, rating) => total + rating, 0) / count;
  return { average, count };
}

function publicWallet(wallet) {
  if (!wallet || typeof wallet !== 'object') return null;
  const fields = new Set([
    'id',
    'provider',
    'name',
    'display_name',
    'account_number',
    'account_name',
    'phone',
    'logo_url',
    'enabled',
    'is_active',
    'active',
    'sort_order',
    'instructions',
  ]);
  return Object.fromEntries(
    Object.entries(wallet).filter(([key]) => fields.has(key)),
  );
}

function publicWallets(wallets) {
  if (!wallets || typeof wallets !== 'object') return wallets;
  if (Array.isArray(wallets)) return wallets.map(publicWallet);
  return Object.fromEntries(
    Object.entries(wallets)
      .map(([id, wallet]) => [id, publicWallet(wallet)])
      .filter(([, wallet]) => wallet != null),
  );
}

function publicCurrencies(currencies) {
  const fields = new Set([
    'code',
    'title',
    'symbol',
    'is_default',
    'enabled',
    'rate_to_yer',
  ]);
  if (!currencies || typeof currencies !== 'object') return currencies;
  if (Array.isArray(currencies)) {
    return currencies.map((currency) => {
      if (!currency || typeof currency !== 'object') return null;
      return Object.fromEntries(
        Object.entries(currency).filter(([key]) => fields.has(key)),
      );
    });
  }
  return Object.fromEntries(
    Object.entries(currencies).map(([code, currency]) => [
      code,
      currency && typeof currency === 'object'
        ? Object.fromEntries(
            Object.entries(currency).filter(([key]) => fields.has(key)),
          )
        : currency,
    ]),
  );
}

function visiblePromotionMap(data) {
  const visible = getVisiblePromotions(data);
  return Object.fromEntries(visible.map((promotion) => [
    promotion.id,
    promotion,
  ]));
}

function sanitizeOrder(order) {
  if (Array.isArray(order)) return order.map(sanitizeOrder);
  if (!order || typeof order !== 'object') return order;
  return Object.fromEntries(
    Object.entries(order)
      .filter(([key]) => !orderSecretFields.has(key))
      .map(([key, value]) => [key, sanitizeOrder(value)]),
  );
}

function isOwnerPath(path, root, profileId) {
  const parts = path.split('/');
  return parts[0] === root && parts[1] === profileId;
}

function canReadPrivatePath(path, caller, value) {
  if (isAdmin(caller)) return true;
  const parts = path.split('/');
  switch (parts[0]) {
    case 'profiles':
      return parts.length === 2 && parts[1] === caller.profileId;
    case 'customers':
      return isOwnerPath(path, 'customers', caller.profileId);
    case 'orders':
      if (parts.length === 1 && value && typeof value === 'object') {
        return Object.fromEntries(
          Object.entries(value)
            .filter(([, order]) => orderBelongsToCaller(order, caller))
            .map(([id, order]) => [id, sanitizeOrder(order)]),
        );
      }
      return orderBelongsToCaller(value, caller);
    case 'merchant_withdrawals':
      return caller.role === 'merchant' &&
        parts.length === 2 &&
        parts[1] === caller.profileId;
    case 'payment_proofs':
      if (parts.length === 1 && value && typeof value === 'object') {
        return Object.fromEntries(
          Object.entries(value).filter(([, proof]) =>
            caller.role === 'customer' &&
            String(proof?.uploaded_by ?? proof?.uploadedBy ?? '') ===
              caller.profileId
          ),
        );
      }
      return caller.role === 'customer' &&
        String(value?.uploaded_by ?? value?.uploadedBy ?? '') ===
          caller.profileId;
    case 'notifications':
      if (parts.length === 1 && value && typeof value === 'object') {
        return Object.fromEntries(
          Object.entries(value).filter(([, notification]) =>
            String(
              notification?.profile_id ??
              notification?.user_id ??
              notification?.recipient_id ??
              '',
            ) === caller.profileId
          ),
        );
      }
      return String(
        value?.profile_id ?? value?.user_id ?? value?.recipient_id ?? '',
      ) === caller.profileId;
    case 'driver_preferences':
      return caller.role === 'driver' &&
        parts.length >= 2 &&
        parts[1] === caller.profileId;
    default:
      return false;
  }
}

function validProfileWrite(path, caller, current, next) {
  const parts = path.split('/');
  const isOwnerPath = parts.length === 2 && parts[1] === caller.profileId;
  const isPhoneAliasPath = parts.length === 2 &&
    current == null &&
    caller.role === 'customer' &&
    String(next?.auth_uid ?? next?.authUid ?? '') === caller.uid &&
    String(next?.phone ?? '').replace(/\D/g, '') === parts[1];
  if ((!isOwnerPath && !isPhoneAliasPath) ||
      !next || typeof next !== 'object' || Array.isArray(next)) {
    return false;
  }
  const isCreate = current == null;
  const allowedFields = caller.role === 'merchant'
    ? merchantProfileFields
    : customerProfileFields;
  const changed = current ? changedKeys(current, next) : new Set(Object.keys(next));
  if ([...changed].some((key) =>
    !allowedFields.has(key) &&
    !(isCreate && ['id', 'role', 'auth_uid', 'password_hash',
      'auth_provider', 'created_at', 'is_verified', 'phone', 'email']
      .includes(key))
  )) {
    return false;
  }
  if (!isPhoneAliasPath &&
      String(next.id ?? caller.profileId) !== caller.profileId) {
    return false;
  }
  if (isCreate && caller.role !== 'customer') return false;
  if (isCreate && String(next.role ?? 'customer') !== 'customer') return false;
  if (isCreate && next.is_verified === true) return false;
  if (current && String(current.role ?? caller.role) !== caller.role) {
    return false;
  }
  if (current && String(next.role ?? current.role) !== current.role) {
    return false;
  }
  const currentAuthUid = current?.auth_uid ?? current?.authUid;
  const nextAuthUid = next.auth_uid ?? next.authUid ?? currentAuthUid;
  if (current && String(nextAuthUid ?? caller.uid) !==
      String(currentAuthUid ?? caller.uid)) {
    return false;
  }
  if (isCreate && next.auth_uid != null &&
      String(next.auth_uid) !== caller.uid) {
    return false;
  }
  return true;
}

function changedKeys(current, next) {
  const before = current && typeof current === 'object' ? current : {};
  const after = next && typeof next === 'object' ? next : {};
  return new Set(
    [...new Set([...Object.keys(before), ...Object.keys(after)])]
      .filter((key) => JSON.stringify(before[key]) !== JSON.stringify(after[key])),
  );
}

function validOrderWrite(path, caller, current, next) {
  const parts = path.split('/');
  const isNewOrder = current == null;
  const isMainOrder = parts[0] === 'orders' && parts.length === 2;
  const isCustomerIndex = parts[0] === 'customers' &&
    parts[1] === caller.profileId &&
    parts[2] === 'orders' &&
    parts.length === 4;
  if (!isMainOrder && !isCustomerIndex) return false;
  if (!next || typeof next !== 'object' || Array.isArray(next)) return false;
  if (isNewOrder) {
    return false;
  }
  if (!orderBelongsToCaller(current, caller)) return false;
  const allowed = caller.role === 'merchant'
    ? merchantOrderFields
    : caller.role === 'driver'
      ? driverOrderFields
      : customerOrderFields;
  const updates = changedKeys(current, next);
  if ([...updates].some((key) => !allowed.has(key))) return false;
  if (caller.role === 'customer') {
    return next.status === 'cancelled' &&
      ['new', 'pending_payment', 'awaiting_confirmation'].includes(
        String(current.status ?? ''),
      );
  }
  if (caller.role === 'merchant') {
    if (!orderHasMerchant(current, caller.profileId)) return false;
    if (!updates.has('status')) return true;
    const transitions = {
      new: ['confirmed'],
      pending_payment: ['confirmed'],
      awaiting_confirmation: ['confirmed'],
      confirmed: ['preparing'],
      preparing: ['shipped'],
    };
    return (transitions[String(current.status ?? '')] ?? [])
      .includes(String(next.status ?? ''));
  }
  if (
    caller.role !== 'driver' ||
    String(current.driver_id ?? current.driverId ?? '') !== caller.profileId
  ) {
    return false;
  }
  if (!updates.has('status')) return true;
  const driverTransitions = {
    shipped: ['picked_up'],
    picked_up: ['delivered'],
  };
  return (driverTransitions[String(current.status ?? '')] ?? [])
    .includes(String(next.status ?? ''));
}

function normalizedMerchantProductCreate(path, caller, next) {
  const parts = path.split('/');
  if (
    caller.role !== 'merchant' ||
    parts.length !== 2 ||
    !next ||
    typeof next !== 'object' ||
    Array.isArray(next) ||
    String(next.id ?? '') !== parts[1] ||
    String(next.merchant_id ?? '') !== caller.profileId ||
    [...Object.keys(next)].some((key) => !merchantProductCreateFields.has(key)) ||
    typeof next.name !== 'string' ||
    !next.name.trim() ||
    next.name.length > 200 ||
    typeof next.category !== 'string' ||
    !next.category.trim() ||
    next.category.length > 200 ||
    typeof next.price !== 'number' ||
    !Number.isFinite(next.price) ||
    next.price < 0 ||
    !Number.isInteger(next.stock) ||
    next.stock < 0 ||
    typeof next.requested_available !== 'boolean' ||
    typeof next.currency_code !== 'string' ||
    !/^[A-Z]{3}$/.test(next.currency_code) ||
    !Array.isArray(next.image_urls) ||
    next.image_urls.length === 0 ||
    next.image_urls.length > 20 ||
    next.image_urls.some((url) =>
      typeof url !== 'string' ||
      url.length > 2048 ||
      !url.startsWith('https://')
    )
  ) {
    return null;
  }

  return {
    ...next,
    id: parts[1],
    merchant_id: caller.profileId,
    available: false,
    approval_status: 'pending',
    review_reason: '',
    reviewed_at: null,
    submitted_at: new Date().toISOString(),
    commission_mode_override: null,
    commission_value_override: null,
    price_change_status: null,
    requested_price: null,
    price_change_previous_price: null,
    price_change_requested_at: null,
    price_change_review_reason: '',
    price_change_reviewed_at: null,
  };
}

function canWrite(path, caller, current, next) {
  const parts = path.split('/');
  if (
    parts[0] === 'merchant_withdrawals' ||
    parts[0] === 'merchant_withdrawal_requests' ||
    parts[0] === 'payment_proofs' ||
    parts[0] === 'refund_requests' ||
    (parts[0] === 'customers' && parts[2] === 'refund_requests')
  ) {
    return false;
  }
  if (isAdmin(caller)) return true;
  switch (parts[0]) {
    case 'profiles':
      return validProfileWrite(path, caller, current, next);
    case 'orders':
      return validOrderWrite(path, caller, current, next);
    case 'customers':
      if (parts[1] !== caller.profileId) return false;
      if (parts[2] === 'orders') {
        return validOrderWrite(path, caller, current, next);
      }
      return parts[2] === 'wishlist';
    case 'products':
      if (caller.role !== 'merchant' ||
          String((next ?? current)?.merchant_id ??
            (next ?? current)?.merchantId ?? '') !== caller.profileId) {
        return false;
      }
      if (!current) {
        return normalizedMerchantProductCreate(path, caller, next) != null;
      }
      if (!next) return false;
      const updates = changedKeys(current, next);
      if (updates.has('stock') &&
          (!Number.isInteger(next.stock) || next.stock < 0)) {
        return false;
      }
      return [...updates].every((key) => merchantProductFields.has(key));
    case 'payment_proofs':
      return false;
    case 'notifications':
      return String(
        (next ?? current)?.profile_id ??
        (next ?? current)?.user_id ??
        (next ?? current)?.recipient_id ??
        '',
      ) === caller.profileId &&
        (!current ||
          [...changedKeys(current, next)].every((key) =>
            (key === 'read' || key === 'is_read') &&
            typeof next?.[key] === 'boolean'
          ));
    case 'driver_preferences':
      return caller.role === 'driver' && parts[1] === caller.profileId;
    case 'merchant_withdrawal_requests':
      return false;
    default:
      return false;
  }
}

function isStoredReceiptUrl(value) {
  const privateMatch = /^gs:\/\/([^/]+)\/(.+)$/.exec(value);
  if (privateMatch) {
    const bucket =
      String(process.env.FIREBASE_STORAGE_BUCKET ||
        `${process.env.GCLOUD_PROJECT || 'she-m-8d0f5'}.firebasestorage.app`).trim();
    return privateMatch[1] === bucket &&
      /^private\/receipts\/[^/]+\/[^/]+$/.test(privateMatch[2]);
  }

  const repository = String(process.env.GITHUB_REPOSITORY ?? '').trim();
  const repositoryParts = repository.split('/');
  if (repositoryParts.length !== 2 || repositoryParts.some((part) => !part)) {
    return false;
  }

  try {
    const url = new URL(value);
    if (
      url.protocol !== 'https:' ||
      url.hostname !== 'raw.githubusercontent.com' ||
      url.username ||
      url.password ||
      url.search ||
      url.hash
    ) {
      return false;
    }

    const segments = url.pathname.split('/').filter(Boolean)
      .map((segment) => decodeURIComponent(segment));
    const receiptDirectory = String(
      process.env.GITHUB_RECEIPTS_DIRECTORY ?? 'assets/receipts',
    ).trim().replace(/^\/+|\/+$/g, '').split('/');
    return segments[0] === repositoryParts[0] &&
      segments[1] === repositoryParts[1] &&
      segments[2] &&
      receiptDirectory.every((segment, index) =>
        segments[index + 3] === segment) &&
      segments.length > receiptDirectory.length + 3 &&
      /\.(jpe?g|png|webp|avif)$/i.test(segments[segments.length - 1]);
  } catch {
    return false;
  }
}

function applyPatch(current, updates) {
  if (!updates || typeof updates !== 'object' || Array.isArray(updates)) {
    throw new TypeError('Database update must be an object');
  }
  const result = current && typeof current === 'object' && !Array.isArray(current)
    ? JSON.parse(JSON.stringify(current))
    : {};
  for (const [rawPath, value] of Object.entries(updates)) {
    const segments = rawPath.split('/');
    if (
      segments.some((segment) =>
        !segment ||
        segment.length > 128 ||
        /[.#$\[\]\u0000-\u001f\u007f]/.test(segment)
      )
    ) {
      throw new TypeError('Invalid database update path');
    }
    let target = result;
    for (const segment of segments.slice(0, -1)) {
      if (
        target[segment] == null ||
        typeof target[segment] !== 'object' ||
        Array.isArray(target[segment])
      ) {
        target[segment] = {};
      }
      target = target[segment];
    }
    const finalSegment = segments[segments.length - 1];
    if (value == null) {
      delete target[finalSegment];
    } else {
      target[finalSegment] = value;
    }
  }
  return result;
}

class CheckoutError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

function finiteNumber(value) {
  if (typeof value === 'string' && value.trim() === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function merchantSaleInYER(
  order,
  merchantId,
  productOwners,
  merchantProductIds,
  currencyRates,
) {
  const rawItems = order.items ?? order.order_items;
  if (!Array.isArray(rawItems)) return null;

  const amount = (value) => {
    if (value == null || typeof value === 'string' && !value.trim()) return null;
    return finiteNumber(value);
  };
  const firstItem = rawItems.find((item) =>
    item && typeof item === 'object' && !Array.isArray(item)
  );
  const firstItemCurrency = String(
    firstItem?.currency_code ?? firstItem?.currencyCode ?? '',
  ).trim();
  const explicitOrderCurrency = String(
    order.currency_code ?? order.currencyCode ?? '',
  ).trim();
  const orderCurrency = (
    explicitOrderCurrency ||
    firstItemCurrency ||
    'YER'
  ).toUpperCase();
  const rateFor = (item, currencyCode) => {
    if (currencyCode === 'YER') return 1;
    const snapshotRate = amount(item.rate_to_yer ?? item.rateToYER);
    const rate = snapshotRate ?? currencyRates[currencyCode];
    return rate != null && rate > 0 ? rate : null;
  };
  const belongsToMerchant = (item) => {
    const productId = String(item.product_id ?? item.productId ?? '').trim();
    const productOwner = productOwners[productId]?.trim();
    if (productOwner) return productOwner === merchantId;
    const itemMerchantId = String(
      item.merchant_id ?? item.merchantId ?? '',
    ).trim();
    if (itemMerchantId) return itemMerchantId === merchantId;
    return productId !== '' && merchantProductIds.has(productId);
  };

  let commissionInYER = amount(order.commission) ?? 0;
  const commissionIncluded = order.commission_included_in_subtotal === true;
  if (commissionIncluded && commissionInYER !== 0 &&
      orderCurrency !== 'YER') {
    let commissionRate;
    for (const rawItem of rawItems) {
      if (!rawItem || typeof rawItem !== 'object' ||
          Array.isArray(rawItem)) {
        continue;
      }
      const itemCurrency = String(
        rawItem.currency_code ?? rawItem.currencyCode ?? '',
      ).trim().toUpperCase();
      if (itemCurrency === orderCurrency) {
        commissionRate = rawItem.rate_to_yer ?? rawItem.rateToYER;
        break;
      }
    }
    const rate = amount(commissionRate) ?? currencyRates[orderCurrency];
    if (rate == null || rate <= 0) return null;
    commissionInYER *= rate;
  }

  const lines = [];
  let orderBasisYER = 0;
  for (const rawItem of rawItems) {
    if (!rawItem || typeof rawItem !== 'object' ||
        Array.isArray(rawItem) || rawItem.status === 'rejected') {
      continue;
    }
    const item = rawItem;
    const quantity = amount(item.quantity ?? item.qty) ?? 1;
    const currencyCode = String(
      item.currency_code ?? item.currencyCode ?? orderCurrency,
    ).trim().toUpperCase();
    const rate = rateFor(item, currencyCode);
    const storedGrossYER = amount(item.total_yer ?? item.totalYER);
    const storedTotal = amount(
      item.total ?? item.line_total ?? item.lineTotal,
    );
    const unitPrice = amount(
      item.unit_price ?? item.unitPrice ?? item.price,
    );
    const rawGross = storedTotal ?? (
      unitPrice == null ? null : unitPrice * quantity
    );
    const grossYER = storedGrossYER ?? (
      rawGross == null || rate == null ? null : rawGross * rate
    );
    const storedBaseUnitYER = amount(
      item.base_unit_price_yer ?? item.baseUnitPriceYER,
    );
    const rawBaseUnit = amount(
      item.base_unit_price ?? item.baseUnitPrice,
    );
    const baseYER = storedBaseUnitYER != null
      ? storedBaseUnitYER * quantity
      : rawBaseUnit == null || rate == null
        ? null
        : rawBaseUnit * quantity * rate;
    const storedVatYER = amount(item.vat_amount_yer ?? item.vatAmountYER);
    const rawVat = amount(item.vat_amount ?? item.vatAmount);
    const vatYER = storedVatYER ?? (
      rawVat == null || rate == null ? 0 : rawVat * rate
    );
    if (grossYER == null && baseYER == null) {
      if (belongsToMerchant(item) ||
          (commissionIncluded && commissionInYER !== 0)) {
        return null;
      }
      continue;
    }
    const basisYER = baseYER ?? Math.max(0, (grossYER ?? 0) - vatYER);
    orderBasisYER += basisYER;
    lines.push({
      belongsToMerchant: belongsToMerchant(item),
      grossYER,
      baseYER,
      vatYER,
      basisYER,
    });
  }

  let merchantTotalYER = 0;
  let hasMerchantItem = false;
  for (const line of lines) {
    if (!line.belongsToMerchant) continue;
    hasMerchantItem = true;
    if (line.baseYER != null) {
      merchantTotalYER += line.baseYER;
      continue;
    }
    let lineTotalYER = Math.max(0, line.grossYER - line.vatYER);
    if (commissionIncluded && commissionInYER > 0 && orderBasisYER > 0) {
      lineTotalYER = Math.max(
        0,
        lineTotalYER - commissionInYER * line.basisYER / orderBasisYER,
      );
    }
    merchantTotalYER += lineTotalYER;
  }
  return hasMerchantItem ? merchantTotalYER : null;
}

function merchantWithdrawableBalance({
  orders,
  products,
  currencies,
  withdrawals,
  merchantId,
  now = Date.now(),
}) {
  const productOwners = {};
  const merchantProductIds = new Set();
  for (const [productKey, product] of Object.entries(products ?? {})) {
    if (!product || typeof product !== 'object' || Array.isArray(product)) {
      continue;
    }
    const productId = String(product.id ?? productKey).trim();
    const ownerId = String(
      product.merchant_id ?? product.merchantId ?? '',
    ).trim();
    if (!productId || !ownerId) continue;
    productOwners[productId] = ownerId;
    productOwners[productKey.trim()] = ownerId;
    if (ownerId === merchantId) {
      merchantProductIds.add(productId);
      merchantProductIds.add(productKey.trim());
    }
  }
  const currencyRates = { YER: 1 };
  for (const [codeKey, currency] of Object.entries(currencies ?? {})) {
    if (!currency || typeof currency !== 'object' || Array.isArray(currency)) {
      continue;
    }
    const code = String(currency.code ?? codeKey).trim().toUpperCase();
    const rate = finiteNumber(currency.rate_to_yer ?? currency.rateToYER);
    if (code && rate != null) currencyRates[code] = rate;
  }

  let availableBalance = 0;
  const saleStatuses = new Set([
    'new',
    'confirmed',
    'accepted',
    'preparing',
    'shipped',
    'picked_up',
    'delivered',
  ]);
  const parseDate = (value) => {
    if (typeof value === 'number') return value;
    const parsed = Date.parse(value ?? '');
    return Number.isFinite(parsed) ? parsed : null;
  };
  for (const order of Object.values(orders ?? {})) {
    if (!order || typeof order !== 'object' ||
        !saleStatuses.has(String(order.status ?? '').trim().toLowerCase())) {
      continue;
    }
    const amount = merchantSaleInYER(
      order,
      merchantId,
      productOwners,
      merchantProductIds,
      currencyRates,
    );
    if (amount == null) continue;
    const status = String(order.status ?? '').trim().toLowerCase();
    const deliveredAt = parseDate(order.delivered_at ?? order.deliveredAt) ??
      parseDate(order.created_at ?? order.createdAt);
    if (
      status === 'delivered' &&
      deliveredAt != null &&
      now >= deliveredAt + 3 * 24 * 60 * 60 * 1000
    ) {
      availableBalance += amount;
    }
  }

  let pendingWithdrawals = 0;
  for (const request of Object.values(withdrawals ?? {})) {
    if (!request || typeof request !== 'object' ||
        !['pending', 'approved', 'paid'].includes(
          String(request.status ?? ''),
        )) {
      continue;
    }
    const amount = finiteNumber(request.amount);
    if (amount != null && amount > 0) pendingWithdrawals += amount;
  }
  return {
    availableBalance: Math.max(0, availableBalance - pendingWithdrawals),
    availableSalesBalance: availableBalance,
  };
}

function parseCoordinates(value) {
  const match = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/
    .exec(String(value ?? ''));
  if (!match) return null;
  const latitude = Number(match[1]);
  const longitude = Number(match[2]);
  if (
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    return null;
  }
  return { latitude, longitude };
}

function distanceBetweenKm(first, second) {
  const radians = (degrees) => degrees * Math.PI / 180;
  const latitudeDelta = radians(second.latitude - first.latitude);
  const longitudeDelta = radians(second.longitude - first.longitude);
  const value = Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(radians(first.latitude)) *
    Math.cos(radians(second.latitude)) *
    Math.sin(longitudeDelta / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}

function numberMap(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value)
      .map(([key, amount]) => [key.trim(), finiteNumber(amount)])
      .filter(([key, amount]) => key && amount != null),
  );
}

function stringSet(value) {
  return new Set(
    Array.isArray(value)
      ? value.map((entry) => String(entry).trim()).filter(Boolean)
      : [],
  );
}

function checkoutDeliveryFee({
  subtotal,
  distanceKm,
  config,
  customerRegion,
  merchantRegions,
  productIds,
  merchantIds,
  commission,
}) {
  const deliveryValue = finiteNumber(config.delivery_value) ?? 0;
  const baseFee = finiteNumber(config.delivery_base_fee) ?? 1500;
  const perKm = finiteNumber(config.delivery_per_km) ?? 65;
  const deliveryMode = String(config.delivery_mode ?? 'distance');
  const productExemptions = stringSet(config.delivery_exempt_product_ids);
  const merchantExemptions = stringSet(config.delivery_exempt_merchant_ids);
  const exempt = productIds.some((id) => productExemptions.has(id)) ||
    merchantIds.some((id) => merchantExemptions.has(id));
  const rules = Array.isArray(config.free_delivery_rules)
    ? config.free_delivery_rules
    : [];
  const free = !exempt && rules.some((rule) => {
    if (!rule || typeof rule !== 'object') return false;
    const threshold = finiteNumber(rule.threshold);
    if (threshold == null || threshold < 0) return false;
    switch (rule.type) {
      case 'vat_any':
      case 'commission_any':
        return commission > threshold;
      case 'subtotal_single_merchant':
        return merchantIds.length === 1 && subtotal > threshold;
      case 'vat_multi_merchant':
      case 'commission_multi_merchant':
        return merchantIds.length > 1 && commission > threshold;
      default:
        return false;
    }
  });
  if (free) return 0;

  if (deliveryMode === 'fixed') return deliveryValue;
  if (deliveryMode === 'percent') {
    return subtotal * deliveryValue / 100;
  }
  if (deliveryMode === 'region') {
    return numberMap(config.delivery_by_region)[customerRegion] ??
      deliveryValue;
  }
  if (deliveryMode === 'merchant_region') {
    if (exempt) return baseFee + Math.max(0, distanceKm) * perKm;
    const byRegion = numberMap(config.delivery_by_merchant_region);
    const matchingFees = merchantRegions
      .filter((region) => Object.prototype.hasOwnProperty.call(byRegion, region))
      .map((region) => byRegion[region]);
    return matchingFees.length > 0
      ? Math.max(...matchingFees)
      : baseFee + Math.max(0, distanceKm) * perKm;
  }
  return baseFee + Math.max(0, distanceKm) * perKm;
}

async function buildCheckoutOrder({ db, caller, body }) {
  if (
    caller.role !== 'customer' ||
    !body ||
    typeof body !== 'object' ||
    Array.isArray(body) ||
    (body.customer_id != null &&
      String(body.customer_id) !== caller.profileId) ||
    !Array.isArray(body.items) ||
    body.items.length === 0 ||
    body.items.length > 50
  ) {
    throw new CheckoutError(400, 'invalid_checkout_request');
  }

  const [customerSnapshot, productsSnapshot, profilesSnapshot,
    pricingSnapshot, currenciesSnapshot, walletsSnapshot] = await Promise.all([
    db.ref(`profiles/${caller.profileId}`).once('value'),
    db.ref('products').once('value'),
    db.ref('profiles').once('value'),
    db.ref('settings/pricing').once('value'),
    db.ref('settings/currencies').once('value'),
    db.ref('settings/payment_wallets').once('value'),
  ]);
  const customer = customerSnapshot.val();
  const products = productsSnapshot.val() ?? {};
  const profiles = profilesSnapshot.val() ?? {};
  const config = pricingSnapshot.val() ?? {};
  const currencies = currenciesSnapshot.val() ?? {};
  const paymentWallets = walletsSnapshot.val() ?? {};
  if (!customer || String(customer.role ?? '') !== 'customer') {
    throw new CheckoutError(403, 'customer_profile_required');
  }

  const addresses = Array.isArray(customer.delivery_addresses)
    ? customer.delivery_addresses
    : [];
  const selectedAddress = addresses.find((address) =>
    address &&
    String(address.id ?? '') ===
      String(customer.selected_delivery_address_id ?? '')
  );
  const customerPoint = selectedAddress
    ? parseCoordinates(
        selectedAddress.location_coordinates ?? selectedAddress.locationCoordinates,
      ) ?? parseCoordinates(selectedAddress.address)
    : null;
  if (!selectedAddress || !customerPoint) {
    throw new CheckoutError(422, 'delivery_coordinates_required');
  }

  const currencyByCode = new Map();
  if (currencies && typeof currencies === 'object') {
    for (const [key, value] of Object.entries(currencies)) {
      if (!value || typeof value !== 'object') continue;
      const code = String(value.code ?? key).trim().toUpperCase();
      if (!code) continue;
      currencyByCode.set(code, {
        ...value,
        code,
        rate: code === 'YER' ? 1 : finiteNumber(
          value.rate_to_yer ?? value.rateToYER,
        ),
      });
    }
  }
  currencyByCode.set('YER', { code: 'YER', rate: 1, symbol: 'ر.ي' });

  const pricingItems = [];
  const seenProducts = new Set();
  for (const requested of body.items) {
    if (!requested || typeof requested !== 'object') {
      throw new CheckoutError(400, 'invalid_checkout_item');
    }
    const productId = String(requested.product_id ?? '').trim();
    const quantity = requested.quantity;
    if (
      !productId ||
      normalizePath(`products/${productId}`) !== `products/${productId}` ||
      seenProducts.has(productId) ||
      !Number.isInteger(quantity) ||
      quantity < 1 ||
      quantity > 100
    ) {
      throw new CheckoutError(400, 'invalid_checkout_item');
    }
    seenProducts.add(productId);
    const product = products[productId];
    if (
      !product ||
      !productIsPublished(product) ||
      !(product.available === true || String(product.available) === 'true')
    ) {
      throw new CheckoutError(409, 'product_unavailable');
    }

    const merchantId = String(product.merchant_id ?? product.merchantId ?? '')
      .trim();
    const merchant = profiles[merchantId];
    if (
      !merchantId ||
      !merchant ||
      String(merchant.role ?? '').toLowerCase() !== 'merchant' ||
      merchant.is_archived === true
    ) {
      throw new CheckoutError(409, 'merchant_unavailable');
    }

    const productColors = Array.isArray(product.colors)
      ? product.colors.map((color) => String(color).trim())
      : [];
    const productSizes = Array.isArray(product.sizes)
      ? product.sizes.map((size) => String(size).trim())
      : [];
    const selectedColor = String(requested.selected_color ?? '').trim();
    const selectedSize = String(requested.selected_size ?? '').trim();
    if (
      (selectedColor &&
        productColors.length > 0 &&
        !productColors.includes(selectedColor)) ||
      (selectedSize && !productSizes.includes(selectedSize))
    ) {
      throw new CheckoutError(409, 'product_option_unavailable');
    }

    const price = finiteNumber(product.price);
    if (price == null || price < 0) {
      throw new CheckoutError(503, 'product_pricing_invalid');
    }
    const discountValue = finiteNumber(product.discount_value) ?? 0;
    const discountMode = String(product.discount_mode ?? '');
    const discount = discountMode === 'fixed'
      ? Math.min(Math.max(0, discountValue), price)
      : discountMode === 'percent'
        ? price * Math.min(100, Math.max(0, discountValue)) / 100
        : 0;
    const salePrice = Math.max(0, price - discount);
    const category = String(product.category ?? '');
    const commissionByMerchant = numberMap(config.commission_by_merchant);
    const commissionByCategory = numberMap(config.commission_by_category);
    const hasProductOverride =
      product.commission_mode_override != null &&
      product.commission_value_override != null;
    const commissionMode = hasProductOverride
      ? String(product.commission_mode_override)
      : Object.prototype.hasOwnProperty.call(
          commissionByMerchant,
          merchantId,
        )
        ? String(config.commission_mode ?? 'percent')
        : String(config.commission_mode ?? 'percent');
    const commissionValue = hasProductOverride
      ? finiteNumber(product.commission_value_override)
      : Object.prototype.hasOwnProperty.call(
          commissionByMerchant,
          merchantId,
        )
        ? commissionByMerchant[merchantId]
        : commissionByCategory[category] ??
          finiteNumber(config.commission_value) ??
          10;
    if (
      !['percent', 'fixed'].includes(commissionMode) ||
      commissionValue == null ||
      commissionValue < 0
    ) {
      throw new CheckoutError(503, 'pricing_configuration_invalid');
    }

    const currencyCode = String(product.currency_code ?? 'SAR')
      .trim()
      .toUpperCase();
    const currency = currencyByCode.get(currencyCode);
    if (
      !currency ||
      currency.enabled === false ||
      currency.rate == null ||
      currency.rate <= 0
    ) {
      throw new CheckoutError(409, 'currency_rate_unavailable');
    }
    const commission = commissionMode === 'fixed'
      ? commissionValue
      : salePrice * commissionValue / 100;
    const unitPrice = salePrice + commission;
    const itemTotal = unitPrice * quantity;
    const rate = currency.rate;
    const merchantName = String(
      product.merchant_name ??
      product.merchantName ??
      merchant.shop_name ??
      merchant.full_name ??
      '',
    );
    const imageUrl = String(
      product.image_url ??
      product.imageUrl ??
      product.cover_image_url ??
      product.coverImageUrl ??
      '',
    );
    const currencySymbol = String(
      product.currency_symbol ??
      product.currencySymbol ??
      currency.symbol ??
      '',
    );
    pricingItems.push({
      productId,
      merchantId,
      merchant,
      merchantName,
      currencyCode,
      currencySymbol,
      rate,
      quantity,
      unitPrice,
      itemTotal,
      commissionTotal: commission * quantity,
      baseUnitPriceYER: price * rate,
      totalYER: itemTotal * rate,
      selectedColor: selectedColor || null,
      selectedSize: selectedSize || null,
      item: {
        product_id: productId,
        product_name: String(product.name ?? ''),
        product_category: category,
        product_description: String(product.description ?? ''),
        quantity,
        unit_price: unitPrice,
        total: itemTotal,
        base_unit_price: price,
        vat_amount: 0,
        base_unit_price_yer: price * rate,
        vat_amount_yer: 0,
        total_yer: itemTotal * rate,
        rate_to_yer: rate,
        merchant_claimed_original_price: finiteNumber(
          product.merchant_claimed_original_price,
        ),
        selected_color: selectedColor || null,
        selected_size: selectedSize || null,
        image_url: imageUrl,
        currency_code: currencyCode,
        currency_symbol: currencySymbol,
        merchant_id: merchantId,
        merchant_name: merchantName,
        status: 'available',
      },
    });
  }

  const subtotal = pricingItems.reduce(
    (sum, item) => sum + item.totalYER,
    0,
  );
  const commission = pricingItems.reduce(
    (sum, item) => sum + item.commissionTotal * item.rate,
    0,
  );
  const firstMerchantPoint = parseCoordinates(
    pricingItems[0].merchant.shop_location ??
      pricingItems[0].merchant.shopLocation,
  );
  const fallbackDistance = finiteNumber(config.fallback_distance_km) ?? 12;
  const distanceKm = firstMerchantPoint
    ? distanceBetweenKm(customerPoint, firstMerchantPoint)
    : fallbackDistance;
  const merchantRegions = [...new Set(pricingItems.map((item) =>
    String(
      item.merchant.shop_region ??
      item.merchant.shopRegion ??
      item.merchant.region ??
      item.merchant.city ??
      '',
    ).trim(),
  ).filter(Boolean))];
  const customerRegion = String(
    selectedAddress.city ?? customer.city ?? '',
  ).trim();
  const merchantIds = [...new Set(pricingItems.map((item) => item.merchantId))];
  const productIds = pricingItems.map((item) => item.productId);
  const shippingFee = checkoutDeliveryFee({
    subtotal,
    distanceKm,
    config,
    customerRegion,
    merchantRegions,
    productIds,
    merchantIds,
    commission,
  });

  const paymentMethod = String(body.payment_method ?? '').trim();
  let paymentWalletId = null;
  let paymentWalletName = null;
  let status = 'new';
  if (paymentMethod !== 'cash_on_delivery') {
    const requestedWalletId = String(body.payment_wallet_id ?? '').trim();
    const wallet = paymentWallets[requestedWalletId];
    if (
      !requestedWalletId ||
      !wallet ||
      wallet.enabled === false ||
      !String(wallet.name ?? '').trim() ||
      !String(wallet.account_number ?? '').trim()
    ) {
      throw new CheckoutError(400, 'payment_wallet_unavailable');
    }
    const expectedMethod = requestedWalletId === 'jib'
      ? 'jib_wallet'
      : 'wallet';
    if (paymentMethod !== expectedMethod) {
      throw new CheckoutError(400, 'invalid_payment_method');
    }
    paymentWalletId = requestedWalletId;
    const provider = String(wallet.provider ?? '').trim();
    paymentWalletName = provider === 'jib'
      ? 'محفظة جيب'
      : provider || 'محفظة إلكترونية';
    status = 'pending_payment';
  } else if (body.payment_wallet_id != null &&
      String(body.payment_wallet_id).trim()) {
    throw new CheckoutError(400, 'invalid_payment_method');
  }

  const quotes = {
    subtotal: finiteNumber(body.subtotal),
    shipping_fee: finiteNumber(body.shipping_fee),
    commission: finiteNumber(body.commission),
  };
  if (
    Object.values(quotes).some((amount) => amount == null) ||
    Math.abs(quotes.subtotal - subtotal) > 0.01 ||
    Math.abs(quotes.shipping_fee - shippingFee) > 0.01 ||
    Math.abs(quotes.commission - commission) > 0.01
  ) {
    throw new CheckoutError(409, 'checkout_price_changed');
  }

  const orderNumber = String(crypto.randomInt(100000, 1000000));
  const orderId = `order-${Date.now()}-${orderNumber}`;
  const createdAt = new Date().toISOString();
  const order = {
    id: orderId,
    order_number: orderNumber,
    customer_id: caller.profileId,
    items: pricingItems.map((item) => item.item),
    status,
    payment_method: paymentMethod,
    payment_wallet_id: paymentWalletId,
    payment_wallet_name: paymentWalletName,
    subtotal,
    shipping_fee: shippingFee,
    commission,
    total: subtotal + shippingFee,
    currency_code: 'YER',
    currency_symbol: 'ر.ي',
    created_at: createdAt,
    commission_included_in_subtotal: true,
  };
  const updates = {
    [`orders/${orderId}`]: order,
    [`customers/${caller.profileId}/orders/${orderId}`]: order,
  };
  const safeOrderId = orderId.replace(/[^a-zA-Z0-9_-]/g, '_');
  const recipients = new Map();
  for (const merchantId of merchantIds) {
    recipients.set(merchantId, 'merchant');
  }
  for (const [id, profile] of Object.entries(profiles)) {
    const profileId = String(profile?.id ?? id).trim();
    const role = String(profile?.role ?? '').trim();
    if (profileId && ['admin', 'manager', 'central_dispatcher'].includes(role)) {
      recipients.set(profileId, role);
    }
  }
  for (const [profileId, role] of recipients) {
    const keyPart = profileId.replace(/[^a-zA-Z0-9_-]/g, '_');
    const merchantRecipient = role === 'merchant';
    updates[`notifications/profile-${keyPart}-order-${safeOrderId}-created`] = {
      profile_id: profileId,
      recipient_role: role,
      title: merchantRecipient ? 'طلب جديد لمتجرك' : 'طلب جديد يحتاج للمتابعة',
      body: merchantRecipient
        ? `تم استلام طلب رقم ${orderNumber} يحتوي على منتجات متجرك.`
        : `تم استلام طلب رقم ${orderNumber} ويحتاج إلى المتابعة.`,
      type: 'new_order',
      order_id: orderId,
      status: 'new',
      is_read: false,
      created_at: createdAt,
    };
  }
  if (status === 'new') {
    updates[`notifications/order-${safeOrderId}-new`] = {
      profile_id: caller.profileId,
      recipient_role: 'customer',
      title: 'تم استلام طلبك',
      body: `طلبك رقم ${orderNumber} جديد وبانتظار تأكيد التاجر.`,
      type: 'order_status',
      order_id: orderId,
      status: 'new',
      is_read: false,
      created_at: createdAt,
    };
  }
  return { order, updates };
}

function createDatabaseRouter({
  database = getFirebaseDatabase,
  verifyIdToken = (token) => getFirebaseAuth().verifyIdToken(token),
} = {}) {
  const router = express.Router();

  async function getCaller(req) {
    const authorization = req.headers.authorization ?? '';
    const match = /^Bearer\s+(.+)$/i.exec(authorization);
    if (!match) return null;
    const token = await verifyIdToken(match[1]);
    if (!token?.uid) return null;
    const claimedRole = String(token.role ?? '').trim().toLowerCase();
    if (claimedRole &&
        !['customer', 'merchant', 'driver', 'dispatcher', 'admin']
          .includes(claimedRole)) {
      return null;
    }
    const authIndexSnapshot = await database()
      .ref(`auth_index/${token.uid}`).once('value');
    const authIndex = authIndexSnapshot.val() ?? {};
    const claimedProfileId = String(token.profile_id ?? '').trim();
    const indexedProfileId = String(authIndex.profile_id ?? '').trim();
    if (
      claimedProfileId &&
      indexedProfileId &&
      claimedProfileId !== indexedProfileId
    ) {
      return null;
    }
    let profileId = claimedProfileId || indexedProfileId || token.uid;
    let profile = (await database()
      .ref(`profiles/${profileId}`).once('value')).val();
    if (!profile) {
      const profilesSnapshot = await database()
        .ref('profiles')
        .once('value');
      const profiles = profilesSnapshot.val();
      if (profiles && typeof profiles === 'object') {
        for (const [candidateId, candidate] of Object.entries(profiles)) {
          const linkedUid = String(
            candidate?.auth_uid ?? candidate?.authUid ?? '',
          ).trim();
          if (linkedUid === token.uid) {
            profile = candidate;
            profileId = candidateId;
            break;
          }
        }
      }
    }
    let role = claimedRole;
    if (profile) {
      const currentRole = String(profile.role ?? '').trim().toLowerCase();
      const linkedUid = String(profile.auth_uid ?? profile.authUid ?? '').trim();
      if (
        !currentRole ||
        (claimedRole && currentRole !== claimedRole) ||
        (linkedUid && linkedUid !== token.uid) ||
        (!linkedUid &&
          token.uid !== profileId &&
          token.uid !== profile.id &&
          indexedProfileId !== profileId)
      ) {
        return null;
      }
      role = currentRole;
    } else if (
      (role && role !== 'customer') ||
      token.uid !== profileId
    ) {
      return null;
    }
    role = role || 'customer';
    return { uid: token.uid, role, profileId };
  }

  router.post('/merchant-withdrawals', async (req, res) => {
    let caller;
    try {
      caller = await getCaller(req);
    } catch {
      return res.status(401).json({ error_code: 'invalid_authentication' });
    }
    if (!caller) {
      return res.status(401).json({
        error_code: 'authentication_required',
      });
    }
    if (caller.role !== 'merchant') {
      return res.status(403).json({ error_code: 'merchant_required' });
    }

    const amount = req.body?.amount;
    const accountName = req.body?.account_name;
    const accountNumber = req.body?.account_number;
    if (
      !/^[A-Za-z0-9_-]{1,128}$/.test(caller.profileId) ||
      typeof amount !== 'number' ||
      !Number.isFinite(amount) ||
      amount <= 0 ||
      typeof accountName !== 'string' ||
      !accountName.trim() ||
      accountName.trim().length > 120 ||
      typeof accountNumber !== 'string' ||
      !accountNumber.trim() ||
      accountNumber.trim().length > 120
    ) {
      return res.status(400).json({ error_code: 'invalid_withdrawal_request' });
    }

    try {
      const db = database();
      const [ordersSnapshot, productsSnapshot, currenciesSnapshot,
        withdrawalsSnapshot] = await Promise.all([
        db.ref('orders').once('value'),
        db.ref('products').once('value'),
        db.ref('settings/currencies').once('value'),
        db.ref(`merchant_withdrawals/${caller.profileId}`).once('value'),
      ]);
      const walletBalance = merchantWithdrawableBalance({
        orders: ordersSnapshot.val() ?? {},
        products: productsSnapshot.val() ?? {},
        currencies: currenciesSnapshot.val() ?? {},
        withdrawals: withdrawalsSnapshot.val() ?? {},
        merchantId: caller.profileId,
      });
      if (amount > walletBalance.availableBalance) {
        return res.status(409).json({
          error_code: 'insufficient_withdrawable_balance',
        });
      }

      const requestId =
        `withdrawal-${Date.now()}-${crypto.randomInt(100000, 1000000)}`;
      const createdAt = new Date().toISOString();
      const request = {
        id: requestId,
        merchant_id: caller.profileId,
        amount,
        currency_symbol: 'ر.ي',
        status: 'pending',
        account_name: accountName.trim(),
        account_number: accountNumber.trim(),
        note: null,
        created_at: createdAt,
      };
      const merchantWithdrawalsRef = db.ref(
        `merchant_withdrawals/${caller.profileId}`,
      );
      const reservation = await merchantWithdrawalsRef.transaction(
        (current) => {
          const currentRequests = current ?? {};
          const reserved = Object.values(currentRequests).reduce(
            (total, existing) => {
              if (!existing || typeof existing !== 'object' ||
                  !['pending', 'approved', 'paid'].includes(
                    String(existing.status ?? ''),
                  )) {
                return total;
              }
              const existingAmount = finiteNumber(existing.amount);
              return existingAmount != null && existingAmount > 0
                ? total + existingAmount
                : total;
            },
            0,
          );
          if (reserved + amount > walletBalance.availableSalesBalance) {
            return undefined;
          }
          return {...currentRequests, [requestId]: request};
        },
      );
      if (!reservation.committed) {
        return res.status(409).json({
          error_code: 'insufficient_withdrawable_balance',
        });
      }
      try {
        await db.ref().update({
          [`merchant_withdrawal_requests/${requestId}`]: request,
        });
      } catch (error) {
        await merchantWithdrawalsRef.transaction((current) => {
          if (!current || current[requestId]?.created_at !== createdAt) {
            return undefined;
          }
          const next = {...current};
          delete next[requestId];
          return next;
        });
        throw error;
      }
      return res.status(201).json({
        success: true,
        data: request,
        withdrawable_balance: Math.max(
          0,
          walletBalance.availableBalance - amount,
        ),
      });
    } catch (error) {
      console.error(
        'Firebase merchant withdrawal request failed:',
        error.code ?? error.name ?? 'unknown',
      );
      return res.status(500).json({
        error_code: 'merchant_withdrawal_request_failed',
      });
    }
  });

  router.post(
    '/merchant-withdrawals/:requestId/review',
    async (req, res) => {
      let caller;
      try {
        caller = await getCaller(req);
      } catch {
        return res.status(401).json({ error_code: 'invalid_authentication' });
      }
      if (!caller) {
        return res.status(401).json({
          error_code: 'authentication_required',
        });
      }
      if (!isAdmin(caller)) {
        return res.status(403).json({ error_code: 'admin_required' });
      }

      const requestId = String(req.params.requestId ?? '').trim();
      const rawStatus = req.body?.status;
      const status = typeof rawStatus === 'string' ? rawStatus.trim() : '';
      const rawNote = req.body?.note;
      if (
        !/^[A-Za-z0-9_-]{1,128}$/.test(requestId) ||
        typeof rawStatus !== 'string' ||
        !['approved', 'rejected', 'paid'].includes(status) ||
        rawNote != null &&
          (typeof rawNote !== 'string' || rawNote.trim().length > 500)
      ) {
        return res.status(400).json({ error_code: 'invalid_withdrawal_review' });
      }

      try {
        const db = database();
        const requestSnapshot = await db.ref(
          `merchant_withdrawal_requests/${requestId}`,
        ).once('value');
        const request = requestSnapshot.val();
        if (!request) {
          return res.status(404).json({
            error_code: 'merchant_withdrawal_not_found',
          });
        }
        const merchantId = String(request.merchant_id ?? '').trim();
        if (!/^[A-Za-z0-9_-]{1,128}$/.test(merchantId)) {
          return res.status(409).json({
            error_code: 'merchant_withdrawal_invalid',
          });
        }
        const merchantRequestSnapshot = await db.ref(
          `merchant_withdrawals/${merchantId}/${requestId}`,
        ).once('value');
        const merchantRequest = merchantRequestSnapshot.val();
        if (
          !merchantRequest ||
          String(merchantRequest.merchant_id ?? '') !== merchantId ||
          String(merchantRequest.id ?? '') !== requestId ||
          String(merchantRequest.status ?? '') !==
            String(request.status ?? '') ||
          finiteNumber(merchantRequest.amount) !== finiteNumber(request.amount) ||
          finiteNumber(request.amount) == null ||
          finiteNumber(request.amount) <= 0
        ) {
          return res.status(409).json({
            error_code: 'merchant_withdrawal_mirror_mismatch',
          });
        }
        const allowedTransition =
          request.status === 'pending' &&
            ['approved', 'rejected'].includes(status) ||
          request.status === 'approved' && status === 'paid';
        if (!allowedTransition) {
          return res.status(409).json({
            error_code: 'merchant_withdrawal_status_conflict',
          });
        }

        const reviewedAt = new Date().toISOString();
        const updated = {
          ...request,
          status,
          note: rawNote == null ? null : rawNote.trim(),
          reviewed_by: caller.profileId,
          reviewed_at: reviewedAt,
          updated_at: reviewedAt,
        };
        if (status === 'paid') {
          updated.paid_by = caller.profileId;
          updated.paid_at = reviewedAt;
        }
        await db.ref().update({
          [`merchant_withdrawals/${merchantId}/${requestId}`]: updated,
          [`merchant_withdrawal_requests/${requestId}`]: updated,
        });
        return res.json({ success: true, data: updated });
      } catch (error) {
        console.error(
          'Firebase merchant withdrawal review failed:',
          error.code ?? error.name ?? 'unknown',
        );
        return res.status(500).json({
          error_code: 'merchant_withdrawal_review_failed',
        });
      }
    },
  );

  router.post('/payment-proofs/:proofId/review', async (req, res) => {
    let caller;
    try {
      caller = await getCaller(req);
    } catch {
      return res.status(401).json({ error_code: 'invalid_authentication' });
    }
    if (!caller) {
      return res.status(401).json({
        error_code: 'authentication_required',
      });
    }
    if (!isAdmin(caller)) {
      return res.status(403).json({ error_code: 'admin_required' });
    }

    const proofId = String(req.params.proofId ?? '').trim();
    const rawStatus = req.body?.status;
    const rawReviewNote = req.body?.review_note ?? '';
    const status = typeof rawStatus === 'string' ? rawStatus.trim() : '';
    const reviewNote =
      typeof rawReviewNote === 'string' ? rawReviewNote.trim() : '';
    if (
      !/^[A-Za-z0-9_-]{1,128}$/.test(proofId) ||
      typeof rawStatus !== 'string' ||
      typeof rawReviewNote !== 'string' ||
      !['approved', 'rejected'].includes(status) ||
      reviewNote.length > 2000
    ) {
      return res.status(400).json({ error_code: 'invalid_payment_review' });
    }

    try {
      const db = database();
      const proofSnapshot = await db.ref(
        `payment_proofs/${proofId}`,
      ).once('value');
      const proof = proofSnapshot.val();
      if (!proof) {
        return res.status(404).json({ error_code: 'payment_proof_not_found' });
      }
      if (String(proof.status ?? '') !== 'pending') {
        return res.status(409).json({ error_code: 'payment_proof_already_reviewed' });
      }

      const orderId = String(proof.order_id ?? proof.orderId ?? '').trim();
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(orderId)) {
        return res.status(409).json({ error_code: 'payment_proof_order_invalid' });
      }
      const orderSnapshot = await db.ref(`orders/${orderId}`).once('value');
      const order = orderSnapshot.val();
      const customerId = String(order?.customer_id ?? order?.customerId ?? '');
      if (
        !order ||
        customerId !==
          String(proof.uploaded_by ?? proof.uploadedBy ?? '') ||
        String(order.payment_proof_id ?? order.paymentProofId ?? '') !== proofId ||
        String(order.status ?? '') !== 'awaiting_confirmation'
      ) {
        return res.status(409).json({ error_code: 'payment_proof_order_mismatch' });
      }

      const reviewedAt = new Date().toISOString();
      const updatedProof = {
        ...proof,
        id: proofId,
        status,
        review_note: reviewNote,
        reviewed_by: caller.profileId,
        reviewed_at: reviewedAt,
      };
      const updatedOrder = {
        ...order,
        status: status === 'approved' ? 'new' : 'cancelled',
        updated_at: reviewedAt,
      };
      const cancellationReason = 'تم رفض إثبات الدفع من المسؤول';
      if (status === 'rejected') {
        updatedOrder.cancelled_by = 'admin';
        updatedOrder.cancellation_reason = cancellationReason;
        updatedOrder.cancelled_at = reviewedAt;
      }
      const safeOrderId = orderId.replace(/[^A-Za-z0-9_-]/g, '_');
      const notificationStatus = updatedOrder.status;
      const orderNumber = String(
        order.order_number ?? order.orderNumber ?? orderId,
      );
      const updates = {
        [`payment_proofs/${proofId}`]: updatedProof,
        [`orders/${orderId}`]: updatedOrder,
        [`customers/${customerId}/orders/${orderId}`]:
          sanitizeOrder(updatedOrder),
        [`notifications/order-${safeOrderId}-${notificationStatus}`]: {
          profile_id: customerId,
          recipient_role: 'customer',
          title: status === 'approved' ? 'تم استلام طلبك' : 'تم إلغاء طلبك',
          body: status === 'approved'
            ? `طلبك رقم ${orderNumber} جديد وبانتظار تأكيد التاجر.`
            : `تم إلغاء الطلب رقم ${orderNumber}. السبب: ${cancellationReason}`,
          type: 'order_status',
          order_id: orderId,
          status: notificationStatus,
          is_read: false,
          created_at: reviewedAt,
        },
      };
      await db.ref().update(updates);
      return res.json({
        success: true,
        data: updatedProof,
        order: sanitizeOrder(updatedOrder),
      });
    } catch (error) {
      console.error(
        'Firebase payment proof review failed:',
        error.code ?? error.name ?? 'unknown',
      );
      return res.status(500).json({ error_code: 'payment_review_failed' });
    }
  });

  router.post('/refund-requests/:requestId/review', async (req, res) => {
    let caller;
    try {
      caller = await getCaller(req);
    } catch {
      return res.status(401).json({ error_code: 'invalid_authentication' });
    }
    if (!caller) {
      return res.status(401).json({
        error_code: 'authentication_required',
      });
    }
    if (!isAdmin(caller)) {
      return res.status(403).json({ error_code: 'admin_required' });
    }

    const requestId = String(req.params.requestId ?? '').trim();
    const status = String(req.body?.status ?? '').trim();
    const adminNote = String(req.body?.admin_note ?? '').trim();
    const requestedAmount = req.body?.approved_amount;
    if (
      !/^[A-Za-z0-9_-]{1,128}$/.test(requestId) ||
      !['under_review', 'approved', 'rejected'].includes(status) ||
      adminNote.length > 2000 ||
      (status === 'approved' &&
        (finiteNumber(requestedAmount) == null ||
          finiteNumber(requestedAmount) <= 0))
    ) {
      return res.status(400).json({ error_code: 'invalid_refund_review' });
    }

    try {
      const db = database();
      const requestSnapshot = await db.ref(
        `refund_requests/${requestId}`,
      ).once('value');
      const current = requestSnapshot.val();
      if (!current) {
        return res.status(404).json({ error_code: 'refund_request_not_found' });
      }
      if (!['pending', 'under_review'].includes(String(current.status ?? ''))) {
        return res.status(409).json({ error_code: 'refund_request_already_reviewed' });
      }
      const customerId = String(current.customer_id ?? '').trim();
      const customerClaim = finiteNumber(current.customer_claimed_amount);
      const approvedAmount = status === 'approved'
        ? finiteNumber(requestedAmount)
        : status === 'rejected'
          ? 0
          : null;
      if (
        !customerId ||
        customerClaim == null ||
        customerClaim < 0 ||
        status === 'approved' &&
          (approvedAmount == null || approvedAmount > customerClaim)
      ) {
        return res.status(400).json({ error_code: 'invalid_refund_amount' });
      }

      const reviewedAt = new Date().toISOString();
      const updated = {
        ...current,
        status,
        approved_amount: approvedAmount,
        admin_note: adminNote,
        reviewed_by: caller.profileId,
        reviewed_at: reviewedAt,
        updated_at: reviewedAt,
      };
      await db.ref().update({
        [`refund_requests/${requestId}`]: updated,
        [`customers/${customerId}/refund_requests/${requestId}`]: updated,
      });
      return res.json({ success: true, data: updated });
    } catch (error) {
      console.error(
        'Firebase refund request review failed:',
        error.code ?? error.name ?? 'unknown',
      );
      return res.status(500).json({ error_code: 'refund_review_failed' });
    }
  });

  router.post('/refund-requests', async (req, res) => {
    let caller;
    try {
      caller = await getCaller(req);
    } catch {
      return res.status(401).json({ error_code: 'invalid_authentication' });
    }
    if (!caller) {
      return res.status(401).json({
        error_code: 'authentication_required',
      });
    }
    if (caller.role !== 'customer') {
      return res.status(403).json({ error_code: 'customer_required' });
    }

    const orderId = String(req.body?.order_id ?? '').trim();
    const itemIndex = req.body?.item_index;
    const reason = String(req.body?.reason ?? '').trim();
    const customerMessage = String(req.body?.customer_message ?? '').trim();
    if (
      !/^[A-Za-z0-9_-]{1,128}$/.test(orderId) ||
      !Number.isInteger(itemIndex) ||
      itemIndex < 0 ||
      !reason ||
      reason.length > 200 ||
      customerMessage.length > 2000
    ) {
      return res.status(400).json({ error_code: 'invalid_refund_request' });
    }

    try {
      const db = database();
      const orderSnapshot = await db.ref(`orders/${orderId}`).once('value');
      const order = orderSnapshot.val();
      if (!order) {
        return res.status(404).json({ error_code: 'order_not_found' });
      }
      if (
        String(order.customer_id ?? order.customerId ?? '') !== caller.profileId
      ) {
        return res.status(403).json({ error_code: 'order_not_owned' });
      }

      const items = order.items;
      if (!Array.isArray(items) || itemIndex >= items.length ||
          !items[itemIndex] || typeof items[itemIndex] !== 'object') {
        return res.status(400).json({ error_code: 'invalid_refund_item' });
      }
      const orderItem = items[itemIndex];
      const productId = String(
        orderItem.product_id ?? orderItem.productId ?? '',
      ).trim();
      const merchantId = String(
        orderItem.merchant_id ?? orderItem.merchantId ?? '',
      ).trim();
      const [customerProfileSnapshot, productRecordSnapshot,
        merchantProfileSnapshot, refundRequestsSnapshot] = await Promise.all([
        db.ref(`profiles/${caller.profileId}`).once('value'),
        productId ? db.ref(`products/${productId}`).once('value') : null,
        merchantId ? db.ref(`profiles/${merchantId}`).once('value') : null,
        db.ref('refund_requests').once('value'),
      ]);
      const customer = customerProfileSnapshot.val() ?? {};
      const product = productRecordSnapshot?.val() ?? {};
      const merchant = merchantProfileSnapshot?.val() ?? {};
      const refundRequests = refundRequestsSnapshot.val() ?? {};
      const duplicate = Object.values(refundRequests).some((entry) =>
        entry &&
        String(entry.customer_id ?? '') === caller.profileId &&
        String(entry.order_id ?? '') === orderId &&
        finiteNumber(entry.item_index) === itemIndex &&
        ['pending', 'under_review', 'approved'].includes(
          String(entry.status ?? ''),
        )
      );
      if (duplicate) {
        return res.status(409).json({
          error_code: 'refund_request_already_exists',
        });
      }

      const unitPrice = finiteNumber(
        orderItem.unit_price ?? orderItem.unitPrice,
      ) ?? 0;
      const quantity = finiteNumber(orderItem.quantity) ?? 0;
      if (!Number.isInteger(quantity) || quantity < 1) {
        return res.status(400).json({ error_code: 'invalid_refund_item' });
      }
      const itemTotal = finiteNumber(orderItem.total) ?? 0;
      const amountDue = itemTotal > 0 ? itemTotal : unitPrice * quantity;
      const rawMerchantClaim = orderItem.merchant_claimed_original_price ??
        product.merchant_claimed_original_price;
      const merchantClaimedOriginalPrice = rawMerchantClaim == null
        ? null
        : finiteNumber(rawMerchantClaim);
      if (amountDue < 0 || !Number.isFinite(amountDue)) {
        return res.status(400).json({ error_code: 'invalid_refund_amount' });
      }

      const createdAt = new Date().toISOString();
      const requestId = `refund-${Date.now()}-${crypto.randomInt(100000, 1000000)}`;
      const safeProduct = publicProduct(product) ?? {};
      const safeMerchant = publicProfile(merchant) ?? {};
      const productSnapshot = {
        ...safeProduct,
        id: String(product.id ?? productId),
        name: String(
          orderItem.product_name ??
          orderItem.productName ??
          product.name ??
          '',
        ),
        category: String(
          orderItem.product_category ??
          product.category ??
          '',
        ),
        description: String(
          orderItem.product_description ??
          product.description ??
          '',
        ),
        image_url: String(orderItem.image_url ?? product.image_url ?? ''),
        merchant_id: merchantId,
      };
      const merchantData = {
        ...safeMerchant,
        id: String(merchant.id ?? merchantId),
        shop_name: String(
          orderItem.merchant_name ??
          merchant.shop_name ??
          '',
        ),
        full_name: String(safeMerchant.full_name ?? ''),
        phone: String(safeMerchant.phone ?? ''),
        email: String(safeMerchant.email ?? ''),
      };
      const customerData = {
        id: String(customer.id ?? caller.profileId),
        full_name: String(customer.full_name ?? ''),
        phone: String(customer.phone ?? ''),
        email: String(customer.email ?? ''),
        city: String(customer.city ?? ''),
        address: String(customer.address ?? ''),
      };
      const request = {
        id: requestId,
        status: 'pending',
        created_at: createdAt,
        updated_at: createdAt,
        customer_id: caller.profileId,
        customer_snapshot: customerData,
        order_id: orderId,
        order_status: String(order.status ?? ''),
        order_created_at: String(order.created_at ?? ''),
        order_snapshot: {
          id: orderId,
          status: String(order.status ?? ''),
          created_at: String(order.created_at ?? ''),
          payment_method: String(order.payment_method ?? ''),
          subtotal: order.subtotal,
          shipping_fee: order.shipping_fee,
          commission: order.commission,
          total: order.total,
          delivery_address: String(
            order.delivery_address ?? customerData.address,
          ),
        },
        item_index: itemIndex,
        order_item_snapshot: sanitizeOrder(orderItem),
        product_id: productId,
        product_snapshot: productSnapshot,
        merchant_id: merchantId,
        merchant_snapshot: merchantData,
        reason,
        customer_message: customerMessage,
        currency_code: String(orderItem.currency_code ?? 'SAR'),
        currency_symbol: String(orderItem.currency_symbol ?? 'ر.س'),
        unit_price: unitPrice,
        quantity,
        customer_claimed_amount: amountDue,
        amount_due_to_customer: amountDue,
        merchant_claimed_original_price: merchantClaimedOriginalPrice,
        merchant_claimed_total: merchantClaimedOriginalPrice == null
          ? null
          : merchantClaimedOriginalPrice * quantity,
        approved_amount: null,
        admin_note: '',
        reviewed_by: '',
        reviewed_at: null,
      };
      await db.ref().update({
        [`refund_requests/${requestId}`]: request,
        [`customers/${caller.profileId}/refund_requests/${requestId}`]: request,
      });
      return res.status(201).json({ success: true, data: request });
    } catch (error) {
      console.error(
        'Firebase refund request creation failed:',
        error.code ?? error.name ?? 'unknown',
      );
      return res.status(500).json({ error_code: 'refund_request_failed' });
    }
  });

  router.post('/orders/:orderId/payment-proof', async (req, res) => {
    let caller;
    try {
      caller = await getCaller(req);
    } catch {
      return res.status(401).json({ error_code: 'invalid_authentication' });
    }
    if (!caller) {
      return res.status(401).json({
        error_code: 'authentication_required',
      });
    }
    if (caller.role !== 'customer') {
      return res.status(403).json({ error_code: 'customer_required' });
    }

    const orderId = String(req.params.orderId ?? '').trim();
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(orderId)) {
      return res.status(400).json({ error_code: 'invalid_order_id' });
    }

    const imageUrl = String(req.body?.image_url ?? '').trim();
    if (!isStoredReceiptUrl(imageUrl)) {
      return res.status(400).json({ error_code: 'invalid_receipt_image' });
    }
    const privateReceiptMatch =
      /^gs:\/\/[^/]+\/private\/receipts\/([^/]+)\//.exec(imageUrl);
    if (privateReceiptMatch && privateReceiptMatch[1] !== caller.uid) {
      return res.status(403).json({ error_code: 'receipt_not_owned' });
    }
    const note = String(req.body?.note ?? '').trim();
    if (note.length > 500) {
      return res.status(400).json({ error_code: 'invalid_receipt_note' });
    }

    try {
      const db = database();
      const orderSnapshot = await db.ref(`orders/${orderId}`).once('value');
      const currentOrder = orderSnapshot.val();
      if (!currentOrder) {
        return res.status(404).json({ error_code: 'order_not_found' });
      }
      const customerId = String(
        currentOrder.customer_id ?? currentOrder.customerId ?? '',
      );
      if (customerId !== caller.profileId) {
        return res.status(403).json({ error_code: 'order_not_owned' });
      }
      if (
        currentOrder.status !== 'pending_payment' ||
        !['wallet', 'jib_wallet'].includes(
          String(currentOrder.payment_method ?? currentOrder.paymentMethod ?? ''),
        ) ||
        !String(currentOrder.payment_wallet_id ?? '').trim()
      ) {
        return res.status(409).json({ error_code: 'order_not_awaiting_payment' });
      }

      const createdAt = new Date().toISOString();
      const proofId = `proof-${Date.now()}-${crypto.randomInt(100000, 1000000)}`;
      const safeOrderId = orderId.replace(/[^A-Za-z0-9_-]/g, '_');
      const proof = {
        id: proofId,
        order_id: orderId,
        uploaded_by: caller.profileId,
        image_url: imageUrl,
        note: note || 'تم إرسال إثبات الدفع',
        status: 'pending',
        created_at: createdAt,
      };
      const updatedOrder = {
        ...currentOrder,
        status: 'awaiting_confirmation',
        payment_proof_id: proofId,
        updated_at: createdAt,
      };
      const updates = {
        [`payment_proofs/${proofId}`]: proof,
        [`orders/${orderId}`]: updatedOrder,
        [`customers/${caller.profileId}/orders/${orderId}`]:
          sanitizeOrder(updatedOrder),
        [`notifications/order-${safeOrderId}-awaiting-confirmation`]: {
          profile_id: caller.profileId,
          recipient_role: 'customer',
          title: 'تم استلام إثبات الدفع',
          body: `تم استلام إثبات الدفع للطلب رقم ${
            currentOrder.order_number ?? currentOrder.orderNumber ?? orderId
          } وبانتظار مراجعته.`,
          type: 'order_status',
          order_id: orderId,
          status: 'awaiting_confirmation',
          is_read: false,
          created_at: createdAt,
        },
      };
      await db.ref().update(updates);
      return res.status(201).json({
        success: true,
        data: proof,
        order: sanitizeOrder(updatedOrder),
      });
    } catch (error) {
      console.error(
        'Firebase payment proof submission failed:',
        error.code ?? error.name ?? 'unknown',
      );
      return res.status(500).json({ error_code: 'payment_proof_failed' });
    }
  });

  router.post('/orders/:orderId/payment-method', async (req, res) => {
    let caller;
    try {
      caller = await getCaller(req);
    } catch {
      return res.status(401).json({ error_code: 'invalid_authentication' });
    }
    if (!caller) {
      return res.status(401).json({
        error_code: 'authentication_required',
      });
    }
    if (caller.role !== 'customer') {
      return res.status(403).json({ error_code: 'customer_required' });
    }

    const orderId = String(req.params.orderId ?? '').trim();
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(orderId)) {
      return res.status(400).json({ error_code: 'invalid_order_id' });
    }

    try {
      const db = database();
      const orderSnapshot = await db.ref(`orders/${orderId}`).once('value');
      const currentOrder = orderSnapshot.val();
      if (!currentOrder) {
        return res.status(404).json({ error_code: 'order_not_found' });
      }
      const customerId = String(
        currentOrder.customer_id ?? currentOrder.customerId ?? '',
      );
      if (customerId !== caller.profileId) {
        return res.status(403).json({ error_code: 'order_not_owned' });
      }
      if (
        !['new', 'pending_payment'].includes(
          String(currentOrder.status ?? ''),
        ) ||
        currentOrder.payment_proof_id ||
        currentOrder.paymentProofId
      ) {
        return res.status(409).json({ error_code: 'payment_method_locked' });
      }

      const paymentMethod = String(req.body?.payment_method ?? '').trim();
      let paymentWalletId = null;
      let paymentWalletName = null;
      let status = 'new';
      if (paymentMethod !== 'cash_on_delivery') {
        const requestedWalletId = String(
          req.body?.payment_wallet_id ?? '',
        ).trim();
        const walletsSnapshot = await db.ref('settings/payment_wallets')
          .once('value');
        const wallets = walletsSnapshot.val() ?? {};
        const wallet = wallets[requestedWalletId];
        if (
          !requestedWalletId ||
          !wallet ||
          wallet.enabled === false ||
          !String(wallet.name ?? '').trim() ||
          !String(wallet.account_number ?? '').trim()
        ) {
          return res.status(400).json({
            error_code: 'payment_wallet_unavailable',
          });
        }
        const expectedMethod = requestedWalletId === 'jib'
          ? 'jib_wallet'
          : 'wallet';
        if (paymentMethod !== expectedMethod) {
          return res.status(400).json({
            error_code: 'invalid_payment_method',
          });
        }
        paymentWalletId = requestedWalletId;
        const provider = String(wallet.provider ?? '').trim();
        paymentWalletName = provider === 'jib'
          ? 'محفظة جيب'
          : provider || 'محفظة إلكترونية';
        status = 'pending_payment';
      }

      const updatedAt = new Date().toISOString();
      const updatedOrder = {
        ...currentOrder,
        status,
        payment_method: paymentMethod,
        payment_wallet_id: paymentWalletId,
        payment_wallet_name: paymentWalletName,
        updated_at: updatedAt,
      };
      const safeOrderId = orderId.replace(/[^A-Za-z0-9_-]/g, '_');
      const updates = {
        [`orders/${orderId}`]: updatedOrder,
        [`customers/${caller.profileId}/orders/${orderId}`]:
          sanitizeOrder(updatedOrder),
      };
      if (status === 'new') {
        updates[`notifications/order-${safeOrderId}-new`] = {
          profile_id: caller.profileId,
          recipient_role: 'customer',
          title: 'تم اختيار الدفع عند الاستلام',
          body: `تم تحديث طريقة الدفع للطلب رقم ${
            currentOrder.order_number ?? currentOrder.orderNumber ?? orderId
          }.`,
          type: 'order_status',
          order_id: orderId,
          status: 'new',
          is_read: false,
          created_at: updatedAt,
        };
      }
      await db.ref().update(updates);
      return res.json(sanitizeOrder(updatedOrder));
    } catch (error) {
      console.error(
        'Firebase payment method update failed:',
        error.code ?? error.name ?? 'unknown',
      );
      return res.status(500).json({ error_code: 'payment_method_update_failed' });
    }
  });

  router.post('/orders', async (req, res) => {
    let caller;
    try {
      caller = await getCaller(req);
    } catch {
      return res.status(401).json({ error_code: 'invalid_authentication' });
    }
    if (!caller) {
      return res.status(401).json({
        error_code: 'authentication_required',
      });
    }
    if (caller.role !== 'customer') {
      return res.status(403).json({ error_code: 'customer_required' });
    }

    try {
      const db = database();
      const { order, updates } = await buildCheckoutOrder({
        db,
        caller,
        body: req.body,
      });
      await db.ref().update(updates);
      return res.status(201).json(order);
    } catch (error) {
      if (error instanceof CheckoutError) {
        return res.status(error.status).json({ error_code: error.code });
      }
      console.error(
        'Firebase checkout failed:',
        error.code ?? error.name ?? 'unknown',
      );
      return res.status(500).json({ error_code: 'checkout_failed' });
    }
  });

  router.all('/', async (req, res) => {
    const path = normalizePath(req.query.path);
    if (!path) {
      return res.status(400).json({ error_code: 'invalid_database_path' });
    }
    if (!['GET', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) {
      return res.status(405).json({ error_code: 'method_not_allowed' });
    }

    let caller = null;
    try {
      const needsAuthentication =
        req.method !== 'GET' ||
        (!isPublicRead(path) && !isPublicProfilePath(path));
      if (needsAuthentication) {
        caller = await getCaller(req);
        if (!caller) {
          return res.status(401).json({
            error_code: 'authentication_required',
          });
        }
      } else if (req.headers.authorization) {
        try {
          caller = await getCaller(req);
        } catch {
          caller = null;
        }
      }
    } catch {
      return res.status(401).json({ error_code: 'invalid_authentication' });
    }

    try {
      const ref = database().ref(path);
      if (req.method === 'GET') {
        const query = applyFirebaseQuery(ref, req.query);
        const snapshot = await query.once('value');
        const value = snapshot.val();
        const parts = path.split('/');
        if (req.headers['x-firebase-etag'] === 'true') {
          res.set(
            'ETag',
            `"${crypto.createHash('sha256')
              .update(JSON.stringify(value))
              .digest('hex')}"`,
          );
        }
        if (isPublicRead(path)) {
          if (parts[0] === 'products') {
            return res.json(publicProducts(value, caller, path));
          }
          if (parts[0] === 'product_ratings') {
            return res.json(publicProductRatingSummary(value));
          }
          if (parts[0] === 'wallets' || parts[0] === 'payment_wallets') {
            return res.json(
              parts.length === 1
                ? publicWallets(value)
                : publicWallet(value),
            );
          }
          if (path === 'settings/payment_wallets' ||
              parts.length === 3 &&
                path.startsWith('settings/payment_wallets/')) {
            return res.json(
              parts.length === 2 ? publicWallets(value) : publicWallet(value),
            );
          }
          if (path === 'settings/currencies') {
            return res.json(publicCurrencies(value));
          }
          if (path === 'promotions') {
            return res.json(visiblePromotionMap(value));
          }
          if (path.startsWith('promotions/')) {
            return res.json(
              visiblePromotionMap({ [parts[1]]: value })[parts[1]] ?? null,
            );
          }
          return res.json(value);
        }
        if (isPublicProfilePath(path) && !caller) {
          if (parts.length === 1 && value && typeof value === 'object') {
            return res.json(Object.fromEntries(
              Object.entries(value)
                .map(([id, profile]) => [id, publicProfile(profile)])
                .filter(([, profile]) => profile != null),
            ));
          }
          return res.json(publicProfile(value));
        }
        if (!caller) {
          return res.status(401).json({
            error_code: 'authentication_required',
          });
        }

        if (parts[0] === 'profiles') {
          if (isAdmin(caller)) return res.json(value);
          if (parts.length === 1 && value && typeof value === 'object') {
            return res.json(Object.fromEntries(
              Object.entries(value)
                .map(([id, profile]) => [id, publicProfile(profile)])
                .filter(([, profile]) => profile != null),
            ));
          }
          if (parts.length === 2 && parts[1] !== caller.profileId) {
            return res.json(publicProfile(value));
          }
        }

        const authorized = canReadPrivatePath(path, caller, value);
        if (authorized === false) {
          return res.status(403).json({ error_code: 'forbidden' });
        }
        return res.json(authorized === true ? sanitizeOrder(value) : authorized);
      }

      const currentSnapshot = await ref.once('value');
      const current = currentSnapshot.val();
      const next = req.method === 'DELETE'
        ? null
        : req.method === 'PATCH'
          ? applyPatch(current, req.body)
          : req.body;

      if (
        req.method === 'PUT' &&
        req.headers['if-match'] === 'null_etag' &&
        current != null
      ) {
        return res.status(412).json({ error_code: 'precondition_failed' });
      }
      const ifMatch = req.headers['if-match'];
      if (ifMatch && ifMatch !== 'null_etag' &&
          ifMatch !== `"${crypto.createHash('sha256')
            .update(JSON.stringify(current))
            .digest('hex')}"`) {
        return res.status(412).json({ error_code: 'precondition_failed' });
      }
      if (!canWrite(path, caller, current, next)) {
        return res.status(403).json({ error_code: 'forbidden' });
      }

      const result = await ref.transaction((latest) => {
        const latestValue = latest ?? null;
        if (ifMatch === 'null_etag' && latestValue != null) return;
        if (ifMatch && ifMatch !== 'null_etag' &&
            ifMatch !== `"${crypto.createHash('sha256')
              .update(JSON.stringify(latestValue))
              .digest('hex')}"`) {
          return;
        }
        const transactionNext = req.method === 'DELETE'
          ? null
          : req.method === 'PATCH'
            ? applyPatch(latestValue, req.body)
            : req.body;
        if (
          path.split('/')[0] === 'products' &&
          caller.role === 'merchant' &&
          latestValue == null
        ) {
          return normalizedMerchantProductCreate(
            path,
            caller,
            transactionNext,
          ) ?? undefined;
        }
        if (!canWrite(path, caller, latestValue, transactionNext)) return;
        return transactionNext;
      }, undefined, false);

      if (!result.committed) {
        return res.status(412).json({ error_code: 'precondition_failed' });
      }
      return res.json(result.snapshot.val());
    } catch (error) {
      if (error instanceof TypeError) {
        return res.status(400).json({ error_code: 'invalid_database_request' });
      }
      console.error('Firebase database gateway failed:', error.code ?? 'unknown');
      const status = error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED' ? 503 : 500;
      return res.status(status).json({
        error_code: status === 503
          ? 'database_not_configured'
          : 'database_request_failed',
      });
    }
  });

  return router;
}

const router = createDatabaseRouter();
router.createDatabaseRouter = createDatabaseRouter;
router.normalizePath = normalizePath;
module.exports = router;
