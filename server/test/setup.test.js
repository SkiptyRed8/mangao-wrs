const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb } = require('./helpers');
const { query, one } = require('../src/db');

before(freshDb);
after(closeDb);

describe('Setup (T03-T05)', () => {
  test('health check reaches the database', async () => {
    const r = await api().get('/health');
    assert.equal(r.status, 200);
    assert.equal(r.body.ok, true);
    assert.equal(r.body.app, 'mangao-system');
    assert.equal(r.body.database, 'ok');
    assert.equal(r.body.users, 6);
  });

  test('all tables of the new ordering process exist', async () => {
    const rows = await query('SELECT table_name AS t FROM information_schema.tables WHERE table_schema = DATABASE()');
    const names = rows.map((r) => r.t).sort();
    for (const t of [
      'users', 'password_resets', 'customer_addresses', 'prices', 'station_settings', 'inventory_items', 'tank_cycles',
      'delivery_batches', 'orders', 'order_status_history', 'stock_movements', 'gallon_loans', 'damage_reports',
      'rider_locations', 'notifications', 'notification_preferences', 'device_tokens',
    ]) assert.ok(names.includes(t), `missing table ${t}`);
  });

  test('owner, prices, stock, tank and station are set', async () => {
    const owner = await one("SELECT * FROM users WHERE role = 'Owner'");
    assert.equal(owner.phone_number, '09170000001');
    assert.notEqual(owner.password_hash, '-');
    const prices = await query('SELECT item_type, amount FROM prices ORDER BY price_id');
    assert.deepEqual(prices.map((p) => [p.item_type, Number(p.amount)]), [['Refill Walk-in', 30], ['Refill Delivery', 35], ['Package', 150]]);
    const stock = await query('SELECT item_name, quantity_on_hand, low_stock_level FROM inventory_items ORDER BY item_id');
    assert.deepEqual(stock.map((s) => [s.item_name, s.quantity_on_hand, s.low_stock_level]), [['New Gallon', 24, 30], ['Seal', 420, 60]]);
    const tank = await one('SELECT * FROM tank_cycles WHERE ended_at IS NULL');
    assert.equal(tank.gallons_count, 0);
    assert.equal(tank.tank_limit, 60);
    const s = await one('SELECT * FROM station_settings');
    assert.equal(Number(s.station_latitude), 14.692823);
  });

  test('order rules are enforced by the database', async () => {
    await assert.rejects(
      query("INSERT INTO orders (order_source, order_type, quantity, unit_price, total_amount, status, payment_method) VALUES ('App','Refill',0,35,0,'New','COD')")
    );
  });

  test('unknown routes answer with a clear message', async () => {
    const r = await api().get('/nope');
    assert.equal(r.status, 404);
    assert.equal(r.body.error.code, 'NOT_FOUND');
  });
});
