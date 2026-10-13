// Work of the owner and staff (FR-03, FR-05, FR-06, FR-11): Log Walk-in, Log Delivery Order,
// To Do (tank counter + Processing), Mark Out for Delivery in batches, Done Today, and the owner's
// "Water tank refilled" reset.
const { Router } = require('express');
const { one, query, transaction } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad, conflict, notFound, forbidden } = require('../utils/errors');
const { int, text, normalizePhone, isPhone } = require('../utils/validate');
const { currentPrices } = require('../services/settings');
const { now, estimatedDelivery, deliveryText, todayStart, clock } = require('../services/time');
const { shapeOrder, ORDER_SELECT, timeline, addHistory, notifyOwner, notifyCustomer, stationPoint, firstName } = require('../services/orders');
const { countOrder, ownerId, openCycle } = require('../services/process');

const router = Router();
router.use(requireAuth, requireRole('Owner', 'Staff'));

const MAX = 100;
const CHANNELS = ['Call', 'Text', 'Messenger', 'Walk-in for delivery'];
const gal = (n) => `${n} ${n === 1 ? 'gallon' : 'gallons'}`;

async function tankState(conn) {
  const c = await openCycle(conn);
  return { count: c.gallons_count, limit: c.tank_limit, alert: c.gallons_count >= c.tank_limit };
}

// GET /api/work/tank -> { count, limit, alert }
router.get('/tank', async (req, res) => {
  const t = await transaction((conn) => tankState(conn));
  res.json(t);
});

// POST /api/work/tank/reset (owner only) -> { count: 0 } "Water tank refilled"
router.post('/tank/reset', async (req, res) => {
  if (req.user.role !== 'Owner') throw forbidden('OWNER_ONLY', 'Owner only', 'Tell the owner: water tank needs refilling.');
  const t = await transaction(async (conn) => {
    const c = await openCycle(conn);
    await conn.query('UPDATE tank_cycles SET ended_at = ?, reset_by = ? WHERE cycle_id = ?', [now(), req.user.user_id, c.cycle_id]);
    const [[s]] = await conn.query('SELECT tank_limit FROM station_settings WHERE setting_id = 1');
    await conn.query('INSERT INTO tank_cycles (gallons_count, tank_limit, started_at) VALUES (0, ?, ?)', [s.tank_limit, now()]);
    return tankState(conn);
  });
  res.json({ ...t, message: 'Counter = 0; alert cleared' });
});

// POST /api/work/walk-in { quantity, type: Refill|Package, paid: true|false, name } -> 201
// Walk-in pick-up: P30 per gallon (P150 package), a sale record only (no status steps).
router.post('/walk-in', async (req, res) => {
  const b = req.body || {};
  const qty = int(b.quantity, 1, MAX);
  if (qty === null) throw bad('QTY_MISSING', 'Quantity missing', 'Tap + to add gallons.', { field: 'quantity' });
  const type = b.type === 'Package' ? 'Package' : 'Refill';
  const paid = b.paid !== false;
  const name = text(b.name, 100) || null;
  const prices = await currentPrices();
  const unit = type === 'Package' ? prices.package : prices.walkIn;
  const t = now();
  const result = await transaction(async (conn) => {
    const [r] = await conn.query(
      `INSERT INTO orders (order_source, order_type, created_by, customer_name, quantity, unit_price, total_amount, status,
         payment_method, payment_status, paid_at, accepted_by, accepted_at, delivered_at, created_at)
       VALUES ('Walk-in', ?, ?, ?, ?, ?, ?, 'Recorded', 'Walk-in', ?, ?, ?, ?, ?, ?)`,
      [type, req.user.user_id, name, qty, unit, unit * qty, paid ? 'Paid' : 'Unpaid', paid ? t : null, req.user.user_id, t, t, t]
    );
    await addHistory(conn, r.insertId, 'Walk-in saved', req.user.user_id, paid ? 'Paid' : 'Unpaid', t);
    const [[o]] = await conn.query('SELECT * FROM orders WHERE order_id = ?', [r.insertId]);
    const count = await countOrder(conn, o, { userId: req.user.user_id, why: 'Walk-in saved', at: t });
    return { id: r.insertId, count };
  });
  res.status(201).json({
    id: result.id,
    total: unit * qty,
    tank: result.count,
    message: `Walk-in saved: ${gal(qty)}, ${paid ? 'Paid' : 'Unpaid'}`,
  });
});

// POST /api/work/delivery { name, phone, address, quantity, type, channel, payment: 'Pay on delivery'|'Paid at station' }
// Logged delivery orders (call, text, Messenger, walk-in for delivery) go straight to Processing with the owner as rider.
router.post('/delivery', async (req, res) => {
  const b = req.body || {};
  const name = text(b.name, 100);
  const phone = normalizePhone(b.phone);
  const address = text(b.address, 255);
  const qty = int(b.quantity, 1, MAX);
  if (!name || !b.phone || !address || qty === null) {
    const missing = [!name && 'name', !b.phone && 'phone', !address && 'address', qty === null && 'quantity'].filter(Boolean);
    throw bad('FIELDS_MISSING', 'Name, phone, address or quantity missing', 'Fill in the marked fields.', { fields: missing });
  }
  if (!isPhone(phone)) throw bad('PHONE_INVALID', 'Phone number not valid', 'Use 11 digits, like 0918 555 2211.', { fields: ['phone'] });
  const channel = CHANNELS.includes(b.channel) ? b.channel : b.channel === 'Walk-in' ? 'Walk-in for delivery' : null;
  if (!channel) throw bad('CHANNEL_MISSING', 'Choose how the order was received', 'Call, Text, Messenger or Walk-in.');
  const paidAtStation = b.payment === 'Paid at station';
  const type = b.type === 'Package' ? 'Package' : 'Refill';
  const prices = await currentPrices();
  const unit = type === 'Package' ? prices.package : prices.delivery;
  const t = now();
  const est = estimatedDelivery(t);

  const id = await transaction(async (conn) => {
    const rider = await ownerId(conn);
    const [r] = await conn.query(
      `INSERT INTO orders (order_source, logged_channel, order_type, created_by, customer_name, contact_phone, delivery_address_text,
         quantity, unit_price, total_amount, notes, status, payment_method, payment_status, paid_at, rider_id, accepted_by, accepted_at,
         est_delivery_from, est_delivery_to, created_at)
       VALUES ('Logged', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Processing', ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        channel, type, req.user.user_id, name, phone, address, qty, unit, unit * qty, text(b.notes, 255) || null,
        paidAtStation ? 'Paid at station' : 'Pay on delivery', paidAtStation ? 'Paid' : 'Pending', paidAtStation ? t : null,
        rider, req.user.user_id, t, est.from, est.to, t,
      ]
    );
    await addHistory(conn, r.insertId, 'Order logged', req.user.user_id, `${channel} · Rider: Owner`, t);
    await addHistory(conn, r.insertId, 'Processing', req.user.user_id, `Delivery ${deliveryText(est.from, est.to)}`, t);
    if (req.user.role === 'Staff') {
      await notifyOwner(conn, {
        orderId: r.insertId,
        type: 'Logged Order',
        title: 'Order logged by staff',
        message: `${firstName(req.user.full_name)}: ${name}, ${gal(qty)} · ${channel}`,
      });
    }
    return r.insertId;
  });
  const o = await one(`${ORDER_SELECT} WHERE o.order_id = ?`, [id]);
  res.status(201).json({ order: shapeOrder(o, await stationPoint()), message: 'Order saved' });
});

// GET /api/work/todo -> { tank, processing: [orders], owner }
router.get('/todo', async (req, res) => {
  const station = await stationPoint();
  const rows = await query(`${ORDER_SELECT} WHERE o.status = 'Processing' ORDER BY o.est_delivery_to, o.order_id`);
  const tank = await transaction((conn) => tankState(conn));
  res.json({ tank, processing: rows.map((o) => shapeOrder(o, station)), owner: req.user.role === 'Owner' });
});

// POST /api/work/out { ids } -> { batches, message }
// One rider per batch (one sidecar): orders with different riders go out as separate batches.
router.post('/out', async (req, res) => {
  const ids = [...new Set(((req.body || {}).ids || []).map(Number).filter((n) => Number.isInteger(n) && n > 0))];
  if (!ids.length) throw bad('NONE_SELECTED', 'No orders selected', 'Tick at least one order in Processing.');
  const t = now();
  const batches = await transaction(async (conn) => {
    const [rows] = await conn.query(
      `SELECT o.*, u.full_name AS rider_name, u.role AS rider_role FROM orders o LEFT JOIN users u ON u.user_id = o.rider_id
       WHERE o.order_id IN (?) AND o.status = 'Processing' FOR UPDATE`,
      [ids]
    );
    if (rows.length !== ids.length) throw conflict('ALREADY_HANDLED', 'Some orders changed', 'An order is no longer in Processing. The list is refreshed.');
    const groups = new Map();
    for (const o of rows) {
      const rider = o.rider_id || (await ownerId(conn));
      if (!groups.has(rider)) groups.set(rider, []);
      groups.get(rider).push(o);
    }
    const out = [];
    for (const [rider, list] of groups) {
      const [b] = await conn.query('INSERT INTO delivery_batches (rider_id, sent_by, sent_at) VALUES (?, ?, ?)', [rider, req.user.user_id, t]);
      const riderLabel = list[0].rider_role === 'Owner' || !list[0].rider_name ? 'Owner' : firstName(list[0].rider_name);
      for (const o of list) {
        await conn.query("UPDATE orders SET status = 'Out for Delivery', rider_id = ?, batch_id = ?, out_at = ? WHERE order_id = ?", [
          rider, b.insertId, t, o.order_id,
        ]);
        await addHistory(conn, o.order_id, 'Out for delivery', req.user.user_id, `Rider: ${riderLabel}`, t);
        await countOrder(conn, o, { userId: req.user.user_id, why: 'Order sent out for delivery', at: t });
        await notifyCustomer(conn, o, {
          type: 'Out for Delivery',
          title: 'Out for delivery',
          message: list.length > 1 ? 'Your rider is handling multiple orders.' : 'Your rider is on the way.',
        });
      }
      out.push({ batchId: b.insertId, rider: riderLabel, orders: list.map((o) => o.order_id) });
    }
    return out;
  });
  const n = ids.length;
  res.json({
    batches,
    message: n === 1 ? 'Out for delivery. Customer notified.' : `${n} orders out for delivery`,
  });
});

// GET /api/work/done-today -> { gallons, items: [{ id, name, quantity, what, at }] }
// Gallons processed today (counted today) and orders logged or sent out today, newest first.
router.get('/done-today', async (req, res) => {
  const start = todayStart();
  const g = await one('SELECT COALESCE(SUM(quantity), 0) AS n FROM orders WHERE tank_counted_at >= ?', [start]);
  const rows = await query(
    `SELECT h.status, h.changed_at, o.order_id, o.order_source, o.customer_name, o.quantity, o.order_type
     FROM order_status_history h JOIN orders o ON o.order_id = h.order_id
     WHERE h.changed_at >= ? AND h.status IN ('Walk-in saved', 'Order logged', 'Out for delivery')
     ORDER BY h.changed_at DESC, h.history_id DESC LIMIT 200`,
    [start]
  );
  const what = { 'Walk-in saved': 'Walk-in saved', 'Order logged': 'Delivery logged', 'Out for delivery': 'Sent out' };
  res.json({
    gallons: Number(g.n),
    items: rows.map((r) => ({
      id: r.order_id,
      name: r.order_source === 'Walk-in' ? `Walk-in${r.customer_name ? `: ${r.customer_name}` : ''}` : r.customer_name || 'Guest',
      quantity: r.quantity,
      type: r.order_type,
      what: what[r.status],
      at: r.changed_at,
      clock: clock(r.changed_at),
    })),
  });
});

// GET /api/work/orders/:id -> { order, timeline } (view only for staff)
router.get('/orders/:id', async (req, res) => {
  const o = await one(`${ORDER_SELECT} WHERE o.order_id = ?`, [Number(req.params.id) || 0]);
  if (!o) throw notFound('ORDER_NOT_FOUND', 'Order not found', 'It may have been removed.');
  res.json({ order: shapeOrder(o, await stationPoint()), timeline: await timeline(o.order_id) });
});

module.exports = router;
