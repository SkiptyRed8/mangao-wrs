const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb, loginAs } = require('./helpers');
const { one } = require('../src/db');
const { setNow } = require('../src/services/time');

let owner, staff, rider;
before(async () => {
  await freshDb();
  owner = await loginAs('09170000001', 'owner123');
  staff = await loginAs('09170000002', 'staff123');
  rider = await loginAs('09170000003', 'rider123');
});
after(async () => {
  setNow(null);
  await closeDb();
});
const as = (token, req) => req.set('Authorization', `Bearer ${token}`);
const stock = async (name) => (await one('SELECT quantity_on_hand AS q FROM inventory_items WHERE item_name = ?', [name])).q;
const tank = async () => (await one('SELECT gallons_count AS n FROM tank_cycles WHERE ended_at IS NULL')).n;

describe('Log Walk-in (FR-03; Admin Home 5, Staff 10)', () => {
  test('2 gallons refill, Paid = P60.00; tank +2, seals -6; no status steps', async () => {
    const seals = await stock('Seal');
    const r = await as(owner, api().post('/api/station/walk-in')).send({ quantity: 2, type: 'Refill', paid: true, name: 'Aling Rosa' });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.equal(r.body.message, 'Walk-in saved: 2 gallons, Paid');
    assert.equal(r.body.order.total, 60);
    assert.equal(r.body.order.status, 'Recorded');
    assert.equal(r.body.order.paymentStatus, 'Paid');
    assert.equal(await tank(), 2);
    assert.equal(await stock('Seal'), seals - 6);
  });

  test('staff saves an unpaid package walk-in: P150 each, one new gallon each', async () => {
    const gallons = await stock('New Gallon');
    const r = await as(staff, api().post('/api/station/walk-in')).send({ quantity: 1, type: 'Package', paid: false });
    assert.equal(r.body.message, 'Walk-in saved: 1 gallon, Unpaid');
    assert.equal(r.body.order.total, 150);
    assert.equal(await stock('New Gallon'), gallons - 1);
  });

  test('quantity missing; riders and customers cannot log', async () => {
    const r = await as(owner, api().post('/api/station/walk-in')).send({ quantity: 0, paid: true });
    assert.equal(r.body.error.title, 'Quantity missing');
    assert.equal((await as(rider, api().post('/api/station/walk-in')).send({ quantity: 1, paid: true })).status, 403);
  });
});

describe('Log Delivery Order (FR-03; Admin Home 5A, Staff 4)', () => {
  const form = { name: 'Ben Cruz', phone: '0918 555 2211', address: '5 Sampaguita St., Batasan Hills', quantity: 2, type: 'Refill', channel: 'Call', payment: 'Pay on delivery' };

  test('goes straight to Processing with the owner as rider and the delivery time set', async () => {
    setNow('2026-10-14T09:45:00+08:00');
    const r = await as(staff, api().post('/api/station/delivery')).send(form);
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.equal(r.body.message, 'Order saved');
    const o = r.body.order;
    assert.equal(o.status, 'Processing');
    assert.equal(o.total, 70);
    assert.equal(o.sourceText, 'Call');
    assert.equal(o.riderRole, 'Owner');
    assert.equal(o.estText, 'by 10:15 AM');
    assert.equal(o.paymentStatus, 'Pending');
    const n = await one("SELECT * FROM notifications WHERE notification_type = 'Logged Order' ORDER BY notification_id DESC LIMIT 1");
    assert.equal(n.message, 'Joy logged Ben Cruz: 2 gallons · Call');
    const board = await as(owner, api().get('/api/admin/orders?view=processing'));
    assert.ok(board.body.orders.some((x) => x.id === o.id));
    assert.equal(await tank(), 3, 'not counted until Out for Delivery');
    setNow(null);
  });

  test('paid at station, walk-in for delivery, package', async () => {
    const r = await as(owner, api().post('/api/station/delivery')).send({ ...form, channel: 'Walk-in', payment: 'Paid at station', type: 'Package', quantity: 1 });
    assert.equal(r.body.order.sourceText, 'Walk-in for delivery');
    assert.equal(r.body.order.paymentStatus, 'Paid');
    assert.equal(r.body.order.total, 150);
  });

  test('required fields', async () => {
    const r = await as(owner, api().post('/api/station/delivery')).send({ ...form, address: '' });
    assert.equal(r.body.error.title, 'Name, phone, address or quantity missing');
    assert.deepEqual(r.body.error.fields, ['address']);
    assert.equal((await as(owner, api().post('/api/station/delivery')).send({ ...form, phone: '12' })).body.error.title, 'Phone number not valid');
  });
});
