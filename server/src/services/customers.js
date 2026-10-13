// One "customer" across the ways orders come in (Unpaid Accounts, Customers list).
//  - An account (u<id>): its app orders, plus logged or walk-in orders with the same phone number.
//  - Otherwise by phone number (p<phone>), or by name when there is no phone (n<name>).
const { one, query } = require('../db');

/** Every order with the customer key (ckey) and the account id (cuid) when there is one. */
const KEYED_ORDERS = `(
  SELECT o.*, COALESCE(o.customer_id, u2.user_id) AS cuid,
    CASE WHEN COALESCE(o.customer_id, u2.user_id) IS NOT NULL THEN CONCAT('u', COALESCE(o.customer_id, u2.user_id))
         WHEN COALESCE(o.contact_phone, '') <> '' THEN CONCAT('p', o.contact_phone)
         ELSE CONCAT('n', COALESCE(o.customer_name, '')) END AS ckey
  FROM orders o
  LEFT JOIN users u2 ON o.customer_id IS NULL AND u2.role = 'Customer' AND u2.phone_number = o.contact_phone
)`;

const UNPAID = "k.payment_status = 'Unpaid' AND k.status IN ('Delivered','Recorded')";

/** Name and phone shown for a key (the account's, else the newest order's). */
async function who(key) {
  if (key.startsWith('p')) {
    const acc = await one("SELECT user_id FROM users WHERE role = 'Customer' AND phone_number = ?", [key.slice(1)]);
    if (acc) key = `u${acc.user_id}`;
  }
  if (key.startsWith('u')) {
    const u = await one("SELECT user_id, full_name, phone_number, email, created_at FROM users WHERE user_id = ? AND role = 'Customer'", [Number(key.slice(1)) || 0]);
    if (u) return { key, accountId: u.user_id, name: u.full_name, phone: u.phone_number, email: u.email || '', since: u.created_at, account: true };
  }
  const o = await one(`SELECT customer_name, contact_phone FROM ${KEYED_ORDERS} k WHERE k.ckey = ? ORDER BY k.created_at DESC LIMIT 1`, [key]);
  if (!o) return null;
  return { key, accountId: null, name: o.customer_name || 'Walk-in', phone: o.contact_phone || '', email: '', since: null, account: false };
}

/** Unpaid orders of one customer, oldest first. */
async function unpaidOrders(key) {
  const rows = await query(
    `SELECT k.order_id, k.order_source, k.order_type, k.quantity, k.total_amount, k.delivered_at, k.created_at
     FROM ${KEYED_ORDERS} k WHERE k.ckey = ? AND ${UNPAID} ORDER BY COALESCE(k.delivered_at, k.created_at)`,
    [key]
  );
  return rows.map((r) => ({
    id: r.order_id,
    source: r.order_source,
    type: r.order_type,
    quantity: r.quantity,
    total: Number(r.total_amount),
    at: r.delivered_at || r.created_at,
  }));
}

/** Unpaid Accounts list: customers who owe, most owed first. q searches name or phone. */
async function unpaidAccounts(q) {
  const params = [];
  let search = '';
  if (q) {
    search = 'HAVING name LIKE ? OR phone LIKE ?';
    const digits = String(q).replace(/\D/g, '');
    params.push(`%${q}%`, `%${digits || q}%`);
  }
  const rows = await query(
    `SELECT k.ckey AS ckey, COALESCE(MAX(u.full_name), SUBSTRING_INDEX(GROUP_CONCAT(k.customer_name ORDER BY k.created_at DESC SEPARATOR '\\n'), '\\n', 1)) AS name,
       COALESCE(MAX(u.phone_number), MAX(k.contact_phone)) AS phone, COUNT(*) AS orders, SUM(k.total_amount) AS owed,
       MIN(COALESCE(k.delivered_at, k.created_at)) AS oldest
     FROM ${KEYED_ORDERS} k LEFT JOIN users u ON u.user_id = k.cuid
     WHERE ${UNPAID} GROUP BY k.ckey ${search} ORDER BY owed DESC, oldest`,
    params
  );
  return rows.map((r) => ({
    key: r.ckey,
    name: r.name || 'Walk-in',
    phone: r.phone || '',
    orders: Number(r.orders),
    owed: Number(r.owed),
    oldest: r.oldest,
  }));
}

module.exports = { KEYED_ORDERS, UNPAID, who, unpaidOrders, unpaidAccounts };
