// Rules shared by the work screens (Chapter 4, Oct 13 ordering process):
//  - Tank counter and seals (3 per gallon) count when a delivery order goes Out for Delivery (first
//    time only) or when a walk-in is saved. A package also uses 1 new gallon per gallon ordered.
//    Not delivered stays counted; a re-delivery is not counted again.
//  - At the tank limit (60) the owner gets "Tank at 60"; stock at or below its low-stock level
//    gives "Low stock". Orders are never blocked.
const { now } = require('./time');
const { notifyOwner, notifyCustomer, addHistory } = require('./orders');

async function openCycle(conn) {
  const [[c]] = await conn.query('SELECT * FROM tank_cycles WHERE ended_at IS NULL ORDER BY cycle_id DESC LIMIT 1 FOR UPDATE');
  if (c) return c;
  const [[s]] = await conn.query('SELECT tank_limit FROM station_settings WHERE setting_id = 1');
  const [r] = await conn.query('INSERT INTO tank_cycles (gallons_count, tank_limit) VALUES (0, ?)', [s.tank_limit]);
  const [[n]] = await conn.query('SELECT * FROM tank_cycles WHERE cycle_id = ?', [r.insertId]);
  return n;
}

/** Changes one stock item and writes the movement; sends the low-stock alert when it drops to the level. */
async function moveStock(conn, itemName, change, { type, note, orderId = null, userId = null, at = now() }) {
  const [[item]] = await conn.query('SELECT * FROM inventory_items WHERE item_name = ? FOR UPDATE', [itemName]);
  const before = item.quantity_on_hand;
  const after = before + change;
  await conn.query('UPDATE inventory_items SET quantity_on_hand = ? WHERE item_id = ?', [after, item.item_id]);
  await conn.query(
    'INSERT INTO stock_movements (item_id, order_id, recorded_by, movement_type, quantity_change, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [item.item_id, orderId, userId, type, change, note, at]
  );
  if (change < 0 && before > item.low_stock_level && after <= item.low_stock_level) {
    const label = itemName === 'Seal' ? 'Seals' : 'Gallons';
    await notifyOwner(conn, { type: 'Low Stock', title: 'Low stock', message: `${label}: ${after} left` });
  }
  return after;
}

/**
 * Counts an order once: tank counter + gallons, seals - 3 per gallon, new gallons - 1 per package gallon.
 * Returns the new tank count (or null when the order was already counted).
 */
async function countOrder(conn, order, { userId = null, why, at = now() }) {
  const [[fresh]] = await conn.query('SELECT tank_counted_at FROM orders WHERE order_id = ? FOR UPDATE', [order.order_id]);
  if (fresh.tank_counted_at) return null;
  const cycle = await openCycle(conn);
  const count = cycle.gallons_count + order.quantity;
  await conn.query('UPDATE tank_cycles SET gallons_count = ? WHERE cycle_id = ?', [count, cycle.cycle_id]);
  if (!cycle.alerted_at && count >= cycle.tank_limit) {
    await conn.query('UPDATE tank_cycles SET alerted_at = ? WHERE cycle_id = ?', [at, cycle.cycle_id]);
    await notifyOwner(conn, { type: 'Tank', title: `Tank at ${cycle.tank_limit}`, message: 'Refill the water tank' });
  }
  await conn.query('UPDATE orders SET tank_counted_at = ?, tank_cycle_id = ? WHERE order_id = ?', [at, cycle.cycle_id, order.order_id]);

  const [[s]] = await conn.query('SELECT seals_per_gallon FROM station_settings WHERE setting_id = 1');
  const seals = s.seals_per_gallon * order.quantity;
  await moveStock(conn, 'Seal', -seals, { type: 'Used', note: why, orderId: order.order_id, at });
  if (order.order_type === 'Package') {
    await moveStock(conn, 'New Gallon', -order.quantity, { type: 'Used', note: 'Package sold', orderId: order.order_id, at });
  }
  return count;
}

/** The owner account that rides for logged orders (the first active Owner). */
async function ownerId(conn) {
  const [[o]] = await conn.query("SELECT user_id FROM users WHERE role = 'Owner' AND is_active = 1 ORDER BY user_id LIMIT 1");
  return o.user_id;
}

/** Closes a delivery batch when none of its orders is still out (location sharing stops). */
async function finishBatchIfDone(conn, batchId, at = now()) {
  if (!batchId) return false;
  const [[r]] = await conn.query("SELECT COUNT(*) AS n FROM orders WHERE batch_id = ? AND status = 'Out for Delivery'", [batchId]);
  if (r.n > 0) return false;
  await conn.query('UPDATE delivery_batches SET finished_at = ? WHERE batch_id = ? AND finished_at IS NULL', [at, batchId]);
  return true;
}

const peso = (n) => `P${Number(n).toFixed(2)}`;

/**
 * Rider (or owner) records Delivered. paid: true / false; ignored when it was already paid at the station.
 * Returns { message, batchDone }.
 */
async function recordDelivered(conn, order, userId, paid) {
  const t = now();
  const already = order.payment_status === 'Paid';
  const status = already ? 'Paid' : paid ? 'Paid' : 'Unpaid';
  await conn.query(
    "UPDATE orders SET status = 'Delivered', delivered_at = ?, payment_status = ?, paid_at = IF(? = 'Paid', COALESCE(paid_at, ?), NULL) WHERE order_id = ?",
    [t, status, status, t, order.order_id]
  );
  const label = already ? (order.payment_method === 'Paid at station' ? 'Delivered (Paid at station)' : 'Delivered (Paid)') : `Delivered (${status})`;
  await addHistory(conn, order.order_id, label, userId, null, t);
  await notifyCustomer(conn, order, {
    type: 'Delivered',
    title: 'Delivered',
    message: status === 'Unpaid' ? `Your order was delivered. Amount owed: ${peso(order.total_amount)}.` : 'Your order was delivered. Thank you!',
  });
  const batchDone = await finishBatchIfDone(conn, order.batch_id, t);
  let message = already ? 'Delivered.' : status === 'Paid' ? 'Delivered. Paid.' : `Delivered; customer owes ${peso(order.total_amount)}`;
  if (batchDone) message += ' Location sharing off.';
  return { message, batchDone };
}

/** Rider (or owner) records Not delivered with an optional note. */
async function recordNotDelivered(conn, order, userId, note) {
  const t = now();
  await conn.query("UPDATE orders SET status = 'Not Delivered' WHERE order_id = ?", [order.order_id]);
  await addHistory(conn, order.order_id, 'Not delivered', userId, note || null, t);
  const who = order.customer_name || 'Guest';
  await notifyOwner(conn, {
    orderId: order.order_id,
    type: 'Not Delivered',
    title: 'Not delivered',
    message: `${who}${note ? `: ${note}` : ''}. Re-deliver or cancel.`,
  });
  await notifyCustomer(conn, order, {
    type: 'Not Delivered',
    title: 'Not delivered',
    message: 'The station will contact you to deliver again or cancel.',
  });
  const batchDone = await finishBatchIfDone(conn, order.batch_id, t);
  return { message: batchDone ? 'Owner and customer notified. Location sharing off.' : 'Owner and customer notified', batchDone };
}

module.exports = { openCycle, moveStock, countOrder, ownerId, finishBatchIfDone, recordDelivered, recordNotDelivered, peso };
