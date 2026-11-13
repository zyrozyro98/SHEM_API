const crypto = require('crypto');
const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const accountsRouter = require('../routes/accounts');

function hashPassword(password) {
  return crypto.createHash('sha256').update(password).digest('hex');
}

async function requestDeletion(
  data,
  profileId,
  requesterPhone,
  password,
  deleteAuthUser,
) {
  const authDeletions = [];
  const updates = [];
  const dependencies = {
    read: async (path) => structuredClone(pathValue(data, path) ?? {}),
    update: async (changes) => {
      updates.push(changes);
      for (const [path, value] of Object.entries(changes)) {
        setPath(data, path, value);
      }
    },
    deleteAuthUser: deleteAuthUser ?? (async (uid) => authDeletions.push(uid)),
  };
  const app = express();
  app.use(express.json());
  app.use('/accounts', accountsRouter.createAccountsRouter(dependencies));
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));

  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/accounts/${profileId}`,
      {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          requester_phone: requesterPhone,
          requester_password: password,
        }),
      },
    );
    return {
      status: response.status,
      body: await response.json(),
      authDeletions,
      updates,
    };
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function pathValue(root, path) {
  return path.split('/').reduce((value, key) => value?.[key], root);
}

function setPath(root, path, value) {
  const keys = path.split('/');
  const last = keys.pop();
  let parent = root;
  for (const key of keys) parent = parent[key] ??= {};
  if (value === null) delete parent[last];
  else parent[last] = value;
}

function profiles(requesterRole, targetRole = requesterRole) {
  return {
    requester: {
      id: 'requester',
      phone: '771111111',
      role: requesterRole,
      password_hash: hashPassword('correct horse'),
    },
    target: {
      id: 'target',
      phone: '772222222',
      role: targetRole,
      password_hash: hashPassword('target password'),
      auth_uid: 'target-auth-uid',
    },
  };
}

test('customer deletion is blocked while any order is not delivered or cancelled', async () => {
  const data = {
    profiles: {
      customer: {
        id: 'customer',
        phone: '771111111',
        role: 'customer',
        password_hash: hashPassword('correct horse'),
      },
    },
    orders: {
      order1: { customer_id: 'customer', status: 'new' },
    },
  };

  const result = await requestDeletion(data, 'customer', '771111111', 'correct horse');

  assert.equal(result.status, 409);
  assert.equal(result.body.error_code, 'customer_active_orders');
  assert.ok(data.profiles.customer);
  assert.deepEqual(result.authDeletions, []);
});

test('customer can delete after all orders are delivered or cancelled', async () => {
  const data = {
    profiles: {
      customer: {
        id: 'customer',
        phone: '771111111',
        role: 'customer',
        password_hash: hashPassword('correct horse'),
        auth_uid: 'customer-auth-uid',
      },
    },
    auth_index: {
      'customer-auth-uid': { phone: '771111111' },
    },
    customers: {
      customer: {
        orders: {
          order1: { customer_id: 'customer', status: 'cancelled' },
        },
      },
    },
    orders: {
      order2: { customer_id: 'customer', status: 'delivered' },
    },
  };

  const result = await requestDeletion(
    data,
    'customer',
    '771111111',
    'correct horse',
  );

  assert.equal(result.status, 200);
  assert.equal(data.profiles.customer, undefined);
  assert.equal(data.customers.customer, undefined);
  assert.deepEqual(result.authDeletions, ['customer-auth-uid']);
});

test('merchant deletion is blocked by a non-rejected item in a new order', async () => {
  const data = {
    profiles: profiles('admin', 'merchant'),
    products: {
      product1: { id: 'product1', merchant_id: 'target', available: true },
    },
    orders: {
      order1: {
        status: 'new',
        items: [{ product_id: 'product1', status: 'available' }],
      },
    },
  };

  const result = await requestDeletion(data, 'target', '771111111', 'correct horse');

  assert.equal(result.status, 409);
  assert.equal(result.body.error_code, 'merchant_active_orders');
  assert.ok(data.profiles.target);
  assert.equal(data.products.product1.available, true);
  assert.deepEqual(result.authDeletions, []);
});

test('admin can delete an eligible merchant and archived listings retain history', async () => {
  const data = {
    profiles: profiles('admin', 'merchant'),
    auth_index: {
      'target-auth-uid': { phone: '772222222' },
    },
    products: {
      product1: { id: 'product1', merchant_id: 'target', available: true },
    },
    orders: {
      order1: {
        status: 'delivered',
        items: [{ product_id: 'product1', status: 'available' }],
      },
    },
  };

  const result = await requestDeletion(data, 'target', '771111111', 'correct horse');

  assert.equal(result.status, 200);
  assert.equal(data.profiles.target, undefined);
  assert.equal(data.auth_index['target-auth-uid'], undefined);
  assert.equal(data.products.product1.available, false);
  assert.equal(data.products.product1.is_archived, true);
  assert.equal(data.orders.order1.status, 'delivered');
  assert.deepEqual(result.authDeletions, ['target-auth-uid']);
});

test('invalid reauthentication cannot delete an account', async () => {
  const data = {
    profiles: profiles('admin', 'customer'),
    orders: {},
  };

  const result = await requestDeletion(data, 'target', '771111111', 'wrong password');

  assert.equal(result.status, 401);
  assert.equal(result.body.error_code, 'invalid_credentials');
  assert.ok(data.profiles.target);
  assert.deepEqual(result.updates, []);
});

test('database changes are restored when Firebase Auth deletion fails', async () => {
  const data = {
    profiles: profiles('admin', 'merchant'),
    auth_index: {
      'target-auth-uid': { phone: '772222222' },
    },
    products: {
      product1: { id: 'product1', merchant_id: 'target', available: true },
    },
    orders: {},
  };

  const result = await requestDeletion(
    data,
    'target',
    '771111111',
    'correct horse',
    async () => {
      throw new Error('Firebase Auth unavailable');
    },
  );

  assert.equal(result.status, 500);
  assert.ok(data.profiles.target);
  assert.deepEqual(data.auth_index['target-auth-uid'], {
    phone: '772222222',
  });
  assert.equal(data.products.product1.available, true);
  assert.equal(data.products.product1.is_archived, undefined);
});