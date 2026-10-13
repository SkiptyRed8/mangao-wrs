// Owner's Home (FR-16, FR-10; Admin Home 1-4, 6, 7): tank counter, Switch View counts, Needs Your
// Action, Today's Summary tiles and Stock Alerts.
const { Router } = require('express');
const { one, query, transaction } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { now } = require('../services/time');
const { openCycle } = require('../services/process');
const { dayRange, daySummary } = require('../services/reports');

const router = Router();
router.use(requireAuth, requireRole('Owner'));

async function stockAlerts() {
  const items = await query('SELECT item_name, quantity_on_hand, low_stock_level FROM inventory_items');
  return items.map((i) => ({
    item: i.item_name === 'Seal' ? 'seals' : 'gallons',
    label: i.item_name === 'Seal' ? 'Seals' : 'Gallons',
    quantity: i.quantity_on_hand,
    level: i.low_stock_level,
    low: i.quantity_on_hand <= i.low_stock_level,
  }));
}

// GET /api/admin/home
router.get('/', async (req, res) => {
  const c = await transaction((conn) => openCycle(conn));
  const k = await one(
    `SELECT SUM(status = 'New') AS c_new, SUM(status = 'Processing') AS c_proc, SUM(status = 'Out for Delivery') AS c_out,
       SUM(status = 'Not Delivered') AS c_nd FROM orders`
  );
  const n = (v) => Number(v || 0);
  const [start, end] = dayRange(now());
  const day = await daySummary(start, end);
  const unread = await one('SELECT COUNT(*) AS c FROM notifications WHERE user_id = ? AND is_read = 0', [req.user.user_id]);
  res.json({
    tank: { count: c.gallons_count, limit: c.tank_limit, alert: c.gallons_count >= c.tank_limit },
    counts: { new: n(k.c_new), processing: n(k.c_proc), out: n(k.c_out), notDelivered: n(k.c_nd) },
    today: day,
    stock: await stockAlerts(),
    unread: n(unread.c),
  });
});

module.exports = router;
module.exports.stockAlerts = stockAlerts;
