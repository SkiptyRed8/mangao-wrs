// Shared order helpers: how an order is sent to the app, the status timeline,
// distance from the station, and history / notification rows.
const { query, one } = require('../db');
const { now, clock, deliveryText } = require('./time');

const ACTIVE = ['New', 'Processing', 'Out for Delivery'];

/** Kilometres between two points (straight line). */
function distanceKm(lat1, lng1, lat2, lng2) {
  if ([lat1, lng1, lat2, lng2].some((v) => v === null || v === undefined)) return null;
  const R = 6371;
  const rad = (x) => (Number(x) * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(a)) * 10) / 10;
}

/** "12 Sampaguita St., Blk 2 Lot 5, Commonwealth" (typed) or "Pinned: near ..." (pin only). */
function addressText(a) {
  const first = [a.house, a.street].filter(Boolean).join(' ');
  const parts = [first, a.blockLot, a.barangay].filter((x) => x && String(x).trim());
  if (a.pinned && !a.house) return `Pinned: near ${parts.join(', ') || 'the map pin'}`;
  return parts.join(', ');
}

const firstName = (n) => String(n || '').split(' ')[0];

/** Who did a step, as the timeline shows it: "Owner", "Ana (Staff)", "Juan", "Maria". */
function actor(row) {
  if (!row.actor_role) return row.order_customer ? firstName(row.order_customer) : 'Guest';
  if (row.actor_role === 'Owner') return 'Owner';
  if (row.actor_role === 'Staff') return `${firstName(row.actor_name)} (Staff)`;
  return firstName(row.actor_name);
}

async function timeline(orderId) {
  const rows = await query(
    `SELECT h.status, h.note, h.changed_at, u.full_name AS actor_name, u.role AS actor_role, o.customer_name AS order_customer
     FROM order_status_history h
     JOIN orders o ON o.order_id = h.order_id
     LEFT JOIN users u ON u.user_id = h.changed_by
     WHERE h.order_id = ? ORDER BY h.changed_at, h.history_id`,
    [orderId]
  );
  return rows.map((r) => ({ status: r.status, note: r.note || '', at: r.changed_at, by: actor(r) }));
}

/** Adds a timeline step. */
async function addHistory(conn, orderId, status, userId, note = null, at = now()) {
  await conn.query('INSERT INTO order_status_history (order_id, status, changed_by, note, changed_at) VALUES (?, ?, ?, ?, ?)', [
    orderId,
    status,
    userId || null,
    note,
    at,
  ]);
  require('./realtime').orderChanged(orderId);
}

/** In-app notification for one account (or a guest phone). Shown by the bell and pushed in step 36. */
async function notify(conn, { userId = null, guestToken = null, orderId = null, type, title, message }) {
  if (!userId && !guestToken) return;
  await conn.query(
    'INSERT INTO notifications (user_id, guest_token, order_id, notification_type, title, message) VALUES (?, ?, ?, ?, ?, ?)',
    [userId, guestToken, orderId, type, title, message]
  );
  require('./realtime').notification({ userId, guestToken, title, message, type, orderId });
  require('./push').send({ userId, guestToken, title, message, type, orderId });
}

/** Notifies the owner (all Owner accounts), unless the owner turned that alert off in Preferences. */
async function notifyOwner(conn, n) {
  const [owners] = await conn.query(
    `SELECT u.user_id FROM users u
     LEFT JOIN notification_preferences p ON p.user_id = u.user_id AND p.notification_type = ?
     WHERE u.role = 'Owner' AND u.is_active = 1 AND COALESCE(p.is_enabled, 1) = 1`,
    [n.type]
  );
  for (const o of owners) await notify(conn, { ...n, userId: o.user_id });
}

/** Notifies the customer of an order (account or guest phone). */
async function notifyCustomer(conn, order, n) {
  await notify(conn, { ...n, userId: order.customer_id, guestToken: order.customer_id ? null : order.guest_token, orderId: order.order_id });
}

const SOURCE = (o) => (o.order_source === 'Logged' ? o.logged_channel || 'Logged' : o.order_source);

const PAYMENT_TEXT = {
  COD: 'Cash on delivery',
  'Pay on delivery': 'Pay on delivery',
  'Paid at station': 'Paid at station',
  'Walk-in': 'Walk-in',
};

/** The order as the app sees it. station = { lat, lng } for the distance. */
function shapeOrder(o, station) {
  const km = station ? distanceKm(station.lat, station.lng, o.delivery_latitude, o.delivery_longitude) : null;
  return {
    id: o.order_id,
    source: o.order_source,
    channel: o.logged_channel,
    sourceText: SOURCE(o),
    type: o.order_type,
    quantity: o.quantity,
    unitPrice: Number(o.unit_price),
    total: Number(o.total_amount),
    customerId: o.customer_id,
    name: o.customer_name || '',
    phone: o.contact_phone || '',
    address: o.delivery_address_text || '',
    landmark: o.delivery_landmark || '',
    lat: o.delivery_latitude === null ? null : Number(o.delivery_latitude),
    lng: o.delivery_longitude === null ? null : Number(o.delivery_longitude),
    km,
    notes: o.notes || '',
    status: o.status,
    payment: o.payment_method,
    paymentText: PAYMENT_TEXT[o.payment_method] || o.payment_method,
    paymentStatus: o.payment_status,
    riderId: o.rider_id,
    riderName: o.rider_name || null,
    riderRole: o.rider_role || null,
    batchId: o.batch_id,
    batchSize: o.batch_size || null,
    acceptedAt: o.accepted_at,
    estFrom: o.est_delivery_from,
    estTo: o.est_delivery_to,
    estText: deliveryText(o.est_delivery_from, o.est_delivery_to),
    outAt: o.out_at,
    deliveredAt: o.delivered_at,
    deliveredClock: o.delivered_at ? clock(o.delivered_at) : '',
    createdAt: o.created_at,
    reason: o.reason || '',
  };
}

/** SELECT used by every order list: the order, its rider, batch size and last decline / not-delivered note. */
const ORDER_SELECT = `
  SELECT o.*, r.full_name AS rider_name, r.role AS rider_role,
    (SELECT COUNT(*) FROM orders b WHERE o.batch_id IS NOT NULL AND b.batch_id = o.batch_id) AS batch_size,
    (SELECT h.note FROM order_status_history h WHERE h.order_id = o.order_id
       AND h.status IN ('Declined','Not delivered','Cancelled') ORDER BY h.history_id DESC LIMIT 1) AS reason
  FROM orders o LEFT JOIN users r ON r.user_id = o.rider_id`;

async function stationPoint() {
  const s = await one('SELECT station_latitude AS lat, station_longitude AS lng, station_phone AS phone FROM station_settings WHERE setting_id = 1');
  return { lat: s.lat === null ? null : Number(s.lat), lng: s.lng === null ? null : Number(s.lng), phone: s.phone || '' };
}

module.exports = {
  ACTIVE,
  distanceKm,
  addressText,
  timeline,
  addHistory,
  notify,
  notifyOwner,
  notifyCustomer,
  shapeOrder,
  ORDER_SELECT,
  stationPoint,
  firstName,
};
