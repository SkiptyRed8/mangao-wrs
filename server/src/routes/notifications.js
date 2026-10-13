// In-app alerts (FR-12; Admin More 4): new orders, orders logged by staff, cancelled and not
// delivered orders, tank at 60 and low stock for the owner; order updates for customers.
const { Router } = require('express');
const { one, query } = require('../db');
const { optionalAuth } = require('../middleware/auth');
const { unauthorized, forbidden, bad } = require('../utils/errors');

const router = Router();
router.use(optionalAuth);

function who(req) {
  if (req.user) return ['n.user_id = ?', req.user.user_id];
  if (req.guestToken) return ['n.guest_token = ?', req.guestToken];
  throw unauthorized('LOGIN_REQUIRED', 'Please log in', 'Log in to see notifications.');
}

// GET /api/notifications -> { items, unread }
router.get('/', async (req, res) => {
  const [w, p] = who(req);
  const rows = await query(`SELECT n.* FROM notifications n WHERE ${w} ORDER BY n.created_at DESC, n.notification_id DESC LIMIT 100`, [p]);
  const u = await one(`SELECT COUNT(*) AS c FROM notifications n WHERE ${w} AND n.is_read = 0`, [p]);
  res.json({
    unread: Number(u.c),
    items: rows.map((r) => ({
      id: r.notification_id,
      type: r.notification_type,
      title: r.title,
      message: r.message,
      orderId: r.order_id,
      read: !!r.is_read,
      at: r.created_at,
    })),
  });
});

// GET /api/notifications/unread -> { unread } (bell badge)
router.get('/unread', async (req, res) => {
  const [w, p] = who(req);
  const u = await one(`SELECT COUNT(*) AS c FROM notifications n WHERE ${w} AND n.is_read = 0`, [p]);
  res.json({ unread: Number(u.c) });
});

// POST /api/notifications/read { id } or { all: true }
router.post('/read', async (req, res) => {
  const [w, p] = who(req);
  const b = req.body || {};
  if (b.all) await query(`UPDATE notifications n SET n.is_read = 1 WHERE ${w}`, [p]);
  else await query(`UPDATE notifications n SET n.is_read = 1 WHERE ${w} AND n.notification_id = ?`, [p, Number(b.id) || 0]);
  res.json({ ok: true });
});

// ---------------------------------------------------------------- Preferences (owner) and phones (push)

/** Alerts the owner can turn on or off (Admin More 4: Preferences). */
const ALERT_TYPES = [
  ['New Order', 'New orders'],
  ['Logged Order', 'Orders logged by staff'],
  ['Cancelled', 'Cancelled orders'],
  ['Not Delivered', 'Not delivered'],
  ['Tank', 'Tank at 60'],
  ['Low Stock', 'Low stock'],
  ['Damaged Gallon', 'Damaged gallon'],
];

// GET /api/notifications/preferences -> { items: [{ type, label, enabled }], push }
router.get('/preferences', async (req, res) => {
  if (!req.user || req.user.role !== 'Owner') throw forbidden('OWNER_ONLY', 'Owner only', 'Only the owner chooses alerts.');
  const rows = await query('SELECT notification_type, is_enabled FROM notification_preferences WHERE user_id = ?', [req.user.user_id]);
  const off = new Set(rows.filter((r) => !r.is_enabled).map((r) => r.notification_type));
  res.json({ items: ALERT_TYPES.map(([type, label]) => ({ type, label, enabled: !off.has(type) })), push: require('../services/push').enabled() });
});

// PUT /api/notifications/preferences { type, enabled } -> { message }
router.put('/preferences', async (req, res) => {
  if (!req.user || req.user.role !== 'Owner') throw forbidden('OWNER_ONLY', 'Owner only', 'Only the owner chooses alerts.');
  const b = req.body || {};
  if (!ALERT_TYPES.some(([t]) => t === b.type)) throw bad('TYPE_UNKNOWN', 'Unknown alert', 'Pick one from the list.');
  await query(
    'INSERT INTO notification_preferences (user_id, notification_type, is_enabled) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE is_enabled = VALUES(is_enabled)',
    [req.user.user_id, b.type, b.enabled === false ? 0 : 1]
  );
  res.json({ message: 'Saved. Takes effect right away.' });
});

// POST /api/notifications/device { token, platform } -> { ok }  (the phone's Firebase token, for push)
router.post('/device', async (req, res) => {
  const [, p] = who(req);
  const token = String((req.body || {}).token || '').trim();
  if (token.length < 20 || token.length > 255) throw bad('TOKEN_INVALID', 'Push not set up', 'The phone did not give a push token.');
  const platform = ['android', 'web'].includes((req.body || {}).platform) ? req.body.platform : 'android';
  await query(
    `INSERT INTO device_tokens (user_id, guest_token, push_token, platform) VALUES (?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), guest_token = VALUES(guest_token), platform = VALUES(platform)`,
    [req.user ? p : null, req.user ? null : p, token, platform]
  );
  res.json({ ok: true });
});

// DELETE /api/notifications/device { token } (log out: no more push to this phone)
router.delete('/device', async (req, res) => {
  await query('DELETE FROM device_tokens WHERE push_token = ?', [String((req.body || {}).token || '')]);
  res.json({ ok: true });
});

module.exports = router;
module.exports.ALERT_TYPES = ALERT_TYPES;
