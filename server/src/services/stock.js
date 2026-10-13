// Raw water tank counter and stock (FR-06, FR-07).
// A delivery order counts once, the first time it goes Out for Delivery (re-delivery is not counted
// again); a walk-in counts when it is saved. Each counted gallon uses seals (3 per gallon by default);
// each package also uses one new gallon from stock.
const { notify } = require('./orders');
const { now } = require('./time');

/** Sends an alert to every active account with one of the roles. */
async function notifyRoles(conn, roles, n) {
  const [rows] = await conn.query('SELECT user_id FROM users WHERE role IN (?) AND is_active = 1', [roles]);
  for (const r of rows) await notify(conn, { ...n, userId: r.user_id });
}

/** The open tank cycle (there is always one; a new one starts when the owner refills the tank). */
async function openCycle(conn) {
  const [[c]] = await conn.query('SELECT * FROM tank_cycles WHERE ended_at IS NULL ORDER BY cycle_id DESC LIMIT 1 FOR UPDATE');
  if (c) return c;
  const [[s]] = await conn.query('SELECT tank_limit FROM station_settings WHERE setting_id = 1');
  const [r] = await conn.query('INSERT INTO tank_cycles (gallons_count, tank_limit) VALUES (0, ?)', [s.tank_limit]);
  const [[fresh]] = await conn.query('SELECT * FROM tank_cycles WHERE cycle_id = ?', [r.insertId]);
  return fresh;
}

/** Changes the stock of an item, writes the movement history and the low-stock alert when it drops below the level. */
async function moveStock(conn, itemName, change, type, userId, { orderId = null, note = null } = {}) {
  if (!change) return;
  const [[item]] = await conn.query('SELECT * FROM inventory_items WHERE item_name = ? FOR UPDATE', [itemName]);
  const before = item.quantity_on_hand;
  const after = before + change;
  await conn.query('UPDATE inventory_items SET quantity_on_hand = ? WHERE item_id = ?', [after, item.item_id]);
  await conn.query(
    'INSERT INTO stock_movements (item_id, order_id, recorded_by, movement_type, quantity_change, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [item.item_id, orderId, userId || null, type, change, note, now()]
  );
  if (before >= item.low_stock_level && after < item.low_stock_level) {
    const what = itemName === 'Seal' ? 'seals' : 'new gallons';
    await notifyRoles(conn, ['Owner'], {
      type: 'Low Stock',
      title: `Low ${what}: ${after} left`,
      message: `Below the low-stock level of ${item.low_stock_level}. Add stock in Inventory.`,
    });
  }
}

/**
 * Counts an order in the tank counter and uses its seals (and new gallons for packages). Does nothing
 * when the order was already counted. Returns { counted, cycle } for messages.
 */
async function countOrder(conn, order, userId) {
  if (order.tank_counted_at) return { counted: false };
  const qty = order.quantity;
  const c = await openCycle(conn);
  const count = c.gallons_count + qty;
  const t = now();
  await conn.query('UPDATE tank_cycles SET gallons_count = ? WHERE cycle_id = ?', [count, c.cycle_id]);
  await conn.query('UPDATE orders SET tank_counted_at = ?, tank_cycle_id = ? WHERE order_id = ?', [t, c.cycle_id, order.order_id]);
  if (!c.alerted_at && count >= c.tank_limit) {
    await conn.query('UPDATE tank_cycles SET alerted_at = ? WHERE cycle_id = ?', [t, c.cycle_id]);
    await notifyRoles(conn, ['Owner', 'Staff'], {
      type: 'Tank',
      title: `Refill the raw water tank: ${count} / ${c.tank_limit}`,
      message: `${count} gallons processed since the last refill. Only the owner resets the counter.`,
    });
  }
  const [[s]] = await conn.query('SELECT seals_per_gallon FROM station_settings WHERE setting_id = 1');
  const note = `Order #${order.order_id}`;
  await moveStock(conn, 'Seal', -qty * s.seals_per_gallon, 'Used', userId, { orderId: order.order_id, note });
  if (order.order_type === 'Package') await moveStock(conn, 'New Gallon', -qty, 'Used', userId, { orderId: order.order_id, note });
  return { counted: true, count, limit: c.tank_limit };
}

module.exports = { notifyRoles, openCycle, moveStock, countOrder };
