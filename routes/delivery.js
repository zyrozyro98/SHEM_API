const express = require('express');
const router = express.Router();
const db = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');

// Post a delivery update (authenticated users related to order or admin)
router.post('/update', authMiddleware, async (req, res) => {
  try {
    const profile = req.user || {};
    const { order_id, courier_name, current_location, eta, status } = req.body;
    if (!order_id) return res.status(400).json({ error: 'order_id required' });

    // Optional: verify user is related to the order or is admin
    const { rows: orderRows } = await db.query('select customer_id from orders where id = $1', [order_id]);
    if (!orderRows.length) return res.status(404).json({ error: 'Order not found' });
    const customerId = orderRows[0].customer_id;
    if (profile.role !== 'admin' && profile.id !== customerId) {
      return res.status(403).json({ error: 'Not authorized to update this order delivery' });
    }

    const id = uuidv4();
    await db.query('insert into delivery_updates(id, order_id, courier_name, current_location, eta, status, created_at) values($1,$2,$3,$4,$5,$6, now())', [id, order_id, courier_name || null, current_location || null, eta || null, status || 'updated']);
    res.status(201).json({ id });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// Get delivery updates for an order (any related user)
router.get('/:order_id', authMiddleware, async (req, res) => {
  try {
    const profile = req.user || {};
    const orderId = req.params.order_id;
    const { rows: orderRows } = await db.query('select customer_id from orders where id = $1', [orderId]);
    if (!orderRows.length) return res.status(404).json({ error: 'Order not found' });
    const customerId = orderRows[0].customer_id;
    if (profile.role !== 'admin' && profile.id !== customerId) {
      return res.status(403).json({ error: 'Not authorized' });
    }
    const { rows } = await db.query('select * from delivery_updates where order_id = $1 order by created_at desc', [orderId]);
    res.json({ updates: rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

module.exports = router;
