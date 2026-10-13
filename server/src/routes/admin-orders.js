// Owner's Order Board (FR-04, FR-11; Admin Orders 1-4): New, Processing, Out for Delivery and
// Delivered tabs, a filter for Not delivered / Declined / Cancelled, Order Details with the timeline,
// Accept (one, several or all, one rider, automatic delivery time), Decline with a reason, Change rider.
const { Router } = require('express');
const { one, query, transaction } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad, notFound, conflict } = require('../utils/errors');
const { text } = require('../utils/validate');
const { now, estimatedDelivery, deliveryText, todayStart } = require('../services/time');
const { shapeOrder, ORDER_SELECT, timeline, addHistory, notifyCustomer, stationPoint, firstName } = require('../services/orders');
const { recordDelivered, recordNotDelivered } = require('../services/process');

const router = Router();
router.use(requireAuth, requireRole('Owner'));

const DECLINE_REASONS = ['Run out of water', 'Out of new gallons', 'Outside delivery area', 'Closed', 'Too many orders', 'Other'];
const CANCEL_REASONS = ['Customer asked to cancel', 'Cannot reach customer', 'Out of stock', 'Other'];

// Which orders each tab and filter shows. Delivered, declined, cancelled and "all" are today's;
// Not delivered stays until the owner re-delivers or cancels it.
const VIEWS = {
  new: ["o.status = 'New'", []],
  processing: ["o.status = 'Processing'", []],
  out: ["o.status = 'Out for Delivery'", []],
  delivered: ["o.status = 'Delivered' AND o.delivered_at >= ?", ['today']],
  'not-delivered': ["o.status = 'Not Delivered'", []],
  declined: ["o.status = 'Declined' AND o.updated_at >= ?", ['today']],
  cancelled: ["o.status = 'Cancelled' AND o.updated_at >= ?", ['today']],
  all: ["o.status <> 'Recorded' AND o.created_at >= ?", ['today']],
};
const ORDER_BY = {
  new: 'o.created_at, o.order_id',
  processing: 'o.est_delivery_to, o.order_id',
  out: 'o.out_at, o.order_id',
  delivered: 'o.delivered_at DESC',
};

async function counts() {
  const t = todayStart();
  const r = await one(
    `SELECT SUM(status = 'New') AS c_new, SUM(status = 'Processing') AS c_processing, SUM(status = 'Out for Delivery') AS c_out,
       SUM(status = 'Delivered' AND delivered_at >= ?) AS c_delivered, SUM(status = 'Not Delivered') AS c_not_delivered
     FROM orders`,
    [t]
  );
  const n = (v) => Number(v || 0);
  return { new: n(r.c_new), processing: n(r.c_processing), out: n(r.c_out), delivered: n(r.c_delivered), notDelivered: n(r.c_not_delivered) };
}

// GET /api/admin/orders?view=new|processing|out|delivered|not-delivered|declined|cancelled|all -> { orders, counts }
router.get('/', async (req, res) => {
  const view = VIEWS[req.query.view] ? req.query.view : 'new';
  const [where, params] = VIEWS[view];
  const station = await stationPoint();
  const rows = await query(
    `${ORDER_SELECT} WHERE o.order_source <> 'Walk-in' AND ${where} ORDER BY ${ORDER_BY[view] || 'o.updated_at DESC'}`,
    params.map((p) => (p === 'today' ? todayStart() : p))
  );
  res.json({ view, orders: rows.map((o) => shapeOrder(o, station)), counts: await counts() });
});

// GET /api/admin/orders/riders -> { riders: [{ id, name, owner }] } (active riders, then Me (Owner))
router.get('/riders', async (req, res) => {
  const rows = await query("SELECT user_id, full_name FROM users WHERE role = 'Rider' AND is_active = 1 ORDER BY full_name");
  res.json({
    riders: [...rows.map((r) => ({ id: r.user_id, name: r.full_name, owner: false })), { id: req.user.user_id, name: 'Me (Owner)', owner: true }],
    reasons: DECLINE_REASONS,
    cancelReasons: CANCEL_REASONS,
  });
});

async function getOrder(id) {
  const o = await one(`${ORDER_SELECT} WHERE o.order_id = ?`, [Number(id) || 0]);
  if (!o) throw notFound('ORDER_NOT_FOUND', 'Order not found', 'It may have been removed.');
  return o;
}

// GET /api/admin/orders/:id -> { order, timeline }
router.get('/:id', async (req, res) => {
  const o = await getOrder(req.params.id);
  res.json({ order: shapeOrder(o, await stationPoint()), timeline: await timeline(o.order_id) });
});

/** The rider for an order: an active rider, or the owner. */
async function readRider(req) {
  const id = Number((req.body || {}).riderId);
  const r = id ? await one("SELECT user_id, full_name, role FROM users WHERE user_id = ? AND is_active = 1 AND role IN ('Rider','Owner')", [id]) : null;
  if (!r) throw bad('RIDER_MISSING', 'Choose one rider', 'Pick a rider or Me (Owner).', { field: 'rider' });
  return r;
}
const riderLabel = (r) => (r.role === 'Owner' ? 'Owner' : firstName(r.full_name));

// POST /api/admin/orders/accept { ids: [..], riderId } -> { accepted, message }
router.post('/accept', async (req, res) => {
  const ids = [...new Set(((req.body || {}).ids || []).map(Number).filter((n) => Number.isInteger(n) && n > 0))];
  if (!ids.length) throw bad('NONE_SELECTED', 'No orders selected', 'Tick at least one new order.');
  const rider = await readRider(req);
  const t = now();
  const est = estimatedDelivery(t);
  const when = deliveryText(est.from, est.to);

  await transaction(async (conn) => {
    const [rows] = await conn.query("SELECT * FROM orders WHERE order_id IN (?) AND status = 'New' FOR UPDATE", [ids]);
    if (rows.length !== ids.length) {
      throw conflict('ALREADY_HANDLED', 'Some orders changed', 'An order was cancelled or already handled. The list is refreshed.');
    }
    await conn.query(
      `UPDATE orders SET status = 'Processing', rider_id = ?, accepted_by = ?, accepted_at = ?, est_delivery_from = ?, est_delivery_to = ?
       WHERE order_id IN (?)`,
      [rider.user_id, req.user.user_id, t, est.from, est.to, ids]
    );
    for (const o of rows) {
      await addHistory(conn, o.order_id, 'Order accepted', req.user.user_id, `Rider: ${riderLabel(rider)}`, t);
      await addHistory(conn, o.order_id, 'Processing', req.user.user_id, `Delivery ${when}`, t);
      await notifyCustomer(conn, o, {
        type: 'Order Accepted',
        title: 'Order accepted',
        message: `Your refill order is processing. Estimated delivery: ${when}.`,
      });
    }
  });
  res.json({
    accepted: ids.length,
    estText: when,
    message: ids.length === 1 ? 'Accepted. Customer notified.' : `${ids.length} orders accepted`,
  });
});

// POST /api/admin/orders/:id/decline { reason, other } -> { order }
router.post('/:id/decline', async (req, res) => {
  const o = await getOrder(req.params.id);
  const b = req.body || {};
  if (!DECLINE_REASONS.includes(b.reason)) throw bad('REASON_MISSING', 'Choose reason', 'Pick why the order is declined.');
  const reason = b.reason === 'Other' ? text(b.other, 150) : b.reason;
  if (!reason) throw bad('REASON_MISSING', 'Type the reason', 'The customer sees this reason.', { field: 'other' });
  await transaction(async (conn) => {
    const [r] = await conn.query("UPDATE orders SET status = 'Declined' WHERE order_id = ? AND status = 'New'", [o.order_id]);
    if (r.affectedRows !== 1) throw conflict('ALREADY_HANDLED', 'Order changed', 'It was cancelled or already handled.');
    await addHistory(conn, o.order_id, 'Declined', req.user.user_id, reason);
    await notifyCustomer(conn, o, { type: 'Order Declined', title: 'Order declined', message: reason });
  });
  const fresh = await getOrder(o.order_id);
  res.json({ order: shapeOrder(fresh, await stationPoint()), message: 'Declined. Customer sees the reason.' });
});

// POST /api/admin/orders/:id/rider { riderId } -> { order } (Processing only; locked once out for delivery)
router.post('/:id/rider', async (req, res) => {
  const o = await getOrder(req.params.id);
  const rider = await readRider(req);
  await transaction(async (conn) => {
    const [r] = await conn.query("UPDATE orders SET rider_id = ? WHERE order_id = ? AND status = 'Processing'", [rider.user_id, o.order_id]);
    if (r.affectedRows !== 1) throw conflict('RIDER_LOCKED', 'Rider cannot be changed', 'Only while the order is in Processing.');
    await addHistory(conn, o.order_id, 'Rider changed', req.user.user_id, `Rider: ${riderLabel(rider)}`);
  });
  const fresh = await getOrder(o.order_id);
  res.json({ order: shapeOrder(fresh, await stationPoint()), message: 'Rider notified.' });
});

// POST /api/admin/orders/:id/cancel { reason, other } -> { order }
// Cancel an accepted order (Processing) or a Not delivered one. Gallons already counted stay counted.
router.post('/:id/cancel', async (req, res) => {
  const o = await getOrder(req.params.id);
  const b = req.body || {};
  if (!CANCEL_REASONS.includes(b.reason)) throw bad('REASON_MISSING', 'Choose a reason', 'Pick why the order is cancelled.');
  const reason = b.reason === 'Other' ? text(b.other, 150) : b.reason;
  if (!reason) throw bad('REASON_MISSING', 'Type the reason', 'The customer sees this reason.', { field: 'other' });
  await transaction(async (conn) => {
    const [r] = await conn.query(
      "UPDATE orders SET status = 'Cancelled' WHERE order_id = ? AND status IN ('New','Processing','Not Delivered')",
      [o.order_id]
    );
    if (r.affectedRows !== 1) throw conflict('CANNOT_CANCEL', 'Cannot cancel', 'Only new, Processing or Not delivered orders can be cancelled.');
    await addHistory(conn, o.order_id, 'Cancelled', req.user.user_id, reason);
    await notifyCustomer(conn, o, { type: 'Order Cancelled', title: 'Order cancelled', message: reason });
  });
  const fresh = await getOrder(o.order_id);
  res.json({ order: shapeOrder(fresh, await stationPoint()), message: 'Order cancelled. Customer notified.' });
});

// POST /api/admin/orders/:id/redeliver -> { order }  Not delivered -> back to Processing for the next
// batch (same rider, can be changed); new delivery time; not counted again in the tank counter.
router.post('/:id/redeliver', async (req, res) => {
  const o = await getOrder(req.params.id);
  const t = now();
  const est = estimatedDelivery(t);
  await transaction(async (conn) => {
    const [r] = await conn.query(
      "UPDATE orders SET status = 'Processing', batch_id = NULL, out_at = NULL, est_delivery_from = ?, est_delivery_to = ? WHERE order_id = ? AND status = 'Not Delivered'",
      [est.from, est.to, o.order_id]
    );
    if (r.affectedRows !== 1) throw conflict('NOT_NOT_DELIVERED', 'Cannot re-deliver', 'Only Not delivered orders can be re-delivered.');
    await addHistory(conn, o.order_id, 'Re-deliver', req.user.user_id, `Delivery ${deliveryText(est.from, est.to)}`, t);
    await notifyCustomer(conn, o, {
      type: 'Re-deliver',
      title: 'We will deliver again',
      message: `Your order is processing again. Estimated delivery: ${deliveryText(est.from, est.to)}.`,
    });
  });
  const fresh = await getOrder(o.order_id);
  res.json({ order: shapeOrder(fresh, await stationPoint()), message: 'Back to Processing.' });
});

// POST /api/admin/orders/:id/delivered { paid } and /not-delivered { note } (owner delivering, Admin Orders 6)
router.post('/:id/delivered', async (req, res) => {
  const o = await one('SELECT * FROM orders WHERE order_id = ?', [Number(req.params.id) || 0]);
  if (!o) throw notFound('ORDER_NOT_FOUND', 'Order not found', 'It may have been removed.');
  if (o.status !== 'Out for Delivery') throw conflict('NOT_OUT', 'Not out for delivery', 'Mark it Out for Delivery first.');
  const r = await transaction((conn) => recordDelivered(conn, o, req.user.user_id, (req.body || {}).paid !== false));
  res.json(r);
});

router.post('/:id/not-delivered', async (req, res) => {
  const o = await one('SELECT * FROM orders WHERE order_id = ?', [Number(req.params.id) || 0]);
  if (!o) throw notFound('ORDER_NOT_FOUND', 'Order not found', 'It may have been removed.');
  if (o.status !== 'Out for Delivery') throw conflict('NOT_OUT', 'Not out for delivery', 'Mark it Out for Delivery first.');
  const r = await transaction((conn) => recordNotDelivered(conn, o, req.user.user_id, text((req.body || {}).note, 200)));
  res.json(r);
});

// POST /api/admin/orders/:id/paid -> { order }  Only the owner changes Unpaid to Paid (FR-08).
router.post('/:id/paid', async (req, res) => {
  const o = await getOrder(req.params.id);
  const t = now();
  await transaction(async (conn) => {
    const [r] = await conn.query("UPDATE orders SET payment_status = 'Paid', paid_at = ? WHERE order_id = ? AND payment_status = 'Unpaid'", [t, o.order_id]);
    if (r.affectedRows !== 1) throw conflict('NOT_UNPAID', 'Already paid', 'This order is not unpaid.');
    await addHistory(conn, o.order_id, 'Marked paid', req.user.user_id, `P${Number(o.total_amount).toFixed(2)} received`, t);
  });
  const fresh = await getOrder(o.order_id);
  res.json({ order: shapeOrder(fresh, await stationPoint()), message: 'Marked paid.' });
});

module.exports = router;
