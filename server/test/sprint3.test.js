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

describe('Push notifications and alert preferences (step 36)', () => {
  test('owner turns an alert off and on; phones register for push', async () => {
    const list = await as(owner, api().get('/api/notifications/preferences'));
    assert.equal(list.status, 200);
    assert.deepEqual(list.body.items.slice(0, 1), [{ type: 'New Order', label: 'New orders', enabled: true }]);
    assert.equal(list.body.push, false, 'Firebase not set up in tests');
    assert.equal((await as(staff, api().get('/api/notifications/preferences'))).status, 403);

    const off = await as(owner, api().put('/api/notifications/preferences')).send({ type: 'New Order', enabled: false });
    assert.equal(off.body.message, 'Saved. Takes effect right away.');
    const before = await one("SELECT COUNT(*) AS n FROM notifications WHERE user_id = 1 AND notification_type = 'New Order'");
    await as(ana, api().post('/api/orders')).send({ type: 'Refill', quantity: 1, address: typed });
    const after = await one("SELECT COUNT(*) AS n FROM notifications WHERE user_id = 1 AND notification_type = 'New Order'");
    assert.equal(after.n, before.n, 'no alert while turned off');
    await as(owner, api().put('/api/notifications/preferences')).send({ type: 'New Order', enabled: true });
    await as(ana, api().post('/api/orders')).send({ type: 'Refill', quantity: 1, address: typed });
    const again = await one("SELECT COUNT(*) AS n FROM notifications WHERE user_id = 1 AND notification_type = 'New Order'");
    assert.equal(again.n, after.n + 1);

    const dev = await as(ana, api().post('/api/notifications/device')).send({ token: 'fcm-token-'.padEnd(40, 'x'), platform: 'android' });
    assert.equal(dev.body.ok, true);
    const g = await api().post('/api/notifications/device').set('X-Guest-Token', GUEST).send({ token: 'fcm-guest-'.padEnd(40, 'y') });
    assert.equal(g.body.ok, true);
    const rows = await query('SELECT user_id, guest_token FROM device_tokens ORDER BY token_id');
    assert.equal(rows.length, 2);
    assert.equal(rows[1].guest_token, GUEST);
  });
});

describe('Weekly Sales Report (step 37)', () => {
  test('7 days from Monday, totals, and compared with last week', async () => {
    const { query: q } = require('../src/db');
    const add = (paidAt, total, qty) =>
      q(
        `INSERT INTO orders (order_source, order_type, customer_name, contact_phone, quantity, unit_price, total_amount, status, payment_method, payment_status, paid_at, delivered_at, tank_counted_at, created_at)
         VALUES ('Logged','Refill','Weekly Test','09180000000',?,35,?,'Delivered','COD','Paid',?,?,?,?)`,
        [qty, total, paidAt, paidAt, paidAt, paidAt]
      );
    // Wednesday Oct 7, 2026 (last week) and Wednesday Oct 14, 2026 (this week), 10:00 Philippine time.
    await add(new Date('2026-10-07T10:00:00+08:00'), 70, 2);
    await add(new Date('2026-10-14T10:00:00+08:00'), 140, 4);
    const time = require('../src/services/time');
    time.setNow(new Date('2026-10-15T09:00:00+08:00'));
    try {
      const r = await as(owner, api().get('/api/sales/weekly?start=2026-10-14'));
      assert.equal(r.status, 200);
      assert.equal(r.body.start, '2026-10-12', 'Monday of that week');
      assert.equal(r.body.end, '2026-10-18');
      assert.equal(r.body.days.length, 7);
      assert.equal(r.body.days[0].day, 'Mon');
      const wed = r.body.days[2];
      assert.equal(wed.date, '2026-10-14');
      assert.ok(wed.moneyEarned >= 140);
      assert.equal(r.body.days[4].future, true, 'Friday is after today');
      assert.ok(r.body.lastWeek.moneyEarned >= 70);
      assert.equal(typeof r.body.change.moneyEarned === 'number' || r.body.change.moneyEarned === null, true);
      const future = await as(owner, api().get('/api/sales/weekly?start=2026-10-26'));
      assert.equal(future.body.error.title, 'No sales yet');
      assert.equal((await as(staff, api().get('/api/sales/weekly'))).status, 403);
    } finally {
      time.setNow(null);
    }
  });
});

describe('Unpaid Accounts (step 38)', () => {
  test('unpaid orders grouped per customer (account + same phone), search, detail, and Paid lowers the total', async () => {
    const { query: q } = require('../src/db');
    const ana1 = await one("SELECT user_id FROM users WHERE phone_number = '09172001111'");
    const add = (cust, name, phone, total, src = 'Logged') =>
      q(
        `INSERT INTO orders (order_source, order_type, customer_id, customer_name, contact_phone, quantity, unit_price, total_amount, status, payment_method, payment_status, delivered_at)
         VALUES (?,'Refill',?,?,?,1,35,?,?,?, 'Unpaid', NOW())`,
        [src, cust, name, phone, total, src === 'Walk-in' ? 'Recorded' : 'Delivered', src === 'Walk-in' ? 'Walk-in' : 'COD']
      );
    await add(ana1.user_id, 'Ana Lim', '09172001111', 70, 'App');
    await add(null, 'Ana', '09172001111', 35); // logged by phone: same account
    await add(null, 'Pedro Cruz', '09185550000', 105);
    await add(null, 'Aling Nena', '', 30, 'Walk-in');

    const list = await as(owner, api().get('/api/sales/unpaid'));
    assert.equal(list.status, 200);
    const anaRow = list.body.customers.find((c) => c.key === `u${ana1.user_id}`);
    assert.equal(anaRow.orders, 2);
    assert.equal(anaRow.owed, 105);
    assert.equal(anaRow.name, 'Ana Lim');
    assert.ok(list.body.customers.find((c) => c.key === 'p09185550000'));
    assert.ok(list.body.customers.find((c) => c.name === 'Aling Nena'));
    assert.ok(list.body.total >= 240);

    const search = await as(owner, api().get('/api/sales/unpaid?q=pedro'));
    assert.equal(search.body.customers.length, 1);
    assert.equal(search.body.customers[0].phone, '09185550000');
    const byPhone = await as(owner, api().get('/api/sales/unpaid?q=0918 555'));
    assert.equal(byPhone.body.customers[0].name, 'Pedro Cruz');

    // A phone key of an account opens the account.
    const det = await as(owner, api().get('/api/sales/unpaid/p09172001111'));
    assert.equal(det.body.customer.key, `u${ana1.user_id}`);
    assert.equal(det.body.orders.length, 2);
    assert.equal(det.body.owed, 105);

    await as(owner, api().post(`/api/admin/orders/${det.body.orders[0].id}/paid`));
    const after = await as(owner, api().get(`/api/sales/unpaid/u${ana1.user_id}`));
    assert.equal(after.body.orders.length, 1);
    assert.equal(after.body.owed, 35);

    assert.equal((await as(owner, api().get('/api/sales/unpaid/pnobody'))).status, 404);
    assert.equal((await as(staff, api().get('/api/sales/unpaid'))).status, 403);
  });
});
