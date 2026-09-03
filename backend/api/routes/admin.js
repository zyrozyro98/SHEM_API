const express = require('express');
const router = express.Router();
const db = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');

function requireAdmin(req, res, next) {
  const profile = req.user || {};
  if (profile.role !== 'admin') return res.status(403).json({ error: 'Admin only' });
  next();
}

// Get pending orders (pending_payment)
router.get('/orders/pending', authMiddleware, requireAdmin, async (req, res) => {
  try {
    const { rows } = await db.query("select * from orders where status = 'pending_payment' order by created_at desc");
    res.json({ orders: rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// Approve an order/payment: approve related payment proofs and mark order confirmed
router.patch('/orders/:id/approve', authMiddleware, requireAdmin, async (req, res) => {
  const client = await db.pool.connect();
  try {
    const admin = req.user;
    const orderId = req.params.id;
    await client.query('BEGIN');
    // Approve any pending payment proofs for this order
    await client.query("update payment_proofs set status = 'approved' where order_id = $1 and status = 'pending'", [orderId]);
    // Update order status to confirmed
    const { rows } = await client.query("update orders set status = 'confirmed', updated_at = now() where id = $1 returning *", [orderId]);
    if (!rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Order not found' });
    }
    // Insert order status history
    await client.query('insert into order_status_history(id, order_id, status, changed_by, note, created_at) values($1,$2,$3,$4,$5, now())', [uuidv4(), orderId, 'confirmed', admin.id, 'Approved by admin']);
    await client.query('COMMIT');
    res.json(rows[0]);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  } finally {
    client.release();
  }
});

// Reject payment proofs for an order and set order back to pending_payment
router.patch('/orders/:id/reject', authMiddleware, requireAdmin, async (req, res) => {
  const client = await db.pool.connect();
  try {
    const admin = req.user;
    const orderId = req.params.id;
    await client.query('BEGIN');
    // Reject pending payment proofs
    await client.query("update payment_proofs set status = 'rejected' where order_id = $1 and status = 'pending'", [orderId]);
    // Optionally set order status back to pending_payment
    const { rows } = await client.query("update orders set status = 'pending_payment', updated_at = now() where id = $1 returning *", [orderId]);
    if (!rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Order not found' });
    }
    await client.query('insert into order_status_history(id, order_id, status, changed_by, note, created_at) values($1,$2,$3,$4,$5, now())', [uuidv4(), orderId, 'pending_payment', admin.id, 'Payment rejected by admin']);
    await client.query('COMMIT');
    res.json(rows[0]);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  } finally {
    client.release();
  }
});

module.exports = router;
