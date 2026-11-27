const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { createDatabaseRouter } = require('../routes/database');

function clone(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

function createDatabase(initial = {}) {
  const values = clone(initial);
  const getAt = (path) => path
    ? path.split('/').reduce(
        (value, segment) => value?.[segment],
        values,
      )
    : values;
  const setAt = (path, next) => {
    const segments = path.split('/');
    let target = values;
    for (const segment of segments.slice(0, -1)) {
      target[segment] ??= {};
      target = target[segment];
    }
    if (next == null) {
      delete target[segments[segments.length - 1]];
    } else {
      target[segments[segments.length - 1]] = clone(next);
    }
  };
  return {
    values,
    ref(path = '') {
      return {
        once: async () => ({ val: () => clone(getAt(path) ?? null) }),
        update: async (updates) => {
          for (const [updatePath, next] of Object.entries(updates)) {
            setAt(updatePath, next);
          }
        },
        transaction: async (update) => {
          const current = clone(getAt(path) ?? null);
          const next = update(current);
          if (next === undefined) {
            return {
              committed: false,
              snapshot: { val: () => clone(current) },
            };
          }
          setAt(path, next);
          return {
            committed: true,
            snapshot: { val: () => clone(next) },
          };
        },
      };
    },
  };
}

async function startDatabaseApp({ initial = {}, users = {} } = {}) {
  const store = createDatabase(initial);
  const app = express();
  app.use(express.json());
  app.use('/database', createDatabaseRouter({
    database: () => store,
    verifyIdToken: async (token) => {
      if (!users[token]) throw new Error('Invalid token');
      return users[token];
    },
  }));
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  return { server, store };
}

async function request(server, path, {
  method = 'GET',
  token,
  body,
} = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(
    `http://127.0.0.1:${server.address().port}/database?path=${
      encodeURIComponent(path)
    }`,
    {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    },
  );
  return { status: response.status, body: await response.json() };
}

async function createOrderRequest(server, {
  token,
  body,
} = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(
    `http://127.0.0.1:${server.address().port}/database/orders`,
    {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    },
  );
  return { status: response.status, body: await response.json() };
}

async function submitPaymentProofRequest(server, {
  orderId = 'order-1',
  token = 'customer-token',
  body = {
    image_url:
      'https://raw.githubusercontent.com/owner/repository/main/assets/receipts/receipt-1.jpg',
    note: 'تحويل عبر المحفظة',
  },
} = {}) {
  const response = await fetch(
    `http://127.0.0.1:${server.address().port}/database/orders/${
      encodeURIComponent(orderId)
    }/payment-proof`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );
  return { status: response.status, body: await response.json() };
}

async function updatePaymentMethodRequest(server, {
  orderId = 'order-1',
  token = 'customer-token',
  body = { payment_method: 'cash_on_delivery' },
} = {}) {
  const response = await fetch(
    `http://127.0.0.1:${server.address().port}/database/orders/${
      encodeURIComponent(orderId)
    }/payment-method`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );
  return { status: response.status, body: await response.json() };
}

async function createRefundRequest(server, {
  token = 'customer-token',
  body = {
    order_id: 'order-1',
    item_index: 0,
    reason: 'المنتج تالف',
    customer_message: 'وصل المنتج متضررًا',
  },
} = {}) {
  const response = await fetch(
    `http://127.0.0.1:${server.address().port}/database/refund-requests`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );
  return { status: response.status, body: await response.json() };
}

async function reviewRefundRequest(server, {
  requestId = 'refund-1',
  token = 'admin-token',
  body = {
    status: 'approved',
    approved_amount: 80,
    admin_note: 'اعتماد جزئي',
  },
} = {}) {
  const response = await fetch(
    `http://127.0.0.1:${server.address().port}/database/refund-requests/${
      encodeURIComponent(requestId)
    }/review`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );
  return { status: response.status, body: await response.json() };
}

async function reviewPaymentProof(server, {
  proofId = 'proof-1',
  token = 'admin-token',
  body = { status: 'approved', review_note: 'تم التحقق من الإيصال' },
} = {}) {
  const response = await fetch(
    `http://127.0.0.1:${server.address().port}/database/payment-proofs/${
      encodeURIComponent(proofId)
    }/review`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );
  return { status: response.status, body: await response.json() };
}

async function createMerchantWithdrawal(server, {
  token = 'merchant-token',
  body = {
    amount: 100,
    account_name: 'محفظة التاجر',
    account_number: '700123456',
  },
} = {}) {
  const response = await fetch(
    `http://127.0.0.1:${server.address().port}/database/merchant-withdrawals`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );
  return { status: response.status, body: await response.json() };
}

async function reviewMerchantWithdrawal(server, {
  requestId,
  token = 'admin-token',
  body = { status: 'approved' },
} = {}) {
  const response = await fetch(
    `http://127.0.0.1:${server.address().port}/database/merchant-withdrawals/${
      encodeURIComponent(requestId)
    }/review`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );
  return { status: response.status, body: await response.json() };
}

const customer = {
  uid: 'uid-customer',
  profile_id: 'customer-1',
  role: 'customer',
};

function checkoutDatabase({ addressCoordinates = '15,44' } = {}) {
  const address = {
    id: 'address-1',
    city: 'Sanaa',
    address: 'Test address',
  };
  if (addressCoordinates != null) {
    address.location_coordinates = addressCoordinates;
  }
  return {
    profiles: {
      'customer-1': {
        id: 'customer-1',
        role: 'customer',
        auth_uid: 'uid-customer',
        city: 'Sanaa',
        delivery_addresses: [address],
        selected_delivery_address_id: 'address-1',
      },
      'merchant-1': {
        id: 'merchant-1',
        role: 'merchant',
        shop_name: 'Shop',
        shop_region: 'Sanaa',
        shop_location: '15,44',
        is_verified: true,
      },
    },
    products: {
      'product-1': {
        id: 'product-1',
        name: 'Item',
        category: 'Care',
        description: 'Description',
        merchant_id: 'merchant-1',
        merchant_name: 'Shop',
        price: 100,
        currency_code: 'YER',
        currency_symbol: 'ر.ي',
        available: true,
        approval_status: 'approved',
        image_url: 'https://media.example.test/item.jpg',
      },
    },
    settings: {
      pricing: {
        commission_mode: 'percent',
        commission_value: 10,
        delivery_mode: 'fixed',
        delivery_value: 75,
      },
      currencies: {
        YER: {
          code: 'YER',
          enabled: true,
          rate_to_yer: 1,
        },
      },
      payment_wallets: {},
    },
  };
}

function checkoutBody(overrides = {}) {
  return {
    customer_id: 'customer-1',
    items: [{
      product_id: 'product-1',
      quantity: 1,
      unit_price: 0,
      merchant_id: 'attacker-controlled',
    }],
    payment_method: 'cash_on_delivery',
    subtotal: 110,
    shipping_fee: 75,
    commission: 10,
    ...overrides,
  };
}

test('database gateway allows anonymous catalog and public merchant reads only', async () => {
  const { server } = await startDatabaseApp({
    initial: {
      'products': { 'product-1': { id: 'product-1', name: 'Item' } },
      'profiles': {
        'merchant-1': {
          id: 'merchant-1',
          role: 'merchant',
          shop_name: 'Shop',
          is_verified: true,
          phone: '+967771234567',
          password_hash: 'secret',
        },
      },
    },
  });
  try {
    const products = await request(server, 'products');
    const profiles = await request(server, 'profiles');

    assert.equal(products.status, 200);
    assert.deepEqual(products.body, {
      'product-1': { id: 'product-1', name: 'Item' },
    });
    assert.deepEqual(profiles.body, {
      'merchant-1': {
        id: 'merchant-1',
        role: 'merchant',
        shop_name: 'Shop',
        is_verified: true,
      },
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('customer profile reads expose only public merchant fields for other profiles', async () => {
  const { server } = await startDatabaseApp({
    initial: {
      'profiles': {
        'customer-1': {
          id: 'customer-1',
          role: 'customer',
          auth_uid: 'uid-customer',
          phone: 'private',
        },
        'merchant-1': {
          id: 'merchant-1',
          role: 'merchant',
          shop_name: 'Shop',
          is_verified: true,
          phone: 'private',
          password_hash: 'secret',
        },
      },
    },
    users: { 'customer-token': customer },
  });
  try {
    const own = await request(server, 'profiles/customer-1', {
      token: 'customer-token',
    });
    const merchant = await request(server, 'profiles/merchant-1', {
      token: 'customer-token',
    });
    const allProfiles = await request(server, 'profiles', {
      token: 'customer-token',
    });

    assert.equal(own.body.phone, 'private');
    assert.deepEqual(merchant.body, {
      id: 'merchant-1',
      role: 'merchant',
      shop_name: 'Shop',
      is_verified: true,
    });
    assert.equal(
      allProfiles.body['merchant-1'].password_hash,
      undefined,
    );
    assert.equal(allProfiles.body['customer-1'], undefined);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('drivers can read only their own preferences', async () => {
  const { server } = await startDatabaseApp({
    initial: {
      profiles: {
        'driver-1': {
          id: 'driver-1',
          role: 'driver',
          auth_uid: 'uid-driver-1',
        },
      },
      auth_index: {
        'uid-driver-1': { profile_id: 'driver-1', role: 'driver' },
      },
      driver_preferences: {
        'driver-1': { favorites: { 'order-1': true } },
        'driver-2': { favorites: { 'order-2': true } },
      },
    },
    users: {
      'driver-token': {
        uid: 'uid-driver-1',
        profile_id: 'driver-1',
        role: 'driver',
      },
    },
  });
  try {
    const ownPreferences = await request(
      server,
      'driver_preferences/driver-1/favorites',
      { token: 'driver-token' },
    );
    const otherPreferences = await request(
      server,
      'driver_preferences/driver-2/favorites',
      { token: 'driver-token' },
    );
    const allPreferences = await request(
      server,
      'driver_preferences',
      { token: 'driver-token' },
    );

    assert.equal(ownPreferences.status, 200);
    assert.deepEqual(ownPreferences.body, { 'order-1': true });
    assert.equal(otherPreferences.status, 403);
    assert.equal(allPreferences.status, 403);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('public product reads hide unpublished products and private fields', async () => {
  const { server } = await startDatabaseApp({
    initial: {
      'products': {
        'visible': {
          id: 'visible',
          name: 'Public',
          price: 12,
          available: true,
          supplier_cost: 5,
        },
        'pending': {
          id: 'pending',
          name: 'Pending',
          approval_status: 'pending',
          supplier_cost: 1,
        },
      },
    },
  });
  try {
    const result = await request(server, 'products');

    assert.deepEqual(result.body, {
      visible: {
        id: 'visible',
        name: 'Public',
        price: 12,
        available: true,
      },
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('public product rating reads expose only an aggregate summary', async () => {
  const { server } = await startDatabaseApp({
    initial: {
      product_ratings: {
        p1: {
          customer1: {
            rating: 5,
            comment: 'Great',
            customer_id: 'customer1',
          },
          customer2: { rating: '4', customer_id: 'customer2' },
          invalid: { rating: 8, customer_id: 'customer3' },
        },
      },
    },
  });
  try {
    const result = await request(server, 'product_ratings/p1');

    assert.deepEqual(result.body, { average: 4.5, count: 2 });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('customer can update their profile but cannot change protected identity fields', async () => {
  const { server, store } = await startDatabaseApp({
    initial: {
      'profiles': {
        'customer-1': {
          id: 'customer-1',
          role: 'customer',
          auth_uid: 'uid-customer',
          password_hash: 'secret',
          full_name: 'Before',
        },
      },
    },
    users: { 'customer-token': customer },
  });
  try {
    const profileUpdate = await request(server, 'profiles/customer-1', {
      method: 'PATCH',
      token: 'customer-token',
      body: { full_name: 'After' },
    });
    const roleUpdate = await request(server, 'profiles/customer-1', {
      method: 'PATCH',
      token: 'customer-token',
      body: { role: 'admin' },
    });
    const emailUpdate = await request(server, 'profiles/customer-1', {
      method: 'PATCH',
      token: 'customer-token',
      body: { email: 'unverified@example.com' },
    });
    const authIndexUpdate = await request(server, 'auth_index/uid-customer', {
      method: 'PUT',
      token: 'customer-token',
      body: { profile_id: 'customer-1', role: 'admin' },
    });

    assert.equal(profileUpdate.status, 200);
    assert.equal(store.values.profiles['customer-1'].full_name, 'After');
    assert.equal(roleUpdate.status, 403);
    assert.equal(emailUpdate.status, 403);
    assert.equal(authIndexUpdate.status, 403);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('database gateway rejects stale or forged role claims', async () => {
  const { server } = await startDatabaseApp({
    initial: {
      'profiles': {
        'customer-1': {
          id: 'customer-1',
          role: 'customer',
          auth_uid: 'uid-customer',
        },
      },
    },
    users: {
      'forged-admin-token': {
        uid: 'uid-customer',
        profile_id: 'customer-1',
        role: 'admin',
      },
    },
  });
  try {
    const result = await request(server, 'orders', {
      token: 'forged-admin-token',
    });

    assert.equal(result.status, 401);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('Firebase users without custom claims can create their own customer profile', async () => {
  const { server, store } = await startDatabaseApp({
    users: { 'google-token': { uid: 'google-uid' } },
  });
  try {
    const result = await request(server, 'profiles/google-uid', {
      method: 'PUT',
      token: 'google-token',
      body: {
        id: 'google-uid',
        auth_uid: 'google-uid',
        role: 'customer',
        phone: '+967771234567',
        full_name: 'Customer',
        is_verified: false,
      },
    });

    assert.equal(result.status, 200);
    assert.equal(store.values.profiles['google-uid'].auth_uid, 'google-uid');
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('customer order reads are limited to their own orders and omit delivery secrets', async () => {
  const { server } = await startDatabaseApp({
    initial: {
      'profiles': {
        'customer-1': {
          id: 'customer-1',
          role: 'customer',
          auth_uid: 'uid-customer',
        },
      },
      'orders': {
        'order-1': {
          id: 'order-1',
          customer_id: 'customer-1',
          pickup_otp: '123456',
          status: 'new',
        },
        'order-2': { id: 'order-2', customer_id: 'customer-2' },
      },
    },
    users: { 'customer-token': customer },
  });
  try {
    const result = await request(server, 'orders', {
      token: 'customer-token',
    });

    assert.deepEqual(result.body, {
      'order-1': {
        id: 'order-1',
        customer_id: 'customer-1',
        status: 'new',
      },
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('public wallet data omits server-only fields and pending promotions', async () => {
  const { server } = await startDatabaseApp({
    initial: {
      'wallets': {
        'wallet-1': {
          provider: 'Test',
          account_number: '12345',
          access_token: 'private',
        },
      },
      'promotions': {
        visible: {
          title: 'Visible',
          image_url: 'https://example.test/banner.png',
          is_active: true,
          approval_status: 'approved',
        },
        pending: {
          title: 'Pending',
          image_url: 'https://example.test/pending.png',
          is_active: true,
          approval_status: 'pending',
        },
      },
    },
  });
  try {
    const wallets = await request(server, 'wallets');
    const promotions = await request(server, 'promotions');

    assert.deepEqual(wallets.body['wallet-1'], {
      provider: 'Test',
      account_number: '12345',
    });
    assert.deepEqual(Object.keys(promotions.body), ['visible']);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('checkout settings expose only public currency and payment-wallet fields',
  async () => {
    const { server } = await startDatabaseApp({
      initial: {
        settings: {
          currencies: {
            SAR: {
              code: 'SAR',
              title: 'Saudi Riyal',
              symbol: 'ر.س',
              enabled: true,
              rate_to_yer: 140,
              private_note: 'internal',
            },
          },
          payment_wallets: {
            jib: {
              provider: 'jib',
              name: 'Account name',
              account_number: '12345',
              enabled: true,
              access_token: 'secret',
            },
          },
        },
      },
    });
    try {
      const currencies = await request(server, 'settings/currencies');
      const wallets = await request(server, 'settings/payment_wallets');
      const jib = await request(server, 'settings/payment_wallets/jib');
      const privateWalletField = await request(
        server,
        'settings/payment_wallets/jib/access_token',
      );

      assert.equal(currencies.body.SAR.rate_to_yer, 140);
      assert.equal(currencies.body.SAR.private_note, undefined);
      assert.equal(wallets.body.jib.access_token, undefined);
      assert.equal(privateWalletField.status, 401);
      assert.deepEqual(jib.body, {
        provider: 'jib',
        name: 'Account name',
        account_number: '12345',
        enabled: true,
      });
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  },
);

test('customer cannot create an order through generic database writes', async () => {
  const { server, store } = await startDatabaseApp({
    initial: {
      'profiles': {
        'customer-1': {
          id: 'customer-1',
          role: 'customer',
          auth_uid: 'uid-customer',
        },
      },
    },
    users: { 'customer-token': customer },
  });
  try {
    const result = await request(server, 'orders/order-1', {
      method: 'PUT',
      token: 'customer-token',
      body: {
        id: 'order-1',
        customer_id: 'customer-1',
        status: 'new',
        total: 0.01,
      },
    });

    assert.equal(result.status, 403);
    assert.equal(store.values.orders, undefined);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('merchant product creation always starts pending and unavailable', async () => {
  const { server, store } = await startDatabaseApp({
    initial: {
      profiles: {
        'merchant-1': {
          id: 'merchant-1',
          role: 'merchant',
          auth_uid: 'uid-merchant',
        },
      },
    },
    users: {
      'merchant-token': {
        uid: 'uid-merchant',
        profile_id: 'merchant-1',
        role: 'merchant',
      },
    },
  });
  try {
    const result = await request(server, 'products/product-1', {
      method: 'PUT',
      token: 'merchant-token',
      body: {
        id: 'product-1',
        merchant_id: 'merchant-1',
        name: 'Product',
        category: 'Care',
        price: 25,
        stock: 5,
        requested_available: true,
        currency_code: 'SAR',
        image_urls: ['https://media.example.test/product.jpg'],
        available: true,
        approval_status: 'approved',
        commission_mode_override: 'fixed',
        commission_value_override: 99,
      },
    });

    assert.equal(result.status, 200);
    assert.equal(store.values.products['product-1'].approval_status, 'pending');
    assert.equal(store.values.products['product-1'].available, false);
    assert.equal(
      store.values.products['product-1'].requested_available,
      true,
    );
    assert.equal(
      store.values.products['product-1'].commission_value_override,
      null,
    );
    assert.equal(
      store.values.products['product-1'].merchant_id,
      'merchant-1',
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('merchant product creation rejects mismatched ownership and invalid prices', async () => {
  const { server, store } = await startDatabaseApp({
    initial: {
      profiles: {
        'merchant-1': {
          id: 'merchant-1',
          role: 'merchant',
          auth_uid: 'uid-merchant',
        },
      },
    },
    users: {
      'merchant-token': {
        uid: 'uid-merchant',
        profile_id: 'merchant-1',
        role: 'merchant',
      },
    },
  });
  const product = {
    id: 'product-1',
    merchant_id: 'merchant-1',
    name: 'Product',
    category: 'Care',
    price: 25,
    stock: 5,
    requested_available: true,
    currency_code: 'SAR',
    image_urls: ['https://media.example.test/product.jpg'],
  };
  try {
    const mismatchedOwner = await request(server, 'products/product-1', {
      method: 'PUT',
      token: 'merchant-token',
      body: { ...product, merchant_id: 'merchant-2' },
    });
    const invalidPrice = await request(server, 'products/product-2', {
      method: 'PUT',
      token: 'merchant-token',
      body: { ...product, id: 'product-2', price: -1 },
    });

    assert.equal(mismatchedOwner.status, 403);
    assert.equal(invalidPrice.status, 403);
    assert.equal(store.values.products, undefined);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('merchant product updates reject negative stock', async () => {
  const { server, store } = await startDatabaseApp({
    initial: {
      profiles: {
        'merchant-1': {
          id: 'merchant-1',
          role: 'merchant',
          auth_uid: 'uid-merchant',
        },
      },
      products: {
        'product-1': {
          id: 'product-1',
          merchant_id: 'merchant-1',
          stock: 5,
        },
      },
    },
    users: {
      'merchant-token': {
        uid: 'uid-merchant',
        profile_id: 'merchant-1',
        role: 'merchant',
      },
    },
  });
  try {
    const result = await request(server, 'products/product-1', {
      method: 'PATCH',
      token: 'merchant-token',
      body: { stock: -1 },
    });

    assert.equal(result.status, 403);
    assert.equal(store.values.products['product-1'].stock, 5);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('checkout creates a server-priced order and customer mirror atomically',
  async () => {
    const { server, store } = await startDatabaseApp({
      initial: checkoutDatabase(),
      users: { 'customer-token': customer },
    });
    try {
      const result = await createOrderRequest(server, {
        token: 'customer-token',
        body: checkoutBody(),
      });

      assert.equal(result.status, 201);
      assert.equal(result.body.customer_id, 'customer-1');
      assert.equal(result.body.status, 'new');
      assert.equal(result.body.subtotal, 110);
      assert.equal(result.body.shipping_fee, 75);
      assert.equal(result.body.commission, 10);
      assert.equal(result.body.total, 185);
      assert.equal(result.body.items[0].unit_price, 110);
      assert.equal(result.body.items[0].merchant_id, 'merchant-1');
      assert.deepEqual(
        store.values.customers['customer-1'].orders[result.body.id],
        result.body,
      );
      assert.equal(store.values.orders[result.body.id].status, 'new');
      assert.equal(
        store.values.notifications[`order-${result.body.id}-new`]
          .profile_id,
        'customer-1',
      );
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  },
);

test('checkout rejects when the selected address has no saved coordinates',
  async () => {
    const { server, store } = await startDatabaseApp({
      initial: checkoutDatabase({ addressCoordinates: null }),
      users: { 'customer-token': customer },
    });
    try {
      const result = await createOrderRequest(server, {
        token: 'customer-token',
        body: checkoutBody(),
      });

      assert.equal(result.status, 422);
      assert.equal(result.body.error_code, 'delivery_coordinates_required');
      assert.equal(store.values.orders, undefined);
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  },
);

test('checkout rejects client price changes and does not create an order',
  async () => {
    const { server, store } = await startDatabaseApp({
      initial: checkoutDatabase(),
      users: { 'customer-token': customer },
    });
    try {
      const result = await createOrderRequest(server, {
        token: 'customer-token',
        body: checkoutBody({ subtotal: 1 }),
      });

      assert.equal(result.status, 409);
      assert.equal(result.body.error_code, 'checkout_price_changed');
      assert.equal(store.values.orders, undefined);
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  },
);

test('checkout validates wallet settings and creates pending-payment orders',
  async () => {
    const initial = checkoutDatabase();
    initial.settings.payment_wallets.bank = {
      provider: 'Test Bank',
      name: 'Account name',
      account_number: '12345',
      enabled: true,
    };
    const { server } = await startDatabaseApp({
      initial,
      users: { 'customer-token': customer },
    });
    try {
      const result = await createOrderRequest(server, {
        token: 'customer-token',
        body: checkoutBody({
          payment_method: 'wallet',
          payment_wallet_id: 'bank',
        }),
      });

      assert.equal(result.status, 201);
      assert.equal(result.body.status, 'pending_payment');
      assert.equal(result.body.payment_wallet_id, 'bank');
      assert.equal(result.body.payment_wallet_name, 'Test Bank');
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  },
);

test('checkout converts fixed discounts and commissions using the saved rate',
  async () => {
    const initial = checkoutDatabase();
    initial.products['product-1'].currency_code = 'SAR';
    initial.products['product-1'].discount_mode = 'fixed';
    initial.products['product-1'].discount_value = 5;
    initial.settings.currencies.SAR = {
      code: 'SAR',
      enabled: true,
      rate_to_yer: 140,
      symbol: 'ر.س',
    };
    const { server } = await startDatabaseApp({
      initial,
      users: { 'customer-token': customer },
    });
    try {
      const result = await createOrderRequest(server, {
        token: 'customer-token',
        body: checkoutBody({
          subtotal: 14630,
          commission: 1330,
        }),
      });

      assert.equal(result.status, 201);
      assert.equal(result.body.items[0].unit_price, 104.5);
      assert.equal(result.body.items[0].total_yer, 14630);
      assert.equal(result.body.commission, 1330);
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  },
);

test('payment proof submission updates the proof and order atomically', async () => {
  const initial = checkoutDatabase();
  initial.orders = {
    'order-1': {
      id: 'order-1',
      order_number: '123456',
      customer_id: 'customer-1',
      status: 'pending_payment',
      payment_method: 'wallet',
      payment_wallet_id: 'wallet-1',
    },
  };
  initial.customers = {
    'customer-1': {
      orders: { 'order-1': initial.orders['order-1'] },
    },
  };
  const originalRepository = process.env.GITHUB_REPOSITORY;
  process.env.GITHUB_REPOSITORY = 'owner/repository';
  const { server, store } = await startDatabaseApp({
    initial,
    users: { 'customer-token': customer },
  });
  try {
    const result = await submitPaymentProofRequest(server);

    assert.equal(result.status, 201);
    assert.equal(result.body.data.uploaded_by, 'customer-1');
    assert.equal(result.body.data.status, 'pending');
    assert.equal(result.body.order.status, 'awaiting_confirmation');
    assert.equal(result.body.order.payment_proof_id, result.body.data.id);
    assert.deepEqual(
      store.values.payment_proofs[result.body.data.id],
      result.body.data,
    );
    assert.equal(
      store.values.customers['customer-1'].orders['order-1'].status,
      'awaiting_confirmation',
    );
    assert.equal(
      store.values.notifications['order-order-1-awaiting-confirmation']
        .profile_id,
      'customer-1',
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
    if (originalRepository === undefined) {
      delete process.env.GITHUB_REPOSITORY;
    } else {
      process.env.GITHUB_REPOSITORY = originalRepository;
    }
  }
});

test('payment proof submission rejects untrusted images and orders', async () => {
  const initial = checkoutDatabase();
  initial.orders = {
    'order-1': {
      id: 'order-1',
      customer_id: 'another-customer',
      status: 'pending_payment',
      payment_method: 'wallet',
      payment_wallet_id: 'wallet-1',
    },
  };
  const originalRepository = process.env.GITHUB_REPOSITORY;
  process.env.GITHUB_REPOSITORY = 'owner/repository';
  const { server, store } = await startDatabaseApp({
    initial,
    users: { 'customer-token': customer },
  });
  try {
    const untrustedImage = await submitPaymentProofRequest(server, {
      body: { image_url: 'https://example.test/receipt.jpg' },
    });
    assert.equal(untrustedImage.status, 400);
    assert.equal(untrustedImage.body.error_code, 'invalid_receipt_image');

    const unownedOrder = await submitPaymentProofRequest(server);
    assert.equal(unownedOrder.status, 403);
    assert.equal(unownedOrder.body.error_code, 'order_not_owned');
    assert.equal(store.values.payment_proofs, undefined);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    if (originalRepository === undefined) {
      delete process.env.GITHUB_REPOSITORY;
    } else {
      process.env.GITHUB_REPOSITORY = originalRepository;
    }
  }
});

test('customer payment method changes update the order and mirror', async () => {
  const initial = checkoutDatabase();
  initial.orders = {
    'order-1': {
      id: 'order-1',
      order_number: '123456',
      customer_id: 'customer-1',
      status: 'pending_payment',
      payment_method: 'wallet',
      payment_wallet_id: 'wallet-1',
      payment_wallet_name: 'محفظة الهاتف',
    },
  };
  initial.customers = {
    'customer-1': {
      orders: { 'order-1': initial.orders['order-1'] },
    },
  };
  const { server, store } = await startDatabaseApp({
    initial,
    users: { 'customer-token': customer },
  });
  try {
    const result = await updatePaymentMethodRequest(server, {
      body: {
        payment_method: 'cash_on_delivery',
        status: 'delivered',
      },
    });

    assert.equal(result.status, 200);
    assert.equal(result.body.status, 'new');
    assert.equal(result.body.payment_method, 'cash_on_delivery');
    assert.equal(result.body.payment_wallet_id, null);
    assert.equal(result.body.payment_wallet_name, null);
    assert.equal(
      store.values.customers['customer-1'].orders['order-1'].status,
      'new',
    );
    assert.equal(store.values.orders['order-1'].status, 'new');
    assert.equal(
      store.values.notifications['order-order-1-new'].profile_id,
      'customer-1',
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('customer payment method changes validate wallet and proof state', async () => {
  const initial = checkoutDatabase();
  initial.settings.payment_wallets.wallet1 = {
    provider: 'Test Wallet',
    name: 'Account name',
    account_number: '12345',
    enabled: true,
  };
  initial.orders = {
    'order-1': {
      id: 'order-1',
      customer_id: 'customer-1',
      status: 'new',
      payment_method: 'cash_on_delivery',
    },
    'order-2': {
      id: 'order-2',
      customer_id: 'customer-1',
      status: 'pending_payment',
      payment_method: 'wallet',
      payment_wallet_id: 'wallet1',
      payment_proof_id: 'proof-1',
    },
  };
  const { server, store } = await startDatabaseApp({
    initial,
    users: { 'customer-token': customer },
  });
  try {
    const selectedWallet = await updatePaymentMethodRequest(server, {
      body: {
        payment_method: 'wallet',
        payment_wallet_id: 'wallet1',
      },
    });
    assert.equal(selectedWallet.status, 200);
    assert.equal(selectedWallet.body.status, 'pending_payment');
    assert.equal(selectedWallet.body.payment_wallet_name, 'Test Wallet');

    const invalidWallet = await updatePaymentMethodRequest(server, {
      body: {
        payment_method: 'wallet',
        payment_wallet_id: 'missing',
      },
    });
    assert.equal(invalidWallet.status, 400);
    assert.equal(invalidWallet.body.error_code, 'payment_wallet_unavailable');

    const lockedOrder = await updatePaymentMethodRequest(server, {
      orderId: 'order-2',
    });
    assert.equal(lockedOrder.status, 409);
    assert.equal(lockedOrder.body.error_code, 'payment_method_locked');
    assert.equal(
      store.values.orders['order-2'].payment_method,
      'wallet',
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('refund requests are server-snapshotted and written to both indexes', async () => {
  const initial = checkoutDatabase();
  initial.profiles['customer-1'] = {
    ...initial.profiles['customer-1'],
    full_name: 'عميل الاختبار',
    phone: '+967700000001',
    address: 'شارع التحرير',
  };
  initial.profiles['merchant-1'] = {
    ...initial.profiles['merchant-1'],
    full_name: 'صاحب المتجر',
    phone: '+967700000002',
    email: 'merchant@example.com',
    is_verified: true,
  };
  initial.products['product-1'].merchant_claimed_original_price = 90;
  initial.orders = {
    'order-1': {
      id: 'order-1',
      customer_id: 'customer-1',
      status: 'delivered',
      created_at: '2026-10-01T10:00:00.000Z',
      payment_method: 'cash_on_delivery',
      subtotal: 300,
      shipping_fee: 20,
      total: 320,
      delivery_address: 'شارع التحرير',
      items: [{
        product_id: 'product-1',
        product_name: 'قميص وقت الشراء',
        product_category: 'ملابس',
        product_description: 'وصف وقت الشراء',
        merchant_id: 'merchant-1',
        merchant_name: 'متجر النخبة',
        unit_price: 150,
        merchant_claimed_original_price: 90,
        quantity: 2,
        total: 300,
        currency_symbol: 'ر.ي',
      }],
    },
  };
  const { server, store } = await startDatabaseApp({
    initial,
    users: { 'customer-token': customer },
  });
  try {
    const result = await createRefundRequest(server);

    assert.equal(result.status, 201);
    assert.equal(result.body.data.customer_id, 'customer-1');
    assert.equal(result.body.data.customer_claimed_amount, 300);
    assert.equal(result.body.data.merchant_claimed_total, 180);
    assert.equal(result.body.data.product_snapshot.name, 'قميص وقت الشراء');
    assert.equal(result.body.data.merchant_snapshot.shop_name, 'متجر النخبة');
    assert.deepEqual(
      store.values.refund_requests[result.body.data.id],
      result.body.data,
    );
    assert.deepEqual(
      store.values.customers['customer-1'].refund_requests[result.body.data.id],
      result.body.data,
    );

    const duplicate = await createRefundRequest(server);
    assert.equal(duplicate.status, 409);

    const forgedWrite = await request(
      server,
      'customers/customer-1/refund_requests/forged',
      {
        method: 'PUT',
        token: 'customer-token',
        body: { customer_id: 'another-customer', status: 'approved' },
      },
    );
    assert.equal(forgedWrite.status, 403);
    assert.equal(
      store.values.customers['customer-1'].refund_requests.forged,
      undefined,
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('refund creation rejects unowned orders and invalid item indexes', async () => {
  const initial = checkoutDatabase();
  initial.orders = {
    'order-1': {
      id: 'order-1',
      customer_id: 'another-customer',
      items: [{ product_id: 'product-1', quantity: 1 }],
    },
    'order-2': {
      id: 'order-2',
      customer_id: 'customer-1',
      items: [{ product_id: 'product-1', quantity: 1 }],
    },
  };
  const { server, store } = await startDatabaseApp({
    initial,
    users: { 'customer-token': customer },
  });
  try {
    const unowned = await createRefundRequest(server, {
      body: {
        order_id: 'order-1',
        item_index: 0,
        reason: 'المنتج تالف',
      },
    });
    assert.equal(unowned.status, 403);

    const invalidIndex = await createRefundRequest(server, {
      body: {
        order_id: 'order-2',
        item_index: 3,
        reason: 'المنتج تالف',
      },
    });
    assert.equal(invalidIndex.status, 400);
    assert.equal(store.values.refund_requests, undefined);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('admin refund review validates amount and updates both indexes', async () => {
  const initial = {
    profiles: {
      'admin-1': {
        id: 'admin-1',
        role: 'admin',
        auth_uid: 'uid-admin',
      },
      'customer-1': {
        id: 'customer-1',
        role: 'customer',
        auth_uid: 'uid-customer',
      },
    },
    refund_requests: {
      'refund-1': {
        id: 'refund-1',
        customer_id: 'customer-1',
        customer_claimed_amount: 100,
        status: 'pending',
      },
    },
    customers: {
      'customer-1': {
        refund_requests: {
          'refund-1': {
            id: 'refund-1',
            customer_id: 'customer-1',
            customer_claimed_amount: 100,
            status: 'pending',
          },
        },
      },
    },
  };
  const { server, store } = await startDatabaseApp({
    initial,
    users: {
      'customer-token': customer,
      'admin-token': {
        uid: 'uid-admin',
        profile_id: 'admin-1',
        role: 'admin',
      },
    },
  });
  try {
    const customerReview = await reviewRefundRequest(server, {
      token: 'customer-token',
    });
    assert.equal(customerReview.status, 403);

    const genericAdminWrite = await request(
      server,
      'refund_requests/refund-1',
      {
        method: 'PUT',
        token: 'admin-token',
        body: { status: 'approved', approved_amount: 1000 },
      },
    );
    assert.equal(genericAdminWrite.status, 403);

    const excessiveAmount = await reviewRefundRequest(server, {
      body: {
        status: 'approved',
        approved_amount: 101,
        admin_note: 'مبلغ زائد',
        reviewed_by: 'forged-admin',
      },
    });
    assert.equal(excessiveAmount.status, 400);
    assert.equal(store.values.refund_requests['refund-1'].status, 'pending');

    const inReview = await reviewRefundRequest(server, {
      body: { status: 'under_review', admin_note: 'قيد الفحص' },
    });
    assert.equal(inReview.status, 200);
    assert.equal(inReview.body.data.status, 'under_review');

    const approved = await reviewRefundRequest(server);
    assert.equal(approved.status, 200);
    assert.equal(approved.body.data.status, 'approved');
    assert.equal(approved.body.data.approved_amount, 80);
    assert.equal(approved.body.data.reviewed_by, 'admin-1');
    assert.equal(
      store.values.customers['customer-1'].refund_requests['refund-1']
        .approved_amount,
      80,
    );

    const repeated = await reviewRefundRequest(server);
    assert.equal(repeated.status, 409);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('admin payment proof review validates and updates all records', async () => {
  const initial = {
    profiles: {
      'admin-1': {
        id: 'admin-1',
        role: 'admin',
        auth_uid: 'uid-admin',
      },
      'customer-1': {
        id: 'customer-1',
        role: 'customer',
        auth_uid: 'uid-customer',
      },
    },
    payment_proofs: {
      'proof-1': {
        id: 'proof-1',
        order_id: 'order-1',
        uploaded_by: 'customer-1',
        status: 'pending',
        image_url: 'https://example.test/receipt.png',
      },
      'proof-2': {
        id: 'proof-2',
        order_id: 'order-2',
        uploaded_by: 'customer-1',
        status: 'pending',
      },
      'proof-3': {
        id: 'proof-3',
        order_id: 'order-3',
        uploaded_by: 'customer-1',
        status: 'pending',
      },
    },
    orders: {
      'order-1': {
        id: 'order-1',
        customer_id: 'customer-1',
        payment_proof_id: 'proof-1',
        status: 'awaiting_confirmation',
      },
      'order-2': {
        id: 'order-2',
        customer_id: 'customer-1',
        payment_proof_id: 'proof-2',
        status: 'awaiting_confirmation',
      },
      'order-3': {
        id: 'order-3',
        customer_id: 'customer-1',
        payment_proof_id: 'different-proof',
        status: 'awaiting_confirmation',
      },
    },
    customers: {
      'customer-1': {
        orders: {
          'order-1': { id: 'order-1', status: 'awaiting_confirmation' },
          'order-2': { id: 'order-2', status: 'awaiting_confirmation' },
          'order-3': { id: 'order-3', status: 'awaiting_confirmation' },
        },
      },
    },
  };
  const { server, store } = await startDatabaseApp({
    initial,
    users: {
      'customer-token': customer,
      'admin-token': {
        uid: 'uid-admin',
        profile_id: 'admin-1',
        role: 'admin',
      },
    },
  });
  try {
    const customerReview = await reviewPaymentProof(server, {
      token: 'customer-token',
    });
    assert.equal(customerReview.status, 403);

    const genericAdminWrite = await request(
      server,
      'payment_proofs/proof-1',
      {
        method: 'PUT',
        token: 'admin-token',
        body: { status: 'approved' },
      },
    );
    assert.equal(genericAdminWrite.status, 403);

    const invalidStatus = await reviewPaymentProof(server, {
      body: { status: 'approved;admin' },
    });
    assert.equal(invalidStatus.status, 400);

    const approved = await reviewPaymentProof(server);
    assert.equal(approved.status, 200);
    assert.equal(approved.body.data.status, 'approved');
    assert.equal(approved.body.data.reviewed_by, 'admin-1');
    assert.equal(approved.body.order.status, 'new');
    assert.equal(
      store.values.customers['customer-1'].orders['order-1'].status,
      'new',
    );
    assert.equal(
      store.values.notifications['order-order-1-new'].profile_id,
      'customer-1',
    );

    const repeated = await reviewPaymentProof(server);
    assert.equal(repeated.status, 409);

    const rejected = await reviewPaymentProof(server, {
      proofId: 'proof-2',
      body: { status: 'rejected', review_note: 'الإيصال غير واضح' },
    });
    assert.equal(rejected.status, 200);
    assert.equal(rejected.body.order.status, 'cancelled');
    assert.equal(rejected.body.order.cancelled_by, 'admin');
    assert.equal(
      store.values.customers['customer-1'].orders['order-2'].status,
      'cancelled',
    );

    const mismatchedOrder = await reviewPaymentProof(server, {
      proofId: 'proof-3',
    });
    assert.equal(mismatchedOrder.status, 409);
    assert.equal(store.values.payment_proofs['proof-3'].status, 'pending');
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('merchant withdrawals use server balance and admin-only status transitions', async () => {
  const fourDaysAgo = new Date(
    Date.now() - 4 * 24 * 60 * 60 * 1000,
  ).toISOString();
  const initial = {
    profiles: {
      'merchant-1': {
        id: 'merchant-1',
        role: 'merchant',
        auth_uid: 'uid-merchant',
      },
      'merchant-2': {
        id: 'merchant-2',
        role: 'merchant',
        auth_uid: 'uid-merchant-2',
      },
      'admin-1': {
        id: 'admin-1',
        role: 'admin',
        auth_uid: 'uid-admin',
      },
      'customer-1': {
        id: 'customer-1',
        role: 'customer',
        auth_uid: 'uid-customer',
      },
    },
    products: {
      'product-1': { id: 'product-1', merchant_id: 'merchant-1' },
    },
    orders: {
      'delivered-order': {
        id: 'delivered-order',
        status: 'delivered',
        created_at: fourDaysAgo,
        items: [
          {
            product_id: 'product-1',
            quantity: 1,
            base_unit_price_yer: 200,
            total_yer: 230,
          },
        ],
      },
      'new-order': {
        id: 'new-order',
        status: 'new',
        items: [
          {
            product_id: 'product-1',
            quantity: 1,
            base_unit_price_yer: 1000,
            total_yer: 1200,
          },
        ],
      },
    },
    merchant_withdrawals: {
      'merchant-1': {
        'old-pending': {
          id: 'old-pending',
          merchant_id: 'merchant-1',
          amount: 30,
          status: 'pending',
        },
        'old-rejected': {
          id: 'old-rejected',
          merchant_id: 'merchant-1',
          amount: 70,
          status: 'rejected',
        },
      },
    },
    merchant_withdrawal_requests: {
      'old-pending': {
        id: 'old-pending',
        merchant_id: 'merchant-1',
        amount: 30,
        status: 'pending',
      },
    },
  };
  const { server, store } = await startDatabaseApp({
    initial,
    users: {
      'merchant-token': {
        uid: 'uid-merchant',
        profile_id: 'merchant-1',
        role: 'merchant',
      },
      'customer-token': customer,
      'admin-token': {
        uid: 'uid-admin',
        profile_id: 'admin-1',
        role: 'admin',
      },
    },
  });
  try {
    const ownWithdrawals = await request(
      server,
      'merchant_withdrawals/merchant-1',
      { token: 'merchant-token' },
    );
    assert.equal(ownWithdrawals.status, 200);
    const otherWithdrawals = await request(
      server,
      'merchant_withdrawals/merchant-2',
      { token: 'merchant-token' },
    );
    assert.equal(otherWithdrawals.status, 403);

    const insufficient = await createMerchantWithdrawal(server, {
      body: {
        amount: 171,
        account_name: 'محفظة التاجر',
        account_number: '700123456',
      },
    });
    assert.equal(insufficient.status, 409);

    const customerRequest = await createMerchantWithdrawal(server, {
      token: 'customer-token',
    });
    assert.equal(customerRequest.status, 403);

    const genericAdminWrite = await request(
      server,
      'merchant_withdrawal_requests/old-pending',
      {
        method: 'PUT',
        token: 'admin-token',
        body: { status: 'paid' },
      },
    );
    assert.equal(genericAdminWrite.status, 403);
    const genericMerchantWrite = await request(
      server,
      'merchant_withdrawals/merchant-1/old-pending',
      {
        method: 'PUT',
        token: 'merchant-token',
        body: { status: 'paid' },
      },
    );
    assert.equal(genericMerchantWrite.status, 403);

    const unauthorizedReview = await reviewMerchantWithdrawal(server, {
      requestId: 'old-pending',
      token: 'merchant-token',
    });
    assert.equal(unauthorizedReview.status, 403);

    const created = await createMerchantWithdrawal(server, {
      body: {
        amount: 100,
        account_name: ' محفظة التاجر ',
        account_number: ' 700123456 ',
        merchant_id: 'merchant-2',
        currency_symbol: 'ر.س',
      },
    });
    assert.equal(created.status, 201);
    assert.equal(created.body.data.merchant_id, 'merchant-1');
    assert.equal(created.body.data.currency_symbol, 'ر.ي');
    assert.equal(created.body.data.amount, 100);
    assert.equal(created.body.withdrawable_balance, 70);
    assert.equal(created.body.data.account_name, 'محفظة التاجر');
    const requestId = created.body.data.id;
    assert.deepEqual(
      store.values.merchant_withdrawals['merchant-1'][requestId],
      store.values.merchant_withdrawal_requests[requestId],
    );

    const approved = await reviewMerchantWithdrawal(server, {
      requestId,
    });
    assert.equal(approved.status, 200);
    assert.equal(approved.body.data.status, 'approved');
    assert.equal(approved.body.data.reviewed_by, 'admin-1');

    const rejectedAfterApproval = await reviewMerchantWithdrawal(server, {
      requestId,
      body: { status: 'rejected' },
    });
    assert.equal(rejectedAfterApproval.status, 409);

    const paid = await reviewMerchantWithdrawal(server, {
      requestId,
      body: { status: 'paid' },
    });
    assert.equal(paid.status, 200);
    assert.equal(paid.body.data.paid_by, 'admin-1');
    assert.equal(
      store.values.merchant_withdrawals['merchant-1'][requestId].status,
      'paid',
    );

    const repeated = await reviewMerchantWithdrawal(server, {
      requestId,
      body: { status: 'paid' },
    });
    assert.equal(repeated.status, 409);

    const concurrentRequests = await Promise.all([
      createMerchantWithdrawal(server, {
        body: {
          amount: 40,
          account_name: 'محفظة التاجر',
          account_number: '700123456',
        },
      }),
      createMerchantWithdrawal(server, {
        body: {
          amount: 40,
          account_name: 'محفظة التاجر',
          account_number: '700123456',
        },
      }),
    ]);
    assert.deepEqual(
      concurrentRequests.map((result) => result.status).sort(),
      [201, 409],
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
