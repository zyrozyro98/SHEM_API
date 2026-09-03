const express = require('express');
const router = express.Router();
const db = require('../db');
const { v4: uuidv4 } = require('uuid');
const { authMiddleware } = require('../middleware/auth');

// Create order
router.post('/', authMiddleware, async (req, res) => {
  const client = await db.pool.connect();
  try {
    const profile = req.user || {};
    const { items, payment_method, subtotal, shipping_fee, total, delivery_address } = req.body;
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'invalid items' });
    }
    await client.query('BEGIN');
    const orderId = uuidv4();
    const insertOrderQ = `insert into orders(id, customer_id, payment_method, subtotal, shipping_fee, total, delivery_address, created_at)
      values($1,$2,$3,$4,$5,$6,$7, now())`;
    await client.query(insertOrderQ, [orderId, profile.id, payment_method || 'cash_on_delivery', subtotal || 0, shipping_fee || 0, total || 0, delivery_address || null]);
    const insertItemQ = `insert into order_items(id, order_id, product_id, product_name, quantity, unit_price, total, created_at)
      values($1,$2,$3,$4,$5,$6,$7, now())`;
    for (const it of items) {
      const itemId = uuidv4();
      await client.query(insertItemQ, [itemId, orderId, it.product_id, it.product_name, it.quantity, it.unit_price, it.total]);
    }
    await client.query('COMMIT');
    res.status(201).json({ id: orderId });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  } finally {
    client.release();
  }
});

// Get orders (for customer)
router.get('/', authMiddleware, async (req, res) => {
  try {
    const profile = req.user || {};
    const { rows } = await db.query('select * from orders where customer_id = $1 order by created_at desc', [profile.id]);
    res.json({ orders: rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

module.exports = router;
