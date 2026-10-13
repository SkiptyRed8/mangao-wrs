const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb, loginAs } = require('./helpers');
const { one, query } = require('../src/db');
const { setNow } = require('../src/services/time');

let ana, maria, owner, staff;
before(async () => {
  await freshDb();
  ana = await loginAs('09172001111', 'ana123');
  maria = await loginAs('09171234567', 'maria123');
  owner = await loginAs('09170000001', 'owner123');
  staff = await loginAs('09170000002', 'staff123');
});
after(async () => {
  setNow(null);
  await closeDb();
});
const as = (token, req) => req.set('Authorization', `Bearer ${token}`);

const typed = { mode: 'typed', house: '12', blockLot: 'Blk 2 Lot 5', street: 'Sampaguita St.', barangay: 'commonwealth', landmark: 'Near the chapel' };

describe('Customer Home and Order Form (FR-15; Customer 2, 3, 3A)', () => {
  test('home shows the price list and no active order yet', async () => {
    const r = await as(ana, api().get('/api/orders/home'));
    assert.equal(r.status, 200);
    assert.deepEqual(r.body.prices, { walkIn: 30, delivery: 35, package: 150 });
    assert.equal(r.body.active.length, 0);
    assert.equal(r.body.unpaid, 0);
    assert.equal(r.body.stationPhone, '09170000001');
  });

  let first;
  test('3 gallons refill = 3 x P35.00 = P105.00, cash on delivery, thank-you message', async () => {
    const r = await as(ana, api().post('/api/orders')).send({ type: 'Refill', quantity: 3, address: typed, notes: 'Leave at the gate' });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    first = r.body.order;
    assert.equal(first.total, 105);
    assert.equal(first.unitPrice, 35);
    assert.equal(first.status, 'New');
    assert.equal(first.payment, 'COD');
    assert.equal(first.address, '12 Sampaguita St., Blk 2 Lot 5, Commonwealth');
    assert.equal(first.phone, '09172001111');
    assert.equal(r.body.title, 'Thank you for your order!');
    const n = await one("SELECT * FROM notifications WHERE user_id = 1 AND notification_type = 'New Order' ORDER BY notification_id DESC LIMIT 1");
    assert.equal(n.message, 'Ana Lim: 3 gallons · Refill');
    const home = await as(ana, api().get('/api/orders/home'));
    assert.equal(home.body.active[0].id, first.id);
  });

  test('package uses the package price; pinned and saved addresses work', async () => {
    const p = await as(ana, api().post('/api/orders')).send({
      type: 'Package', quantity: 2, phone: '0917 200 1111',
      address: { mode: 'pin', lat: 14.6976, lng: 121.0886, street: 'Malaya St.', barangay: 'Commonwealth' },
    });
    assert.equal(p.body.order.total, 300);
    assert.equal(p.body.order.address, 'Pinned: near Malaya St., Commonwealth');
    const saved = await as(ana, api().get('/api/addresses'));
    const s = await as(ana, api().post('/api/orders')).send({ type: 'Refill', quantity: 1, addressId: saved.body.addresses[0].id });
    assert.equal(s.body.order.address, '12 Malaya St., Commonwealth');
    const again = await as(ana, api().post('/api/orders')).send({ type: 'Refill', quantity: 2, fromOrderId: p.body.order.id });
    assert.equal(again.body.order.address, 'Pinned: near Malaya St., Commonwealth');
    assert.equal(again.body.order.lat, 14.6976);
    for (const id of [p.body.order.id, s.body.order.id, again.body.order.id]) await as(ana, api().post(`/api/orders/${id}/cancel`));
  });

  test('form messages', async () => {
    const cases = [
      [{ type: 'Refill', quantity: 0, address: typed }, 'Number of gallons not valid'],
      [{ type: 'Refill', quantity: 2 }, 'Delivery address missing'],
      [{ type: 'Refill', quantity: 2, address: { mode: 'typed', house: '12' } }, 'Fill in the missing fields'],
      [{ type: 'Refill', quantity: 2, address: { ...typed, barangay: 'Makati' } }, 'Choose a barangay'],
      [{ type: 'Refill', quantity: 2, address: { mode: 'pin' } }, 'Pin missing'],
      [{ type: 'Refill', quantity: 2, address: typed, phone: '123' }, 'Phone number not valid'],
    ];
    for (const [body, title] of cases) {
      const r = await as(ana, api().post('/api/orders')).send(body);
      assert.equal(r.status, 400, title);
      assert.equal(r.body.error.title, title);
    }
    const m = await as(ana, api().post('/api/orders')).send({ type: 'Refill', quantity: 2, address: { mode: 'typed', house: '12' } });
    assert.deepEqual(m.body.error.fields, ['street', 'barangay']);
  });

  test('only customers (and guests) order here; customers see only their own orders', async () => {
    const r = await as(staff, api().post('/api/orders')).send({ type: 'Refill', quantity: 1, address: typed });
    assert.equal(r.status, 403);
    assert.equal((await api().post('/api/orders').send({ type: 'Refill', quantity: 1, address: typed })).status, 401);
    assert.equal((await as(maria, api().get(`/api/orders/${first.id}`))).status, 404);
  });

  test('guest orders are kept for the guest phone only', async () => {
    const g = 'guest-' + 'a'.repeat(20);
    const r = await api().post('/api/orders').set('X-Guest-Token', g).send({ type: 'Refill', quantity: 2, phone: '09185550000', name: 'Liza', address: typed });
    assert.equal(r.status, 201);
    const mine = await api().get('/api/orders/home').set('X-Guest-Token', g);
    assert.equal(mine.body.active.length, 1);
    const other = await api().get('/api/orders/home').set('X-Guest-Token', 'guest-' + 'b'.repeat(20));
    assert.equal(other.body.active.length, 0);
    await api().post(`/api/orders/${r.body.order.id}/cancel`).set('X-Guest-Token', g);
  });
});

describe('Saved addresses (Customer 7)', () => {
  test('add (typed and pinned), edit, delete', async () => {
    const a = await as(ana, api().post('/api/addresses')).send({ name: 'Work', ...typed, house: '5', street: 'Mabuhay St.', blockLot: '' });
    assert.equal(a.status, 201);
    assert.equal(a.body.message, 'Address saved');
    assert.equal(a.body.address.text, '5 Mabuhay St., Commonwealth');
    const p = await as(ana, api().post('/api/addresses')).send({ name: "Aunt's house", mode: 'pin', lat: 14.69, lng: 121.1, barangay: 'Batasan Hills', landmark: 'near the plaza' });
    assert.equal(p.body.address.mode, 'pin');
    const e = await as(ana, api().put(`/api/addresses/${a.body.address.id}`)).send({ name: 'Office', ...typed });
    assert.equal(e.body.message, 'Address updated');
    assert.equal(e.body.address.name, 'Office');
    const d = await as(ana, api().delete(`/api/addresses/${p.body.address.id}`));
    assert.equal(d.body.message, 'Address deleted');
    const list = await as(ana, api().get('/api/addresses'));
    assert.deepEqual(list.body.addresses.map((x) => x.name), ['Home', 'Office']);
    assert.equal((await as(ana, api().post('/api/addresses')).send({ ...typed })).body.error.title, 'Name missing');
    assert.equal((await as(maria, api().delete(`/api/addresses/${a.body.address.id}`))).status, 404);
  });

  test('Quezon City barangays (142)', async () => {
    const r = await api().get('/api/geo/barangays');
    assert.equal(r.body.barangays.length, 142);
    assert.ok(r.body.barangays.includes('Commonwealth'));
  });
});

describe('Order Board, Accept and Decline (FR-04, FR-11; Admin Orders 1-4)', () => {
  test('New tab lists app orders oldest first with distance; counts per tab', async () => {
    const r = await as(owner, api().get('/api/admin/orders?view=new'));
    assert.equal(r.status, 200);
    assert.deepEqual(r.body.orders.map((o) => o.name), ['Maria Santos', 'Pedro Reyes', 'Ana Lim']);
    assert.equal(r.body.counts.new, 3);
    assert.ok(r.body.orders[0].km > 0);
    assert.equal(r.body.orders[0].sourceText, 'App');
    assert.equal((await as(staff, api().get('/api/admin/orders'))).status, 403);
  });

  test('accept one: 30 minutes after accepting, one rider, timeline and customer notified', async () => {
    setNow('2026-10-14T09:20:00+08:00');
    const riders = await as(owner, api().get('/api/admin/orders/riders'));
    const juan = riders.body.riders.find((x) => x.name === 'Juan Dela Cruz');
    assert.equal(riders.body.riders.at(-1).name, 'Me (Owner)');
    const list = await as(owner, api().get('/api/admin/orders?view=new'));
    const maria1 = list.body.orders[0];
    const r = await as(owner, api().post('/api/admin/orders/accept')).send({ ids: [maria1.id], riderId: juan.id });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.message, 'Accepted. Customer notified.');
    const d = await as(owner, api().get(`/api/admin/orders/${maria1.id}`));
    assert.equal(d.body.order.status, 'Processing');
    assert.equal(d.body.order.estText, 'by 9:50 AM');
    assert.equal(d.body.order.riderName, 'Juan Dela Cruz');
    assert.deepEqual(d.body.timeline.map((t) => [t.status, t.by, t.note]), [
      ['Waiting for order to be accepted', 'Maria', ''],
      ['Order accepted', 'Owner', 'Rider: Juan'],
      ['Processing', 'Owner', 'Delivery by 9:50 AM'],
    ]);
    const c = await as(maria, api().get(`/api/orders/${maria1.id}`));
    assert.equal(c.body.order.estText, 'by 9:50 AM');
    const n = await one("SELECT * FROM notifications WHERE notification_type = 'Order Accepted' ORDER BY notification_id DESC LIMIT 1");
    assert.equal(n.message, 'Your refill order is processing. Estimated delivery: by 9:50 AM.');
  });

  test('accept all at 11:40 AM: lunch rule 1:00 to 1:30 PM, same rider for all', async () => {
    setNow('2026-10-14T11:40:00+08:00');
    const list = await as(owner, api().get('/api/admin/orders?view=new'));
    const ids = list.body.orders.map((o) => o.id);
    assert.equal(ids.length, 2);
    const r = await as(owner, api().post('/api/admin/orders/accept')).send({ ids, riderId: 1 });
    assert.equal(r.body.message, '2 orders accepted');
    assert.equal(r.body.estText, '1:00 to 1:30 PM');
    const p = await as(owner, api().get('/api/admin/orders?view=processing'));
    assert.equal(p.body.counts.processing, 3);
    const mine = p.body.orders.find((o) => o.id === ids[0]);
    assert.equal(mine.riderName, 'Ervin P. Mangao');
    assert.equal(mine.riderRole, 'Owner');
    const again = await as(owner, api().post('/api/admin/orders/accept')).send({ ids, riderId: 1 });
    assert.equal(again.status, 409);
  });

  test('customer cannot cancel after it is accepted', async () => {
    const home = await as(ana, api().get('/api/orders/home'));
    const accepted = home.body.active.find((o) => o.status === 'Processing');
    const c = await as(ana, api().post(`/api/orders/${accepted.id}/cancel`));
    assert.equal(c.status, 409);
    assert.equal(c.body.error.title, 'Cannot cancel');
  });

  test('change rider only while Processing', async () => {
    const p = await as(owner, api().get('/api/admin/orders?view=processing'));
    const o = p.body.orders[0];
    const juan = await one("SELECT user_id FROM users WHERE full_name = 'Juan Dela Cruz'");
    const r = await as(owner, api().post(`/api/admin/orders/${o.id}/rider`)).send({ riderId: juan.user_id });
    assert.equal(r.body.message, 'Rider notified.');
    assert.equal(r.body.order.riderName, 'Juan Dela Cruz');
    await query("UPDATE orders SET status = 'Out for Delivery' WHERE order_id = ?", [o.id]);
    const locked = await as(owner, api().post(`/api/admin/orders/${o.id}/rider`)).send({ riderId: 1 });
    assert.equal(locked.body.error.title, 'Rider cannot be changed');
    await query("UPDATE orders SET status = 'Processing' WHERE order_id = ?", [o.id]);
  });

  test('decline with a reason (or Other); customer sees it; cancel by customer before accepting', async () => {
    setNow(null);
    const a = await as(maria, api().post('/api/orders')).send({ type: 'Refill', quantity: 2, address: typed });
    const b = await as(maria, api().post('/api/orders')).send({ type: 'Refill', quantity: 1, address: typed });
    const c = await as(maria, api().post('/api/orders')).send({ type: 'Refill', quantity: 1, address: typed });
    const d1 = await as(owner, api().post(`/api/admin/orders/${a.body.order.id}/decline`)).send({ reason: 'Run out of water' });
    assert.equal(d1.body.message, 'Declined. Customer sees the reason.');
    const seen = await as(maria, api().get(`/api/orders/${a.body.order.id}`));
    assert.equal(seen.body.order.status, 'Declined');
    assert.equal(seen.body.order.reason, 'Run out of water');
    const d2 = await as(owner, api().post(`/api/admin/orders/${b.body.order.id}/decline`)).send({ reason: 'Other', other: 'The station is closed for today.' });
    assert.equal(d2.body.order.reason, 'The station is closed for today.');
    assert.equal((await as(owner, api().post(`/api/admin/orders/${b.body.order.id}/decline`)).send({ reason: 'Closed' })).status, 409);
    assert.equal((await as(owner, api().post(`/api/admin/orders/${c.body.order.id}/decline`)).send({ reason: 'x' })).body.error.title, 'Choose reason');

    const x = await as(maria, api().post(`/api/orders/${c.body.order.id}/cancel`));
    assert.equal(x.body.message, 'Order cancelled; owner notified');
    const f = await as(owner, api().get('/api/admin/orders?view=declined'));
    assert.equal(f.body.orders.length, 2);
    const cc = await as(owner, api().get('/api/admin/orders?view=cancelled'));
    assert.ok(cc.body.orders.some((o) => o.id === c.body.order.id));
  });
});
