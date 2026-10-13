// Rider (and the owner in the Delivery view): Out for Delivery list, Delivered (Paid / Unpaid, or
// already paid at the station), Not delivered with an optional note, Done Today (FR-05, FR-08).
const { Router } = require('express');
const { one, query, transaction } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad, notFound, conflict } = require('../utils/errors');
const { text } = require('../utils/validate');
const { todayStart, clock, now } = require('../services/time');
const realtime = require('../services/realtime');
const { shapeOrder, ORDER_SELECT, stationPoint } = require('../services/orders');
const { recordDelivered, recordNotDelivered } = require('../services/process');

const router = Router();
router.use(requireAuth, requireRole('Rider', 'Owner'));

// GET /api/rider/deliveries -> { orders, sentAt, sharing }
router.get('/deliveries', async (req, res) => {
  const station = await stationPoint();
  const rows = await query(
    `${ORDER_SELECT} WHERE o.status = 'Out for Delivery' AND o.rider_id = ? ORDER BY o.out_at, o.order_id`,
    [req.user.user_id]
  );
  const first = rows.length ? rows.reduce((a, o) => (o.out_at < a ? o.out_at : a), rows[0].out_at) : null;
  res.json({ orders: rows.map((o) => shapeOrder(o, station)), sentAt: first, sentClock: first ? clock(first) : '', sharing: rows.length > 0 });
});

async function myOut(req) {
  const o = await one('SELECT * FROM orders WHERE order_id = ?', [Number(req.params.id) || 0]);
  if (!o) throw notFound('ORDER_NOT_FOUND', 'Order not found', 'It may have been removed.');
  const mine = o.rider_id === req.user.user_id || req.user.role === 'Owner';
  if (!mine) throw notFound('ORDER_NOT_FOUND', 'Order not found', 'This order is in another rider\'s batch.');
  if (o.status !== 'Out for Delivery') throw conflict('NOT_OUT', 'Already recorded', `This order is ${o.status.toLowerCase()}.`);
  return o;
}

// POST /api/rider/orders/:id/delivered { paid: true|false } -> { message }
router.post('/orders/:id/delivered', async (req, res) => {
  const o = await myOut(req);
  const r = await transaction((conn) => recordDelivered(conn, o, req.user.user_id, (req.body || {}).paid !== false));
  res.json(r);
});

// POST /api/rider/orders/:id/not-delivered { note } -> { message }
router.post('/orders/:id/not-delivered', async (req, res) => {
  const o = await myOut(req);
  const r = await transaction((conn) => recordNotDelivered(conn, o, req.user.user_id, text((req.body || {}).note, 200)));
  res.json(r);
});

// POST /api/rider/location { lat, lng } -> { sharing }
// The rider's phone sends its location every few seconds while orders are out (Rider 5). Sharing
// turns on by itself at Out for Delivery and off after the last order of the batch.
router.post('/location', async (req, res) => {
  const lat = Number((req.body || {}).lat);
  const lng = Number((req.body || {}).lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    throw bad('LOCATION_INVALID', 'Location not valid', 'Turn on location and try again.');
  }
  const out = await one(
    "SELECT batch_id FROM orders WHERE rider_id = ? AND status = 'Out for Delivery' ORDER BY out_at DESC LIMIT 1",
    [req.user.user_id]
  );
  if (!out) {
    await query('UPDATE rider_locations SET is_sharing = 0 WHERE rider_id = ?', [req.user.user_id]);
    return res.json({ sharing: false });
  }
  const t = now();
  await query(
    `INSERT INTO rider_locations (rider_id, batch_id, latitude, longitude, is_sharing, updated_at) VALUES (?, ?, ?, ?, 1, ?)
     ON DUPLICATE KEY UPDATE batch_id = VALUES(batch_id), latitude = VALUES(latitude), longitude = VALUES(longitude), is_sharing = 1, updated_at = VALUES(updated_at)`,
    [req.user.user_id, out.batch_id, lat.toFixed(7), lng.toFixed(7), t]
  );
  await realtime.location(req.user.user_id, { lat, lng, at: t, sharing: true });
  res.json({ sharing: true });
});

// GET /api/rider/done-today -> { delivered, paidAmount, unpaidCount, orders }
router.get('/done-today', async (req, res) => {
  const station = await stationPoint();
  const rows = await query(
    `${ORDER_SELECT} WHERE o.status = 'Delivered' AND o.rider_id = ? AND o.delivered_at >= ? ORDER BY o.delivered_at DESC`,
    [req.user.user_id, todayStart()]
  );
  const orders = rows.map((o) => shapeOrder(o, station));
  const collected = rows.filter((o) => o.payment_status === 'Paid' && o.payment_method !== 'Paid at station');
  res.json({
    delivered: orders.length,
    paidAmount: collected.reduce((s, o) => s + Number(o.total_amount), 0),
    unpaidCount: rows.filter((o) => o.payment_status === 'Unpaid').length,
    orders,
  });
});

// GET /api/rider/orders/:id -> { order } (view only)
router.get('/orders/:id', async (req, res) => {
  const o = await one(`${ORDER_SELECT} WHERE o.order_id = ? AND (o.rider_id = ? OR ? = 'Owner')`, [Number(req.params.id) || 0, req.user.user_id, req.user.role]);
  if (!o) throw notFound('ORDER_NOT_FOUND', 'Order not found', 'It may belong to another rider.');
  res.json({ order: shapeOrder(o, await stationPoint()) });
});

module.exports = router;
