// Day figures used by the owner's Home (Today's Summary) and the Daily Sales Report (FR-10).
//  - Money earned: payments received that day (paid at the station, paid on delivery, walk-ins paid,
//    and old unpaid orders marked paid that day).
//  - Unpaid: orders completed that day that are still unpaid.
//  - Gallons processed: gallons counted that day (sent out or walk-in saved); delivery vs walk-in.
//  - Rider paid: cash the riders (or the owner) collected on delivery that day.
const { one, query } = require('../db');
const { phAt } = require('./time');

/** [start, end) of a Philippine-time day 'YYYY-MM-DD' (or of the day of a Date). */
function dayRange(day) {
  const d = typeof day === 'string' ? new Date(`${day}T12:00:00+08:00`) : day;
  const start = phAt(d, 0, 0);
  return [start, new Date(start.getTime() + 24 * 60 * 60 * 1000)];
}

async function daySummary(start, end) {
  const n = (v) => Number(v || 0);
  const money = await one("SELECT SUM(total_amount) AS v FROM orders WHERE payment_status = 'Paid' AND paid_at >= ? AND paid_at < ?", [start, end]);
  const unpaid = await one(
    "SELECT SUM(total_amount) AS v FROM orders WHERE payment_status = 'Unpaid' AND status IN ('Delivered','Recorded') AND delivered_at >= ? AND delivered_at < ?",
    [start, end]
  );
  const g = await one(
    `SELECT SUM(quantity) AS total, SUM(IF(order_type = 'Package', quantity, 0)) AS packages,
       SUM(IF(order_source = 'Walk-in', quantity, 0)) AS walkin, SUM(IF(order_source <> 'Walk-in', quantity, 0)) AS delivery
     FROM orders WHERE tank_counted_at >= ? AND tank_counted_at < ?`,
    [start, end]
  );
  const rider = await one(
    `SELECT SUM(total_amount) AS v FROM orders WHERE payment_status = 'Paid' AND payment_method IN ('COD','Pay on delivery')
       AND paid_at = delivered_at AND delivered_at >= ? AND delivered_at < ?`,
    [start, end]
  );
  const walkins = await one("SELECT COUNT(*) AS c FROM orders WHERE order_source = 'Walk-in' AND created_at >= ? AND created_at < ?", [start, end]);
  const delivered = await one("SELECT COUNT(*) AS c FROM orders WHERE status = 'Delivered' AND delivered_at >= ? AND delivered_at < ?", [start, end]);
  return {
    moneyEarned: n(money.v),
    unpaid: n(unpaid.v),
    gallons: n(g.total),
    packages: n(g.packages),
    deliveryGallons: n(g.delivery),
    walkInGallons: n(g.walkin),
    riderPaid: n(rider.v),
    walkIns: n(walkins.c),
    delivered: n(delivered.c),
  };
}

/** Orders completed that day (delivered or walk-in saved), newest first. */
async function dayOrders(start, end) {
  const rows = await query(
    `SELECT order_id, order_source, customer_name, quantity, order_type, total_amount, payment_method, payment_status, delivered_at
     FROM orders WHERE status IN ('Delivered','Recorded') AND delivered_at >= ? AND delivered_at < ? ORDER BY delivered_at DESC`,
    [start, end]
  );
  return rows.map((r) => ({
    id: r.order_id,
    name: r.order_source === 'Walk-in' ? (r.customer_name ? `Walk-in: ${r.customer_name}` : 'Walk-in') : r.customer_name || 'Guest',
    quantity: r.quantity,
    type: r.order_type,
    total: Number(r.total_amount),
    tag: r.payment_method === 'Paid at station' ? 'Paid at station' : r.payment_status,
    at: r.delivered_at,
  }));
}

module.exports = { dayRange, daySummary, dayOrders };

// ---------------------------------------------------------------- Weekly Sales Report (step 37)
const DAY_NAMES = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/** 'YYYY-MM-DD' plus n days. */
function addDays(ymd, n) {
  const d = new Date(`${ymd}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** The Monday of the week of 'YYYY-MM-DD'. */
function mondayOf(ymd) {
  const d = new Date(`${ymd}T12:00:00Z`);
  const back = (d.getUTCDay() + 6) % 7; // Sunday 0 -> 6 days back
  return addDays(ymd, -back);
}

const SUM_KEYS = ['moneyEarned', 'unpaid', 'gallons', 'packages', 'deliveryGallons', 'walkInGallons', 'riderPaid', 'walkIns', 'delivered'];

/** Totals of the 7 days from Monday 'start'; days after 'today' are 0 and marked future. */
async function weekSummary(start, today) {
  const days = [];
  const totals = Object.fromEntries(SUM_KEYS.map((k) => [k, 0]));
  for (let i = 0; i < 7; i++) {
    const date = addDays(start, i);
    const future = date > today;
    const s = future ? Object.fromEntries(SUM_KEYS.map((k) => [k, 0])) : await daySummary(...dayRange(date));
    for (const k of SUM_KEYS) totals[k] += s[k];
    days.push({ date, day: DAY_NAMES[i], future, ...s, orders: s.delivered + s.walkIns });
  }
  totals.orders = totals.delivered + totals.walkIns;
  return { days, totals };
}

/** Percent change from last week to this week (null when last week was 0). */
const change = (now, before) => (before ? Math.round(((now - before) / before) * 1000) / 10 : null);

module.exports.addDays = addDays;
module.exports.mondayOf = mondayOf;
module.exports.weekSummary = weekSummary;
module.exports.change = change;
