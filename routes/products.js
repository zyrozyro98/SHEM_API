const express = require('express');
const router = express.Router();
const db = require('../db');
const Joi = require('joi');
const { v4: uuidv4 } = require('uuid');
const { authMiddleware } = require('../middleware/auth');

const productSchema = Joi.object({
  merchant_id: Joi.string().guid().required(),
  name: Joi.string().required(),
  category: Joi.string().required(),
  description: Joi.string().allow('', null),
  price: Joi.number().min(0).required(),
  image_url: Joi.string().uri().allow(null),
  available: Joi.boolean()
});

// List products (public)
router.get('/', async (req, res) => {
  try {
    const { rows } = await db.query('select * from products where available = true');
    res.json({ products: rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// Get product
router.get('/:id', async (req, res) => {
  try {
    const { rows } = await db.query('select * from products where id = $1', [req.params.id]);
    if (!rows.length) return res.status(404).json({ error: 'Not found' });
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// Create product (merchant only)
router.post('/', authMiddleware, async (req, res) => {
  try {
    const profile = req.user || {};
    if (profile.role !== 'merchant' && profile.role !== 'admin') {
      return res.status(403).json({ error: 'Only merchants or admins can create products' });
    }
    const payload = req.body;
    const { error } = productSchema.validate(payload);
    if (error) return res.status(400).json({ error: error.message });
    const id = uuidv4();
    const q = `insert into products(id, merchant_id, name, category, description, price, image_url, available, created_at)
               values($1,$2,$3,$4,$5,$6,$7,$8, now()) returning *`;
    const params = [id, payload.merchant_id, payload.name, payload.category, payload.description || null, payload.price, payload.image_url || null, payload.available ?? true];
    const { rows } = await db.query(q, params);
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// Update product (merchant owner or admin)
router.patch('/:id', authMiddleware, async (req, res) => {
  try {
    const profile = req.user || {};
    const { rows: exists } = await db.query('select * from products where id = $1', [req.params.id]);
    if (!exists.length) return res.status(404).json({ error: 'Not found' });
    const product = exists[0];
    if (profile.role !== 'admin' && product.merchant_id !== profile.id) {
      return res.status(403).json({ error: 'Not authorized' });
    }
    const updates = req.body;
    const allowed = ['name','category','description','price','image_url','available'];
    const set = [];
    const vals = [];
    let idx = 1;
    for (const k of allowed) {
      if (k in updates) {
        set.push(`${k} = $${idx}`);
        vals.push(updates[k]);
        idx++;
      }
    }
    if (!set.length) return res.status(400).json({ error: 'No fields to update' });
    const q = `update products set ${set.join(', ')} where id = $${idx} returning *`;
    vals.push(req.params.id);
    const { rows: updated } = await db.query(q, vals);
    res.json(updated[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

module.exports = router;
