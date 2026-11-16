const express = require('express');
const { getFirebaseDatabase } = require('../services/firebase_admin');

const publicFields = [
  'active',
  'latest_version',
  'title',
  'message',
  'download_url',
  'target_roles',
  'importance',
];

function createAppUpdateRouter({
  getDatabase = getFirebaseDatabase,
} = {}) {
  const router = express.Router();

  router.get('/notice', async (_req, res) => {
    try {
      const snapshot = await getDatabase()
        .ref('app_settings/app_update_notice')
        .once('value');
      const value = snapshot.val();
      if (!value || typeof value !== 'object' || Array.isArray(value)) {
        return res.json({});
      }

      const notice = {};
      for (const field of publicFields) {
        if (Object.prototype.hasOwnProperty.call(value, field)) {
          notice[field] = value[field];
        }
      }
      return res.json(notice);
    } catch (error) {
      console.error('Failed to read public app update notice:', error);
      return res.status(503).json({ error: 'Update settings unavailable' });
    }
  });

  return router;
}

module.exports = createAppUpdateRouter();
module.exports.createAppUpdateRouter = createAppUpdateRouter;
