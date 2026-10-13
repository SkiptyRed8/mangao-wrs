// Station work for the owner and staff (FR-03, FR-05): Log Walk-in (pick-up, record only),
// Log Delivery Order (call, text, Messenger, walk-in for delivery), and later steps add
// Mark Out for Delivery and the staff lists.
const { Router } = require('express');
const { one, transaction } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad } = require('../utils/errors');
const { int, normalizePhone, isPhone, text } = require('../utils/validate');
const { currentPrices } = require('../services/settings');
const { now, estimatedDelivery, deliveryText } = require('../services/time');
const { addHistory, notifyOwner, shapeOrder, ORDER_SELECT, stationPoint } = require('../services/orders');
const { countOrder } = require('../services/stock');

const router = Router();
router.use(requireAuth, requireRole('Owner', 'Staff'));

const MAX = 100;
const gallonsText = (n) => `${n} ${n === 1 ? 'gallon' : 'gallons'}`;
const CHANNELS = { Call: 'Call', Text: 'Text', Messenger: 'Messenger', 'Walk-in': 'Walk-in for delivery', 'Walk-in for delivery': 'Walk-in for delivery' };

function readType(v) {
  return v === 'Package' ? 'Package' : 'Refill';
}

// POST /api/station/walk-in { quantity, type: Refill|Package, paid: true|false, name? } -> 201 { order, message }
// A record only (no status steps). Counts in the tank counter and uses seals right away.
router.post('/walk-in', async (req, res) => {
  const b = req.body || {};
  const qty = int(b.quantity, 1, MAX);
  if (qty === null) throw bad('QUANTITY_MISSING', 'Quantity missing', `Type 1 to ${MAX} gallons.`, { field: 'quantity' });
  if (typeof b.paid !== 'boolean') throw bad('PAYMENT_MISSING', 'Paid or unpaid?', 'Choose Paid or Unpaid.', { field: 'paid' });
  const type = readType(b.type);
  const prices = await currentPrices();
  const unit = type === 'Package' ? prices.package : prices.walkIn;
  const t = now();
  const name = text(b.name, 100) || 'Walk-in customer';

  const id = await transaction(async (conn) => {
    const [r] = await conn.query(
      `INSERT INTO orders (order_source, order_type, created_by, customer_name, quantity, unit_price, total_amount,
         status, payment_method, payment_status, paid_at, delivered_at, created_at)
       VALUES ('Walk-in', ?, ?, ?, ?, ?, ?, 'Recorded', 'Walk-in', ?, ?, ?, ?)`,
      [type, req.user.user_id, name, qty, unit, unit * qty, b.paid ? 'Paid' : 'Unpaid', b.paid ? t : null, t, t]
    );
    await addHistory(conn, r.insertId, 'Walk-in saved', req.user.user_id, b.paid ? 'Paid' : 'Unpaid', t);
    const [[o]] = await conn.query('SELECT * FROM orders WHERE order_id = ?', [r.insertId]);
    await countOrder(conn, o, req.user.user_id);
    return r.insertId;
  });
  const o = await one(`${ORDER_SELECT} WHERE o.order_id = ?`, [id]);
  res.status(201).json({ order: shapeOrder(o), message: `Walk-in saved: ${gallonsText(qty)}, ${b.paid ? 'Paid' : 'Unpaid'}` });
});

// POST /api/station/delivery { name, phone, address, quantity, type, channel, payment } -> 201 { order, message }
// Goes straight to Processing with the owner as rider; the delivery time is set now.
router.post('/delivery', async (req, res) => {
  const b = req.body || {};
  const name = text(b.name, 100);
  const address = text(b.address, 255);
  const qty = int(b.quantity, 1, MAX);
  const rawPhone = text(b.phone, 20);
  if (!name || !rawPhone || !address || qty === null) {
    const missing = [!name && 'name', !rawPhone && 'phone', !address && 'address', qty === null && 'quantity'].filter(Boolean);
    throw bad('FIELDS_MISSING', 'Name, phone, address or quantity missing', 'Fill in the highlighted fields.', { fields: missing });
  }
  const phone = normalizePhone(rawPhone);
  if (!isPhone(phone)) throw bad('PHONE_INVALID', 'Phone number not valid', 'Use 11 digits, like 0918 555 2211.', { fields: ['phone'] });
  const channel = CHANNELS[b.channel];
  if (!channel) throw bad('CHANNEL_MISSING', 'Order received by?', 'Choose Call, Text, Messenger or Walk-in.', { fields: ['channel'] });
  if (!['Pay on delivery', 'Paid at station'].includes(b.payment)) {
    throw bad('PAYMENT_MISSING', 'Payment missing', 'Choose Pay on delivery or Paid at station.', { fields: ['payment'] });
  }
  const type = readType(b.type);
  const prices = await currentPrices();
  const unit = type === 'Package' ? prices.package : prices.delivery;
  const owner = await one("SELECT user_id FROM users WHERE role = 'Owner' ORDER BY user_id LIMIT 1");
  const t = now();
  const est = estimatedDelivery(t);
  const when = deliveryText(est.from, est.to);
  const paid = b.payment === 'Paid at station';

  const id = await transaction(async (conn) => {
    const [r] = await conn.query(
      `INSERT INTO orders (order_source, logged_channel, order_type, created_by, customer_name, contact_phone, delivery_address_text,
         quantity, unit_price, total_amount, notes, status, payment_method, payment_status, paid_at, rider_id, accepted_by, accepted_at,
         est_delivery_from, est_delivery_to, created_at)
       VALUES ('Logged', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Processing', ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        channel, type, req.user.user_id, name, phone, address, qty, unit, unit * qty, text(b.notes, 255) || null,
        b.payment, paid ? 'Paid' : 'Pending', paid ? t : null, owner.user_id, req.user.user_id, t, est.from, est.to, t,
      ]
    );
    await addHistory(conn, r.insertId, 'Order logged', req.user.user_id, `${channel} · Rider: Owner`, t);
    await addHistory(conn, r.insertId, 'Processing', req.user.user_id, `Delivery ${when}`, t);
    if (req.user.role === 'Staff') {
      await notifyOwner(conn, {
        orderId: r.insertId,
        type: 'Logged Order',
        title: 'Order logged by staff',
        message: `${req.user.full_name.split(' ')[0]} logged ${name}: ${gallonsText(qty)} · ${channel}`,
      });
    }
    return r.insertId;
  });
  const o = await one(`${ORDER_SELECT} WHERE o.order_id = ?`, [id]);
  res.status(201).json({ order: shapeOrder(o, await stationPoint()), message: 'Order saved', estText: when });
});

module.exports = router;
