// Oct 20 additions: delivery date chosen by the customer, 15-minute reminder and 30-minute cancel of
// orders nobody accepted, "arriving" / "has arrived" messages, order date and time in notifications.
const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb, loginAs, setNow, API_URL } = require('./helpers');
const { one, query } = require('../src/db');

let ana, owner, staff, rider;
before(async () => {
  await freshDb();
  ana = await loginAs('09172001111', 'ana123');
  owner = await loginAs('09170000001', 'owner123');
  staff = await loginAs('09170000002', 'staff123');
  rider = await loginAs('09170000003', 'rider123');
});
after(async () => {
  setNow(null);
  await closeDb();
});
const as = (token, req) => req.set('Authorization', `Bearer ${token}`);
const pin = { mode: 'pin', lat: 14.6976, lng: 121.0886, street: 'Malaya St.', barangay: 'Commonwealth' };
const place = (body) => as(ana, api().post('/api/orders')).send({ type: 'Refill', quantity: 2, address: pin, ...body });
const sweep = () => api().post('/__test/sweep').send({});

describe('Delivery date chosen by the customer', () => {
  test('a later day is saved, shown, and gives that day\'s delivery hours when accepted', async () => {
    if (!API_URL) return;
    setNow('2026-10-20T09:00:00+08:00');
    const r = await place({ deliveryDate: '2026-10-22' });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.equal(r.body.order.deliveryDate, '2026-10-22');
    assert.equal(r.body.order.createdText, 'Oct 20, 9:00 AM');
    const n = await one("SELECT message FROM notifications WHERE order_id = ? AND notification_type = 'New Order' LIMIT 1", [r.body.order.id]);
    assert.equal(n.message, 'Ana Lim: 2 gallons · Refill · ordered Oct 20, 9:00 AM · deliver on Oct 22');

    const juan = await one("SELECT user_id FROM users WHERE phone_number = '09170000003'");
    const a = await as(owner, api().post('/api/admin/orders/accept')).send({ ids: [r.body.order.id], riderId: juan.user_id });
    assert.equal(a.status, 200, JSON.stringify(a.body));
    const o = await as(ana, api().get(`/api/orders/${r.body.order.id}`));
    assert.equal(o.body.order.estText, 'Oct 22, 7:30 AM to 6:00 PM');
  });

  test('today means as soon as possible; past or too far ahead is refused', async () => {
    if (!API_URL) return;
    setNow('2026-10-20T09:05:00+08:00');
    const today = await place({ deliveryDate: '2026-10-20' });
    assert.equal(today.status, 201);
    assert.equal(today.body.order.deliveryDate, null);
    for (const d of ['2026-10-19', '2026-10-28', 'next week']) {
      const bad = await place({ deliveryDate: d });
      assert.equal(bad.status, 400, d);
      assert.equal(bad.body.error.title, 'Delivery date not valid');
    }
  });
});

describe('Orders nobody accepted', () => {
  test('reminder to the owner after 15 minutes, cancelled with a polite message after 30', async () => {
    if (!API_URL) return;
    setNow('2026-10-21T10:00:00+08:00');
    const r = await place({});
    const id = r.body.order.id;

    setNow('2026-10-21T10:10:00+08:00');
    await sweep();
    assert.equal(await one("SELECT notification_id FROM notifications WHERE order_id = ? AND notification_type = 'Order Reminder'", [id]), null, 'no reminder before 15 minutes');

    setNow('2026-10-21T10:16:00+08:00');
    await sweep();
    await sweep(); // only one reminder
    const rem = await query("SELECT title, message FROM notifications WHERE order_id = ? AND notification_type = 'Order Reminder'", [id]);
    assert.equal(rem.length, 1);
    assert.equal(rem[0].title, 'Order still waiting');
    assert.match(rem[0].message, /^Owner, you have not accepted Ana Lim's order yet \(2 gallons · Refill, ordered Oct 21, 10:00 AM\)\. Accept or decline it by 10:30 AM/);
    assert.equal((await one('SELECT status FROM orders WHERE order_id = ?', [id])).status, 'New');

    setNow('2026-10-21T10:31:00+08:00');
    await sweep();
    assert.equal((await one('SELECT status FROM orders WHERE order_id = ?', [id])).status, 'Cancelled');
    const told = await one("SELECT title, message FROM notifications WHERE order_id = ? AND notification_type = 'Cancelled' AND user_id = (SELECT user_id FROM users WHERE phone_number = '09172001111')", [id]);
    assert.equal(told.title, 'Order cancelled');
    assert.match(told.message, /^We're sorry, the station is very busy/);
    const mine = await as(ana, api().get(`/api/orders/${id}`));
    assert.equal(mine.body.order.status, 'Cancelled');
    assert.equal(mine.body.order.reason, 'Not accepted within 30 minutes');
  });
});

describe('Rider arriving and arrived', () => {
  test('the customer is told once when the rider is near and once at the door', async () => {
    if (!API_URL) return;
    setNow(null);
    const juan = await one("SELECT user_id FROM users WHERE phone_number = '09170000003'");
    const r = await place({});
    const id = r.body.order.id;
    await as(owner, api().post('/api/admin/orders/accept')).send({ ids: [id], riderId: juan.user_id });
    await as(staff, api().post('/api/work/out')).send({ ids: [id] });

    await as(rider, api().post('/api/rider/location')).send({ lat: 14.6990, lng: 121.0886 }); // about 155 m away
    await as(rider, api().post('/api/rider/location')).send({ lat: 14.6985, lng: 121.0886 });
    const near = await query("SELECT title, message FROM notifications WHERE order_id = ? AND notification_type = 'Rider Arriving'", [id]);
    assert.equal(near.length, 1);
    assert.equal(near[0].message, 'Your rider is almost there. Please prepare ₱70.00.');
    // The status moves on by itself: Out for Delivery -> Arriving.
    let o = await as(ana, api().get(`/api/orders/${id}`));
    assert.equal(o.body.order.status, 'Out for Delivery');
    assert.equal(o.body.order.arrival, 'Arriving');
    assert.ok(o.body.timeline.some((s) => s.status === 'Arriving'));

    await as(rider, api().post('/api/rider/location')).send({ lat: 14.6977, lng: 121.0886 }); // about 11 m
    const here = await query("SELECT title FROM notifications WHERE order_id = ? AND notification_type = 'Rider Arrived'", [id]);
    assert.equal(here.length, 1);
    assert.equal(here[0].title, 'Your rider has arrived');

    o = await as(ana, api().get(`/api/orders/${id}`));
    assert.equal(typeof o.body.otherStops, 'number');
    assert.equal(o.body.order.arrival, 'Arrived');
    assert.ok(o.body.timeline.some((s) => s.status === 'Arrived'));
    const board = await as(owner, api().get('/api/map'));
    assert.equal(board.body.orders.find((x) => x.id === id).arrival, 'Arrived');

    // Delivered ends the trip; the arrival step is no longer shown.
    await as(rider, api().post(`/api/rider/orders/${id}/delivered`)).send({ paid: true });
    o = await as(ana, api().get(`/api/orders/${id}`));
    assert.equal(o.body.order.status, 'Delivered');
    assert.equal(o.body.order.arrival, null);
  });

  test('the "other orders on this trip" note counts only other customers', async () => {
    if (!API_URL) return;
    setNow(null);
    const juan = await one("SELECT user_id FROM users WHERE phone_number = '09170000003'");
    const a = (await place({})).body.order.id;
    const b = (await place({ quantity: 3 })).body.order.id;
    await as(owner, api().post('/api/admin/orders/accept')).send({ ids: [a, b], riderId: juan.user_id });
    await as(staff, api().post('/api/work/out')).send({ ids: [a, b] });
    const o = await as(ana, api().get(`/api/orders/${a}`));
    assert.equal(o.body.otherStops, 0, 'both orders are Ana\'s');
    for (const id of [a, b]) await as(rider, api().post(`/api/rider/orders/${id}/delivered`)).send({ paid: true });
  });
});
