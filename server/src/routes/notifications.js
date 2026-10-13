// In-app alerts (FR-12; Admin More 4): new orders, orders logged by staff, cancelled and not
// delivered orders, tank at 60 and low stock for the owner; order updates for customers.
const { Router } = require('express');
const { one, query } = require('../db');
const { optionalAuth } = require('../middleware/auth');
const { unauthorized } = require('../utils/errors');

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

module.exports = router;
