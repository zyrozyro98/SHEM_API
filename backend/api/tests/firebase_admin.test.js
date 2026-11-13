const test = require('node:test');
const assert = require('node:assert/strict');
const { getFirebaseApp } = require('../services/firebase_admin');

test('invalid service account JSON is reported as a configuration error', () => {
  const previousServiceAccount = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  const previousDatabaseUrl = process.env.FIREBASE_DATABASE_URL;
  process.env.FIREBASE_SERVICE_ACCOUNT_JSON = '{invalid';
  process.env.FIREBASE_DATABASE_URL = 'https://example.firebaseio.com';

  try {
    assert.throws(
      () => getFirebaseApp(),
      (error) => error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED',
    );
  } finally {
    if (previousServiceAccount === undefined) {
      delete process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    } else {
      process.env.FIREBASE_SERVICE_ACCOUNT_JSON = previousServiceAccount;
    }
    if (previousDatabaseUrl === undefined) {
      delete process.env.FIREBASE_DATABASE_URL;
    } else {
      process.env.FIREBASE_DATABASE_URL = previousDatabaseUrl;
    }
  }
});
