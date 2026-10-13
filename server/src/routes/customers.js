// Customers (FR-11; Admin More 1): the owner's customer list (accounts, plus logged and walk-in
// customers with a name or phone) and each customer's record: contact, addresses, order history,
// unpaid orders and borrowed gallons. A customer is one key (see services/customers.js).
const { Router } = require('express');
const { one, query } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { notFound } = require('../utils/errors');
const { text } = require('../utils/validate');
const { KEYED_ORDERS, UNPAID, who, unpaidOrders } = require('../services/customers');
const { shapeAddress } = require('../services/addresses');

const router = Router();
router.use(requireAuth, requireRole('Owner'));

/** Key of a loan row, the same way orders are keyed. */
function loanKey(l, accountByPhone) {
  if (l.customer_id) return `u${l.customer_id}`;
  if (l.contact_phone && accountByPhone[l.contact_phone]) return `u${accountByPhone[l.contact_phone]}`;
  if (l.contact_phone) return `p${l.contact_phone}`;
  return `n${l.customer_name}`;
}

async function accountsByPhone() {
  const rows = await query("SELECT user_id, phone_number FROM users WHERE role = 'Customer'");
  return Object.fromEntries(rows.map((r) => [r.phone_number, r.user_id]));
}

// GET /api/customers?q= -> { customers: [{ key, name, phone, account, orders, lastOrder, owed, borrowed }] }
router.get('/', async (req, res) => {
  const q = text(req.query.q, 60).toLowerCase();
  const rows = await query(
    `SELECT k.ckey AS ckey, MAX(k.cuid) AS uid,
       SUBSTRING_INDEX(GROUP_CONCAT(k.customer_name ORDER BY k.created_at DESC SEPARATOR '\\n'), '\\n', 1) AS name,
       MAX(k.contact_phone) AS phone, COUNT(*) AS orders, MAX(k.created_at) AS last_order,
       SUM(IF(${UNPAID}, k.total_amount, 0)) AS owed
     FROM ${KEYED_ORDERS} k WHERE k.ckey <> 'n' GROUP BY k.ckey`
  );
  const accounts = await query("SELECT user_id, full_name, phone_number, created_at FROM users WHERE role = 'Customer'");
  const acc = Object.fromEntries(accounts.map((a) => [`u${a.user_id}`, a]));
  const map = new Map();
  for (const r of rows) {
    const a = acc[r.ckey];
    map.set(r.ckey, {
      key: r.ckey,
      name: a ? a.full_name : r.name || 'Walk-in',
      phone: a ? a.phone_number : r.phone || '',
      account: !!a,
      orders: Number(r.orders),
      lastOrder: r.last_order,
      owed: Number(r.owed),
      borrowed: 0,
    });
  }
  for (const a of accounts) {
    const key = `u${a.user_id}`;
    if (!map.has(key)) map.set(key, { key, name: a.full_name, phone: a.phone_number, account: true, orders: 0, lastOrder: null, owed: 0, borrowed: 0 });
  }
  const byPhone = Object.fromEntries(accounts.map((a) => [a.phone_number, a.user_id]));
  const loans = await query('SELECT customer_id, customer_name, contact_phone, quantity FROM gallon_loans WHERE returned_at IS NULL');
  for (const l of loans) {
    const key = loanKey(l, byPhone);
    if (!map.has(key)) map.set(key, { key, name: l.customer_name, phone: l.contact_phone || '', account: false, orders: 0, lastOrder: null, owed: 0, borrowed: 0 });
    map.get(key).borrowed += l.quantity;
  }
  let list = [...map.values()];
  if (q) {
    const digits = q.replace(/\D/g, '');
    list = list.filter((c) => c.name.toLowerCase().includes(q) || (digits && c.phone.includes(digits)));
  }
  list.sort((a, b) => new Date(b.lastOrder || 0) - new Date(a.lastOrder || 0) || a.name.localeCompare(b.name));
  res.json({ count: map.size, customers: list });
});

// GET /api/customers/:key -> { customer, stats, addresses, orders, unpaid: { owed, orders }, loans }
router.get('/:key', async (req, res) => {
  const customer = await who(String(req.params.key));
  if (!customer) {
    // Someone who only borrowed gallons (no orders yet).
    const key = String(req.params.key);
    const l = await one(
      key.startsWith('p') ? 'SELECT * FROM gallon_loans WHERE contact_phone = ? ORDER BY lent_at DESC LIMIT 1' : 'SELECT * FROM gallon_loans WHERE customer_name = ? AND contact_phone IS NULL ORDER BY lent_at DESC LIMIT 1',
      [key.slice(1)]
    );
    if (!l) throw notFound('CUSTOMER_NOT_FOUND', 'Customer not found', 'Go back to Customers.');
  }
  const c = customer || (() => {
    const key = String(req.params.key);
    return { key, accountId: null, name: key.startsWith('n') ? key.slice(1) : '', phone: key.startsWith('p') ? key.slice(1) : '', email: '', since: null, account: false };
  })();
  if (!c.name) {
    const l = await one('SELECT customer_name FROM gallon_loans WHERE contact_phone = ? ORDER BY lent_at DESC LIMIT 1', [c.phone]);
    c.name = l ? l.customer_name : 'Walk-in';
  }

  const orders = await query(
    `SELECT k.order_id, k.order_source, k.order_type, k.quantity, k.total_amount, k.status, k.payment_status, k.payment_method,
       k.delivery_address_text, k.delivery_latitude, k.delivery_longitude, k.created_at, k.delivered_at
     FROM ${KEYED_ORDERS} k WHERE k.ckey = ? ORDER BY k.created_at DESC, k.order_id DESC LIMIT 100`,
    [c.key]
  );
  const done = orders.filter((o) => ['Delivered', 'Recorded'].includes(o.status));

  let addresses = [];
  if (c.accountId) {
    addresses = (await query('SELECT * FROM customer_addresses WHERE customer_id = ? ORDER BY address_id', [c.accountId])).map((a) => ({ ...shapeAddress(a), saved: true }));
  }
  // Addresses used on their orders (newest first, no repeats).
  const seen = new Set(addresses.map((a) => a.text));
  for (const o of orders) {
    const t = o.delivery_address_text;
    if (!t || seen.has(t) || addresses.length >= 8) continue;
    seen.add(t);
    addresses.push({
      id: null,
      name: 'Used on an order',
      text: t,
      lat: o.delivery_latitude === null ? null : Number(o.delivery_latitude),
      lng: o.delivery_longitude === null ? null : Number(o.delivery_longitude),
      saved: false,
    });
  }

  const byPhone = await accountsByPhone();
  const loanRows = await query(
    `SELECT l.*, lb.full_name AS lent_name, lb.role AS lent_role FROM gallon_loans l LEFT JOIN users lb ON lb.user_id = l.lent_by
     WHERE l.customer_id = ? OR l.contact_phone = ? OR (l.contact_phone IS NULL AND l.customer_name = ?)
     ORDER BY l.returned_at IS NULL DESC, l.lent_at DESC LIMIT 100`,
    [c.accountId || 0, c.phone || '#', c.name]
  );
  const loans = loanRows
    .filter((l) => loanKey(l, byPhone) === c.key)
    .map((l) => ({
      id: l.loan_id,
      name: l.customer_name,
      phone: l.contact_phone || '',
      orderId: l.order_id,
      quantity: l.quantity,
      lentAt: l.lent_at,
      lentBy: l.lent_role === 'Owner' ? 'Owner' : l.lent_name || '',
      returnedAt: l.returned_at,
      returnedBy: '',
      note: l.note || '',
      out: !l.returned_at,
    }));

  const unpaid = await unpaidOrders(c.key);
  res.json({
    customer: c,
    stats: {
      orders: orders.length,
      completed: done.length,
      gallons: done.reduce((a, o) => a + o.quantity, 0),
      spent: done.filter((o) => o.payment_status === 'Paid').reduce((a, o) => a + Number(o.total_amount), 0),
      borrowed: loans.filter((l) => l.out).reduce((a, l) => a + l.quantity, 0),
    },
    addresses,
    orders: orders.map((o) => ({
      id: o.order_id,
      source: o.order_source,
      type: o.order_type,
      quantity: o.quantity,
      total: Number(o.total_amount),
      status: o.status,
      paymentStatus: o.payment_status,
      payment: o.payment_method,
      at: o.created_at,
    })),
    unpaid: { owed: unpaid.reduce((a, o) => a + o.total, 0), orders: unpaid },
    loans,
  });
});

module.exports = router;
