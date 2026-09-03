const express = require('express');
const router = express.Router();
const db = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');

// Get notifications for authenticated user
router.get('/', authMiddleware, async (req, res) => {
  try {
    const profile = req.user || {};
    if (!profile.id) return res.status(400).json({ error: 'Profile not found' });
    const { rows } = await db.query('select * from notifications where profile_id = $1 order by created_at desc', [profile.id]);
    res.json({ notifications: rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// Admin: create notification for a user
router.post('/', authMiddleware, async (req, res) => {
  try {
    const profile = req.user || {};
    if (profile.role !== 'admin') return res.status(403).json({ error: 'Admin only' });
    const { profile_id, title, body } = req.body;
    if (!profile_id || !title || !body) return res.status(400).json({ error: 'profile_id, title and body required' });
    const id = uuidv4();
    await db.query('insert into notifications(id, profile_id, title, body, is_read, created_at) values($1,$2,$3,$4,false, now())', [id, profile_id, title, body]);
    res.status(201).json({ id });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

module.exports = router;
