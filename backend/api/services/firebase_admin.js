const { cert, getApp, getApps, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getDatabase } = require('firebase-admin/database');
const { getStorage } = require('firebase-admin/storage');

let firebaseApp;

function getFirebaseApp() {
  if (firebaseApp) return firebaseApp;
  if (getApps().length) {
    firebaseApp = getApp();
    return firebaseApp;
  }

  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  const databaseURL = process.env.FIREBASE_DATABASE_URL;
  if (!serviceAccountJson || !databaseURL) {
    const error = new Error('Firebase Admin is not configured');
    error.code = 'FIREBASE_ADMIN_NOT_CONFIGURED';
    throw error;
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(serviceAccountJson);
  } catch {
    const error = new Error(
      'FIREBASE_SERVICE_ACCOUNT_JSON must contain valid JSON',
    );
    error.code = 'FIREBASE_ADMIN_NOT_CONFIGURED';
    throw error;
  }

  const projectId =
    process.env.GCLOUD_PROJECT?.trim() || serviceAccount.project_id?.trim();
  if (!projectId) {
    const error = new Error('Firebase project ID is not configured');
    error.code = 'FIREBASE_ADMIN_NOT_CONFIGURED';
    throw error;
  }

  firebaseApp = initializeApp({
    credential: cert(serviceAccount),
    projectId,
    databaseURL,
    storageBucket:
      process.env.FIREBASE_STORAGE_BUCKET?.trim() ||
      `${projectId}.firebasestorage.app`,
  });
  return firebaseApp;
}

function getFirebaseDatabase() {
  return getDatabase(getFirebaseApp());
}

function getFirebaseAuth() {
  return getAuth(getFirebaseApp());
}

function getFirebaseStorage() {
  return getStorage(getFirebaseApp());
}

module.exports = {
  getFirebaseApp,
  getFirebaseAuth,
  getFirebaseDatabase,
  getFirebaseStorage,
};
