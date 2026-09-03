const express = require('express');
const router = express.Router();
const multer = require('multer');
const upload = multer({ storage: multer.memoryStorage() });
const { createClient } = require('@supabase/supabase-js');
const db = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');

if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
  console.warn('SUPABASE storage will not work until SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are set');
}

const supa = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY
  ? createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY)
  : null;
const BUCKET = process.env.SUPABASE_PROOFS_BUCKET || 'payment-proofs';

// Upload payment proof (multipart form with file field `file`)
router.post('/proofs', authMiddleware, upload.single('file'), async (req, res) => {
  try {
    if (!supa) return res.status(503).json({ error: 'Payment storage is not configured' });
    const profile = req.user || {};
    const { order_id, note } = req.body;
    if (!order_id) return res.status(400).json({ error: 'order_id required' });
    if (!req.file) return res.status(400).json({ error: 'file required' });

    const fileName = `${uuidv4()}_${req.file.originalname.replace(/[^a-z0-9_.-]/ig,'')}`;
    const path = `${fileName}`;
    const { data, error } = await supa.storage.from(BUCKET).upload(path, req.file.buffer, { contentType: req.file.mimetype, upsert: false });
    if (error) {
      console.error('upload error', error);
      return res.status(500).json({ error: 'Storage upload failed' });
    }
    const publicUrl = supa.storage.from(BUCKET).getPublicUrl(path).data.publicUrl || null;

    const id = uuidv4();
    await db.query(`insert into payment_proofs(id, order_id, uploaded_by, image_url, note, status, created_at) values($1,$2,$3,$4,$5,'pending', now())`, [id, order_id, profile.id, publicUrl, note || null]);
    res.status(201).json({ id, image_url: publicUrl });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;

// Admin: update payment proof status
router.patch('/proofs/:id', authMiddleware, async (req, res) => {
  try {
    const profile = req.user || {};
    if (profile.role !== 'admin') return res.status(403).json({ error: 'Admin only' });
    const proofId = req.params.id;
    const { status } = req.body;
    if (!['pending','approved','rejected'].includes(status)) return res.status(400).json({ error: 'Invalid status' });
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');
      const { rows } = await client.query('update payment_proofs set status = $1 where id = $2 returning *', [status, proofId]);
      if (!rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Not found' }); }
      const proof = rows[0];
      if (status === 'approved') {
        // mark order as confirmed
        await client.query("update orders set status = 'confirmed', updated_at = now() where id = $1", [proof.order_id]);
        await client.query('insert into order_status_history(id, order_id, status, changed_by, note, created_at) values($1,$2,$3,$4,$5, now())', [require('uuid').v4(), proof.order_id, 'confirmed', profile.id, 'Payment proof approved']);
      }
      await client.query('COMMIT');
      res.json(proof);
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(err);
      res.status(500).json({ error: 'DB error' });
    } finally {
      client.release();
    }
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
});
