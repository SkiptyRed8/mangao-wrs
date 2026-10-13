// Daily Sales Report (FR-10; Admin Sales 1). The weekly report and export come in Sprint 3.
const { Router } = require('express');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad } = require('../utils/errors');
const { now, phParts } = require('../services/time');
const { dayRange, daySummary, dayOrders } = require('../services/reports');

const router = Router();
router.use(requireAuth, requireRole('Owner'));

const ymd = (d) => {
  const p = phParts(d);
  return `${p.y}-${String(p.mo + 1).padStart(2, '0')}-${String(p.d).padStart(2, '0')}`;
};

// GET /api/sales/daily?date=YYYY-MM-DD -> { date, summary, orders, today }
router.get('/daily', async (req, res) => {
  const today = ymd(now());
  const date = req.query.date || today;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw bad('DATE_INVALID', 'Date not valid', 'Pick the date again.');
  if (date > today) throw bad('DATE_FUTURE', 'No sales yet', 'Pick today or an earlier day.');
  const [start, end] = dayRange(date);
  res.json({ date, today, summary: await daySummary(start, end), orders: await dayOrders(start, end) });
});

module.exports = router;
