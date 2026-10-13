// Customer orders (FR-15; Customer 2-5): place an order (refill or package, cash on delivery),
// see the active order and its 5 status steps, cancel before it is accepted.
// Works for customer accounts and for guests (X-Guest-Token, Guest Mode in step 33).
const { Router } = require('express');
const { one, query, transaction } = require('../db');
const { optionalAuth } = require('../middleware/auth');
const { bad, unauthorized, forbidden, notFound, conflict } = require('../utils/errors');
const { int, normalizePhone, isPhone, text } = require('../utils/validate');
const { currentPrices } = require('../services/settings');
const { readAddress, shapeAddress } = require('../services/addresses');
const { now } = require('../services/time');
const {
  ACTIVE, shapeOrder, ORDER_SELECT, timeline, addHistory, notifyOwner, stationPoint,
} = require('../services/orders');

const router = Router();
router.use(optionalAuth);

const MAX_GALLONS = 50;

/** Who is ordering: a customer account or a guest phone. Staff, riders and the owner use Log Delivery Order. */
function who(req) {
  if (req.user) {
    if (req.user.role !== 'Customer') throw forbidden('CUSTOMERS_ONLY', 'Customers only', 'Use Log Delivery Order for call, text and Messenger orders.');
    return { sql: 'o.customer_id = ?', param: req.user.user_id };
  }
  if (req.guestToken) return { sql: 'o.customer_id IS NULL AND o.guest_token = ?', param: req.guestToken };
  throw unauthorized('LOGIN_REQUIRED', 'Please log in', 'Log in or continue as guest to order.');
}

/** Unpaid balance: delivered orders recorded as Unpaid (shown on the Order Form, never blocks ordering). */
async function unpaid(w) {
  const r = await one(`SELECT COALESCE(SUM(o.total_amount), 0) AS owed FROM orders o WHERE ${w.sql} AND o.payment_status = 'Unpaid'`, [w.param]);
  return Number(r.owed);
}

// GET /api/orders/home -> { active: [orders], prices, unpaid, stationPhone }  (Customer Home)
router.get('/home', async (req, res) => {
  const w = who(req);
  const station = await stationPoint();
  const rows = await query(`${ORDER_SELECT} WHERE ${w.sql} AND o.status IN (?) ORDER BY o.created_at DESC, o.order_id DESC`, [w.param, ACTIVE]);
  res.json({
    active: rows.map((o) => shapeOrder(o, station)),
    prices: await currentPrices(),
    unpaid: await unpaid(w),
    stationPhone: station.phone,
  });
});

// GET /api/orders -> { orders } (newest first; My Orders in step 32)
router.get('/', async (req, res) => {
  const w = who(req);
  const station = await stationPoint();
  const rows = await query(`${ORDER_SELECT} WHERE ${w.sql} ORDER BY o.created_at DESC, o.order_id DESC LIMIT 100`, [w.param]);
  res.json({ orders: rows.map((o) => shapeOrder(o, station)), unpaid: await unpaid(w) });
});

async function myOrder(req) {
  const w = who(req);
  const o = await one(`${ORDER_SELECT} WHERE o.order_id = ? AND ${w.sql}`, [Number(req.params.id) || 0, w.param]);
  if (!o) throw notFound('ORDER_NOT_FOUND', 'Order not found', 'It may belong to another account.');
  return o;
}

// GET /api/orders/:id -> { order, timeline, stationPhone }
router.get('/:id', async (req, res) => {
  const o = await myOrder(req);
  const station = await stationPoint();
  // Out for Delivery: the rider's last location for the live map (Customer 5, Customer 11).
  let rider = null;
  if (o.status === 'Out for Delivery' && o.rider_id) {
    const l = await one('SELECT latitude, longitude, updated_at, is_sharing FROM rider_locations WHERE rider_id = ?', [o.rider_id]);
    if (l && l.is_sharing) rider = { id: o.rider_id, lat: Number(l.latitude), lng: Number(l.longitude), updatedAt: l.updated_at };
  }
  res.json({ order: shapeOrder(o, station), timeline: await timeline(o.order_id), stationPhone: station.phone, rider, station: { lat: station.lat, lng: station.lng } });
});

// POST /api/orders { type: Refill|Package, quantity, address: {...} | addressId, phone, notes, name (guests) }
router.post('/', async (req, res) => {
  const w = who(req);
  const b = req.body || {};
  const type = b.type === 'Package' ? 'Package' : b.type === 'Refill' ? 'Refill' : null;
  if (!type) throw bad('TYPE_MISSING', 'Choose the order type', 'Refill my gallons or Buy a package.');
  const qty = int(b.quantity, 1, MAX_GALLONS);
  if (qty === null) throw bad('GALLONS_INVALID', 'Number of gallons not valid', `Order 1 to ${MAX_GALLONS} gallons.`, { field: 'quantity' });

  let a;
  if (b.addressId && req.user) {
    const r = await one('SELECT * FROM customer_addresses WHERE address_id = ? AND customer_id = ?', [Number(b.addressId) || 0, req.user.user_id]);
    if (!r) throw bad('ADDRESS_MISSING', 'Delivery address missing', 'Pin on map or type the address.', { field: 'address' });
    a = { ...shapeAddress(r), addressId: r.address_id };
  } else if (b.fromOrderId) {
    // Order again: same address as an earlier order of this customer.
    const w2 = who(req);
    const prev = await one(`SELECT * FROM orders o WHERE o.order_id = ? AND ${w2.sql}`, [Number(b.fromOrderId) || 0, w2.param]);
    if (!prev) throw bad('ADDRESS_MISSING', 'Delivery address missing', 'Pin on map or type the address.', { field: 'address' });
    a = {
      text: prev.delivery_address_text,
      landmark: prev.delivery_landmark,
      lat: prev.delivery_latitude === null ? null : Number(prev.delivery_latitude),
      lng: prev.delivery_longitude === null ? null : Number(prev.delivery_longitude),
      addressId: prev.address_id,
    };
  } else if (b.address && typeof b.address === 'object') {
    a = readAddress(b.address);
  } else {
    throw bad('ADDRESS_MISSING', 'Delivery address missing', 'Pin on map or type the address.', { field: 'address' });
  }

  const phone = normalizePhone(b.phone || (req.user && req.user.phone_number));
  if (!isPhone(phone)) throw bad('PHONE_INVALID', 'Phone number not valid', 'Use 11 digits, like 0917 200 1111.', { field: 'phone' });
  const name = req.user ? req.user.full_name : text(b.name, 100);
  if (!name) throw bad('NAME_MISSING', 'Name missing', 'Type your name so the rider knows who to look for.', { field: 'name' });

  const prices = await currentPrices();
  const unit = type === 'Package' ? prices.package : prices.delivery;
  const t = now();

  const id = await transaction(async (conn) => {
    const [r] = await conn.query(
      `INSERT INTO orders (order_source, order_type, customer_id, guest_token, customer_name, contact_phone, address_id,
         delivery_address_text, delivery_landmark, delivery_latitude, delivery_longitude, quantity, unit_price, total_amount,
         notes, status, payment_method, payment_status, created_at)
       VALUES ('App', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'New', 'COD', 'Pending', ?)`,
      [
        type,
        req.user ? req.user.user_id : null,
        req.user ? null : req.guestToken,
        name,
        phone,
        a.addressId || null,
        a.text,
        a.landmark || null,
        a.lat,
        a.lng,
        qty,
        unit,
        unit * qty,
        text(b.notes, 255) || null,
        t,
      ]
    );
    await addHistory(conn, r.insertId, 'Waiting for order to be accepted', req.user ? req.user.user_id : null, null, t);
    await notifyOwner(conn, {
      orderId: r.insertId,
      type: 'New Order',
      title: 'New order',
      message: `${name}: ${qty} ${qty === 1 ? 'gallon' : 'gallons'} · ${type}`,
    });
    return r.insertId;
  });

  const o = await one(`${ORDER_SELECT} WHERE o.order_id = ?`, [id]);
  res.status(201).json({
    order: shapeOrder(o, await stationPoint()),
    title: 'Thank you for your order!',
    message: 'Your order has been received. Please wait for the station to accept your order. Payment: cash on delivery, pay once delivered.',
  });
});

// POST /api/orders/:id/cancel -> { order } (only while waiting to be accepted)
router.post('/:id/cancel', async (req, res) => {
  const o = await myOrder(req);
  await transaction(async (conn) => {
    const [r] = await conn.query("UPDATE orders SET status = 'Cancelled' WHERE order_id = ? AND status = 'New'", [o.order_id]);
    if (r.affectedRows !== 1) {
      throw conflict('ALREADY_ACCEPTED', 'Cannot cancel', 'The station already accepted this order. Call the station.');
    }
    await addHistory(conn, o.order_id, 'Cancelled', req.user ? req.user.user_id : null, 'By customer');
    await notifyOwner(conn, {
      orderId: o.order_id,
      type: 'Cancelled',
      title: 'Order cancelled',
      message: `${o.customer_name || 'Guest'} cancelled ${o.quantity} ${o.quantity === 1 ? 'gallon' : 'gallons'} · ${o.order_type}`,
    });
  });
  const fresh = await one(`${ORDER_SELECT} WHERE o.order_id = ?`, [o.order_id]);
  res.json({ order: shapeOrder(fresh, await stationPoint()), message: 'Order cancelled; owner notified' });
});

module.exports = router;
