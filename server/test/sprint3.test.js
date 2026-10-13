// Sprint 3 (steps 33-42).
const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb, loginAs } = require('./helpers');
const { one, query } = require('../src/db');

let owner, staff, rider, ana;
before(async () => {
  await freshDb();
  owner = await loginAs('09170000001', 'owner123');
  staff = await loginAs('09170000002', 'staff123');
  rider = await loginAs('09170000003', 'rider123');
  ana = await loginAs('09172001111', 'ana123');
});
after(closeDb);
const as = (token, req) => req.set('Authorization', `Bearer ${token}`);
const typed = { mode: 'typed', house: '12', street: 'Sampaguita St.', barangay: 'Commonwealth' };
const GUEST = 'guest-' + 'c'.repeat(24);

describe('Guest mode (step 33)', () => {
  test('a guest must type a name; orders stay on the guest phone and move to the new account', async () => {
    const noName = await api().post('/api/orders').set('X-Guest-Token', GUEST).send({ type: 'Refill', quantity: 2, phone: '09185551212', address: typed });
    assert.equal(noName.body.error.title, 'Name missing');
    const r = await api().post('/api/orders').set('X-Guest-Token', GUEST).send({ type: 'Refill', quantity: 2, phone: '09185551212', name: 'Lito', address: typed });
    assert.equal(r.status, 201);
    const mine = await api().get('/api/orders').set('X-Guest-Token', GUEST);
    assert.equal(mine.body.orders[0].name, 'Lito');
    const s = await api().post('/api/auth/signup').set('X-Guest-Token', GUEST).send({
      name: 'Lito Reyes', phone: '09185551212', email: 'lito@gmail.com', password: 'lito123', confirm: 'lito123', consent: true,
    });
    assert.equal(s.status, 201);
    const moved = await api().get('/api/orders').set('Authorization', `Bearer ${s.body.token}`);
    assert.equal(moved.body.orders.length, 1);
    const left = await api().get('/api/orders').set('X-Guest-Token', GUEST);
    assert.equal(left.body.orders.length, 0);
  });
});

describe('Live location and live map (step 34)', () => {
  test('sharing starts at Out for Delivery, owner/staff see the rider and pins, the customer sees the rider, and it stops after the last order', async () => {
    const off = await as(rider, api().post('/api/rider/location')).send({ lat: 14.70, lng: 121.09 });
    assert.equal(off.body.sharing, false, 'nothing out yet');

    const juan = await one("SELECT user_id FROM users WHERE phone_number = '09170000003'");
    const maria = await one("SELECT order_id FROM orders WHERE contact_phone = '09171234567'");
    await as(owner, api().post('/api/admin/orders/accept')).send({ ids: [maria.order_id], riderId: juan.user_id });
    await as(staff, api().post('/api/work/out')).send({ ids: [maria.order_id] });

    const on = await as(rider, api().post('/api/rider/location')).send({ lat: 14.6901, lng: 121.0801 });
    assert.equal(on.body.sharing, true);

    const map = await as(staff, api().get('/api/map'));
    assert.equal(map.status, 200);
    assert.equal(map.body.riders.length, 1);
    assert.equal(map.body.riders[0].name, 'Juan Dela Cruz');
    assert.equal(map.body.riders[0].lat, 14.6901);
    assert.deepEqual(map.body.riders[0].orders, [maria.order_id]);
    assert.equal(map.body.orders[0].name, 'Maria Santos');
    assert.equal((await as(rider, api().get('/api/map'))).status, 403);

    const mariaToken = await loginAs('09171234567', 'maria123');
    const seen = await as(mariaToken, api().get(`/api/orders/${maria.order_id}`));
    assert.equal(seen.body.rider.lat, 14.6901);

    await as(rider, api().post(`/api/rider/orders/${maria.order_id}/delivered`)).send({ paid: true });
    const l = await one('SELECT is_sharing FROM rider_locations WHERE rider_id = ?', [juan.user_id]);
    assert.equal(l.is_sharing, 0, 'sharing off after the last order');
    const after = await as(mariaToken, api().get(`/api/orders/${maria.order_id}`));
    assert.equal(after.body.rider, null);
  });
});

describe('Real-time updates (step 35)', () => {
  test('owner and the customer get an "order" event when an order changes; the customer gets the notification', async () => {
    const http = require('http');
    const { io: connect } = require('socket.io-client');
    const realtime = require('../src/services/realtime');
    const server = http.createServer(require('../src/app'));
    realtime.attach(server);
    await new Promise((r) => server.listen(0, r));
    const url = `http://localhost:${server.address().port}`;
    const ownerSock = connect(url, { auth: { token: owner }, transports: ['websocket'] });
    const anaSock = connect(url, { auth: { token: ana }, transports: ['websocket'] });
    const bad = connect(url, { auth: {}, transports: ['websocket'] });
    try {
      await Promise.all([ownerSock, anaSock].map((s) => new Promise((r, j) => { s.on('connect', r); s.on('connect_error', j); })));
      const refused = await new Promise((r) => bad.on('connect_error', (e) => r(e.message)));
      assert.equal(refused, 'Please log in');

      const ownerGot = new Promise((r) => ownerSock.on('order', r));
      const anaGot = new Promise((r) => anaSock.on('order', r));
      const anaNote = new Promise((r) => anaSock.on('notification', r));
      const placed = await as(ana, api().post('/api/orders')).send({ type: 'Refill', quantity: 1, address: typed });
      const ev = await ownerGot;
      assert.equal(ev.id, placed.body.order.id);
      assert.equal(ev.status, 'New');
      assert.equal((await anaGot).id, placed.body.order.id);
      await as(owner, api().post(`/api/admin/orders/${placed.body.order.id}/decline`)).send({ reason: 'Closed' });
      const n = await anaNote;
      assert.equal(n.title, 'Order declined');
      assert.equal(n.message, 'Closed');
    } finally {
      for (const s of [ownerSock, anaSock, bad]) s.close();
      await new Promise((r) => server.close(r));
    }
  });
});
