// Borrowed Gallons (FR-13; Admin Orders 8, Admin Inventory 5, Staff 8). The owner and staff lend the
// station's new gallons to a customer (stock goes down, "Lent") and mark them returned, all or part
// (stock goes up, "Returned"). A part return splits the entry: the returned part becomes its own
// returned entry and the rest stays out.
const { Router } = require('express');
const { one, query, transaction } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad, notFound, conflict } = require('../utils/errors');
const { int, text, normalizePhone, isPhone } = require('../utils/validate');
const { now, phAt } = require('../services/time');
const { moveStock } = require('../services/process');
const { addHistory } = require('../services/orders');
const realtime = require('../services/realtime');

const router = Router();
router.use(requireAuth, requireRole('Owner', 'Staff'));

const SELECT = `SELECT l.*, lb.full_name AS lent_name, lb.role AS lent_role, rb.full_name AS ret_name, rb.role AS ret_role
  FROM gallon_loans l LEFT JOIN users lb ON lb.user_id = l.lent_by LEFT JOIN users rb ON rb.user_id = l.returned_by`;

const who = (name, role) => (role === 'Owner' ? 'Owner' : name || '');
const shape = (l) => ({
  id: l.loan_id,
  name: l.customer_name,
  phone: l.contact_phone || '',
  customerId: l.customer_id,
  orderId: l.order_id,
  quantity: l.quantity,
  lentAt: l.lent_at,
  lentBy: who(l.lent_name, l.lent_role),
  returnedAt: l.returned_at,
  returnedBy: l.returned_at ? who(l.ret_name, l.ret_role) : '',
  note: l.note || '',
  out: !l.returned_at,
});

// GET /api/loans?status=out|returned|all&q=&orderId= -> { gallonsOut, loans }
router.get('/', async (req, res) => {
  const where = [];
  const params = [];
  const status = req.query.status || 'out';
  if (status === 'out') where.push('l.returned_at IS NULL');
  if (status === 'returned') where.push('l.returned_at IS NOT NULL');
  if (req.query.orderId) {
    where.push('l.order_id = ?');
    params.push(Number(req.query.orderId) || 0);
  }
  const q = text(req.query.q, 60);
  if (q) {
    where.push('(l.customer_name LIKE ? OR l.contact_phone LIKE ?)');
    params.push(`%${q}%`, `%${q.replace(/\D/g, '') || q}%`);
  }
  const rows = await query(
    `${SELECT} ${where.length ? `WHERE ${where.join(' AND ')}` : ''} ORDER BY l.returned_at IS NULL DESC, COALESCE(l.returned_at, l.lent_at) DESC, l.loan_id DESC LIMIT 300`,
    params
  );
  const out = await one('SELECT COALESCE(SUM(quantity), 0) AS n, COUNT(DISTINCT customer_name, COALESCE(contact_phone, "")) AS c FROM gallon_loans WHERE returned_at IS NULL');
  res.json({ gallonsOut: Number(out.n), customersOut: Number(out.c), loans: rows.map(shape) });
});

function lendDate(v) {
  if (!v) return now();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) throw bad('DATE_INVALID', 'Date not valid', 'Pick the date again.');
  const d = new Date(`${v}T12:00:00+08:00`);
  if (d >= phAt(now(), 0, 0)) {
    if (d.getTime() > now().getTime() + 86400000) throw bad('DATE_FUTURE', 'Date is in the future', 'Pick today or an earlier day.');
    return now();
  }
  return d;
}

// POST /api/loans { orderId?, name, phone, quantity, date, note } -> { loan, message }
router.post('/', async (req, res) => {
  const b = req.body || {};
  const qty = int(b.quantity, 1, 100);
  let name = text(b.name, 100);
  let phone = normalizePhone(b.phone);
  let customerId = null;
  let order = null;
  if (b.orderId) {
    order = await one('SELECT * FROM orders WHERE order_id = ?', [Number(b.orderId) || 0]);
    if (!order) throw notFound('ORDER_NOT_FOUND', 'Order not found', 'It may have been removed.');
    name = name || order.customer_name || 'Walk-in';
    phone = phone || order.contact_phone || '';
    customerId = order.customer_id;
  }
  if (!name) throw bad('NAME_MISSING', 'Customer name missing', 'Type who borrowed the gallons.', { field: 'name' });
  if (phone && !isPhone(phone)) throw bad('PHONE_INVALID', 'Phone number not valid', 'Use 11 digits, e.g. 0917 123 4567.', { field: 'phone' });
  if (qty === null) throw bad('QTY_MISSING', 'Quantity missing', 'Tap + to set how many gallons.', { field: 'quantity' });
  if (!customerId && phone) {
    const acc = await one("SELECT user_id FROM users WHERE role = 'Customer' AND phone_number = ?", [phone]);
    if (acc) customerId = acc.user_id;
  }
  const stock = await one("SELECT quantity_on_hand AS n FROM inventory_items WHERE item_name = 'New Gallon'");
  if (stock.n < qty) throw conflict('NOT_ENOUGH', 'Not enough new gallons', `Only ${stock.n} in stock. Add stock first.`);
  const at = lendDate(b.date);
  const note = text(b.note, 255) || null;
  const id = await transaction(async (conn) => {
    const [r] = await conn.query(
      'INSERT INTO gallon_loans (customer_id, customer_name, contact_phone, order_id, quantity, lent_by, lent_at, note) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [customerId, name, phone || null, order ? order.order_id : null, qty, req.user.user_id, at, note]
    );
    await moveStock(conn, 'New Gallon', -qty, { type: 'Lent', note: `Lent to ${name}`, orderId: order ? order.order_id : null, userId: req.user.user_id, at });
    if (order) await addHistory(conn, order.order_id, 'Gallon lent', req.user.user_id, `${qty} ${qty === 1 ? 'gallon' : 'gallons'} lent`);
    return r.insertId;
  });
  if (order) realtime.orderChanged(order.order_id);
  realtime.ownerRefresh('loans');
  const loan = await one(`${SELECT} WHERE l.loan_id = ?`, [id]);
  res.status(201).json({ loan: shape(loan), message: 'Gallons lent. Stock goes down.' });
});

// POST /api/loans/:id/return { quantity } -> { loan, message }  quantity defaults to all still out.
router.post('/:id/return', async (req, res) => {
  const loan = await one('SELECT * FROM gallon_loans WHERE loan_id = ?', [Number(req.params.id) || 0]);
  if (!loan) throw notFound('LOAN_NOT_FOUND', 'Entry not found', 'It may have been removed.');
  if (loan.returned_at) throw conflict('ALREADY_RETURNED', 'Already returned', 'This entry is already marked returned.');
  const b = req.body || {};
  const qty = b.quantity === undefined || b.quantity === null || b.quantity === '' ? loan.quantity : int(b.quantity, 1, loan.quantity);
  if (qty === null) throw bad('QTY_INVALID', 'Quantity not valid', `From 1 to ${loan.quantity}.`, { field: 'quantity' });
  const t = now();
  const id = await transaction(async (conn) => {
    let returnedId = loan.loan_id;
    if (qty < loan.quantity) {
      await conn.query('UPDATE gallon_loans SET quantity = quantity - ? WHERE loan_id = ?', [qty, loan.loan_id]);
      const [r] = await conn.query(
        `INSERT INTO gallon_loans (customer_id, customer_name, contact_phone, order_id, quantity, lent_by, lent_at, returned_at, returned_by, note)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [loan.customer_id, loan.customer_name, loan.contact_phone, loan.order_id, qty, loan.lent_by, loan.lent_at, t, req.user.user_id, loan.note]
      );
      returnedId = r.insertId;
    } else {
      await conn.query('UPDATE gallon_loans SET returned_at = ?, returned_by = ? WHERE loan_id = ?', [t, req.user.user_id, loan.loan_id]);
    }
    await moveStock(conn, 'New Gallon', qty, { type: 'Returned', note: `Returned by ${loan.customer_name}`, orderId: loan.order_id, userId: req.user.user_id, at: t });
    if (loan.order_id) await addHistory(conn, loan.order_id, 'Gallon returned', req.user.user_id, `${qty} ${qty === 1 ? 'gallon' : 'gallons'} returned`, t);
    return returnedId;
  });
  if (loan.order_id) realtime.orderChanged(loan.order_id);
  realtime.ownerRefresh('loans');
  const left = loan.quantity - qty;
  res.json({
    loan: shape(await one(`${SELECT} WHERE l.loan_id = ?`, [id])),
    left,
    message: left ? `${qty} returned. ${left} still borrowed.` : 'Returned. Stock goes up.',
  });
});

module.exports = router;
