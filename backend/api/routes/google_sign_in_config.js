const express = require('express');

function createGoogleSignInConfigRouter({
  getClientId = () => process.env.GOOGLE_WEB_CLIENT_ID,
} = {}) {
  const router = express.Router();

  router.get('/google-sign-in', (_req, res) => {
    const clientId = String(getClientId() || '').trim();
    if (!clientId) {
      return res.status(503).json({
        error: 'Google web sign-in is not configured',
      });
    }

    res.set('Cache-Control', 'no-store');
    return res.json({ client_id: clientId });
  });

  return router;
}

module.exports = createGoogleSignInConfigRouter();
module.exports.createGoogleSignInConfigRouter = createGoogleSignInConfigRouter;
