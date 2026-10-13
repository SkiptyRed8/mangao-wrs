// Sales reports (FR-10; Admin Sales 1-2): daily and weekly. Unpaid accounts and export are below.
const { Router } = require('express');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad } = require('../utils/errors');
const { now, phParts } = require('../services/time');
const { unpaidAccounts, unpaidOrders, who } = require('../services/customers');
const { notFound } = require('../utils/errors');
const { dayRange, daySummary, dayOrders, addDays, mondayOf, weekSummary, change } = require('../services/reports');

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

// GET /api/sales/weekly?start=YYYY-MM-DD (any day of the week; the Monday is used)
//  -> { start, end, today, days[7], totals, lastWeek, change: { moneyEarned, gallons, orders } }
router.get('/weekly', async (req, res) => {
  const today = ymd(now());
  const pick = req.query.start || today;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(pick)) throw bad('DATE_INVALID', 'Date not valid', 'Pick the week again.');
  const start = mondayOf(pick);
  if (start > today) throw bad('DATE_FUTURE', 'No sales yet', 'Pick this week or an earlier week.');
  const week = await weekSummary(start, today);
  const last = await weekSummary(addDays(start, -7), today);
  res.json({
    start,
    end: addDays(start, 6),
    today,
    days: week.days,
    totals: week.totals,
    lastWeek: last.totals,
    lastWeekDays: last.days.map((d) => ({ date: d.date, day: d.day, moneyEarned: d.moneyEarned })),
    change: {
      moneyEarned: change(week.totals.moneyEarned, last.totals.moneyEarned),
      gallons: change(week.totals.gallons, last.totals.gallons),
      orders: change(week.totals.orders, last.totals.orders),
    },
  });
});

// GET /api/sales/unpaid?q= -> { total, count, customers: [{ key, name, phone, orders, owed, oldest }] }  (Admin Sales 3)
router.get('/unpaid', async (req, res) => {
  const q = String(req.query.q || '').trim().slice(0, 60);
  const customers = await unpaidAccounts(q);
  const all = q ? await unpaidAccounts('') : customers;
  res.json({ total: all.reduce((a, c) => a + c.owed, 0), count: all.length, customers });
});

// GET /api/sales/unpaid/:key -> { customer, owed, orders }  One customer's unpaid orders; Paid uses
// POST /api/admin/orders/:id/paid.
router.get('/unpaid/:key', async (req, res) => {
  const customer = await who(String(req.params.key));
  if (!customer) throw notFound('CUSTOMER_NOT_FOUND', 'Customer not found', 'Go back to Unpaid Accounts.');
  const orders = await unpaidOrders(customer.key);
  res.json({ customer, owed: orders.reduce((a, o) => a + o.total, 0), orders });
});

module.exports = router;
