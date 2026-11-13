const admin = require('firebase-admin');

let firebaseApp;

function getFirebaseApp() {
  if (firebaseApp) return firebaseApp;
  if (admin.apps.length) {
    firebaseApp = admin.app();
    return firebaseApp;
  }

  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  const databaseURL = process.env.FIREBASE_DATABASE_URL;
  if (!serviceAccountJson || !databaseURL) {
    const error = new Error('Firebase Admin is not configured');
    error.code = 'FIREBASE_ADMIN_NOT_CONFIGURED';
    throw error;
  }

  firebaseApp = admin.initializeApp({
    credential: admin.credential.cert(JSON.parse(serviceAccountJson)),
    databaseURL,
  });
  return firebaseApp;
}

module.exports = { getFirebaseApp };
