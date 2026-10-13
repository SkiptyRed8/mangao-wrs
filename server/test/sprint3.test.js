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

describe('Export Report (step 39)', () => {
  const download = async (body) => {
    const r = await as(owner, api().post('/api/export')).send(body);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const f = await api().get(r.body.url).buffer(true).parse((res, cb) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => cb(null, Buffer.concat(chunks)));
    });
    return { r, f };
  };

  test('daily, weekly and unpaid as PDF and spreadsheet; the link is a short ticket', async () => {
    const d = await download({ report: 'daily', date: '2026-10-14', format: 'pdf' });
    assert.equal(d.r.body.fileName, 'Mangao-Daily-Sales-2026-10-14.pdf');
    assert.equal(d.f.headers['content-type'], 'application/pdf');
    assert.match(d.f.headers['content-disposition'], /attachment; filename="Mangao-Daily-Sales-2026-10-14.pdf"/);
    assert.equal(d.f.body.slice(0, 5).toString(), '%PDF-');

    const w = await download({ report: 'weekly', date: '2026-10-14', format: 'xlsx' });
    assert.equal(w.r.body.fileName, 'Mangao-Weekly-Sales-2026-10-12.xlsx');
    assert.equal(w.f.body.slice(0, 2).toString(), 'PK', 'xlsx is a zip');
    const ExcelJS = require('exceljs');
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.load(w.f.body);
    assert.deepEqual(wb.worksheets.map((s) => s.name), ['Summary', 'Day by day']);
    assert.equal(wb.getWorksheet('Day by day').rowCount, 8);

    const u = await download({ report: 'unpaid', format: 'pdf' });
    assert.match(u.r.body.fileName, /^Mangao-Unpaid-Accounts-\d{4}-\d{2}-\d{2}\.pdf$/);
    const ux = await download({ report: 'unpaid', format: 'xlsx' });
    const wb2 = new ExcelJS.Workbook();
    await wb2.xlsx.load(ux.f.body);
    assert.deepEqual(wb2.worksheets.map((s) => s.name), ['Summary', 'Customers', 'Unpaid orders']);
  });

  test('errors: no report, no format, future date, bad link, not the owner', async () => {
    assert.equal((await as(owner, api().post('/api/export')).send({ format: 'pdf' })).body.error.title, 'Choose a report');
    assert.equal((await as(owner, api().post('/api/export')).send({ report: 'daily' })).body.error.title, 'Choose a format');
    assert.equal((await as(owner, api().post('/api/export')).send({ report: 'daily', format: 'pdf', date: '2099-01-01' })).body.error.title, 'No sales yet');
    assert.equal((await api().get('/api/export/file?ticket=nope')).body.error.title, 'Link expired');
    assert.equal((await as(staff, api().post('/api/export')).send({ report: 'daily', format: 'pdf' })).status, 403);
  });
});

describe('Borrowed gallons (step 40)', () => {
  test('lend from an order and by name, part and full return, stock and movement history, timeline', async () => {
    const stock = async () => (await one("SELECT quantity_on_hand AS n FROM inventory_items WHERE item_name = 'New Gallon'")).n;
    const o = await one("SELECT order_id, customer_name FROM orders WHERE customer_name IS NOT NULL ORDER BY order_id LIMIT 1");
    const s0 = await stock();

    const lend = await as(staff, api().post('/api/loans')).send({ orderId: o.order_id, quantity: 3, note: 'Own gallons cracked' });
    assert.equal(lend.status, 201, JSON.stringify(lend.body));
    assert.equal(lend.body.loan.name, o.customer_name);
    assert.equal(lend.body.loan.lentBy, 'Joy Ramos');
    assert.equal(await stock(), s0 - 3);

    const walk = await as(owner, api().post('/api/loans')).send({ name: 'Mang Ben', phone: '0918 777 1234', quantity: 1 });
    assert.equal(walk.status, 201);
    assert.equal(walk.body.loan.phone, '09187771234');
    assert.equal(walk.body.loan.lentBy, 'Owner');

    assert.equal((await as(owner, api().post('/api/loans')).send({ quantity: 1 })).body.error.title, 'Customer name missing');
    assert.equal((await as(owner, api().post('/api/loans')).send({ name: 'X' })).body.error.title, 'Quantity missing');
    assert.equal((await as(owner, api().post('/api/loans')).send({ name: 'X', quantity: 100 })).body.error.title, 'Not enough new gallons');
    assert.equal((await as(rider, api().get('/api/loans'))).status, 403);

    const list = await as(owner, api().get('/api/loans'));
    assert.equal(list.body.gallonsOut, 4);
    assert.equal(list.body.customersOut, 2);
    const forOrder = await as(owner, api().get(`/api/loans?status=all&orderId=${o.order_id}`));
    assert.equal(forOrder.body.loans.length, 1);
    assert.equal((await as(owner, api().get('/api/loans?q=ben'))).body.loans.length, 1);

    // Part return: 2 of 3 come back.
    const part = await as(staff, api().post(`/api/loans/${lend.body.loan.id}/return`)).send({ quantity: 2 });
    assert.equal(part.body.message, '2 returned. 1 still borrowed.');
    assert.equal(await stock(), s0 - 3 - 1 + 2);
    const after = await as(owner, api().get(`/api/loans?status=all&orderId=${o.order_id}`));
    assert.deepEqual(after.body.loans.map((l) => [l.quantity, l.out]).sort(), [[1, true], [2, false]]);
    assert.equal((await as(owner, api().post(`/api/loans/${lend.body.loan.id}/return`)).send({ quantity: 5 })).body.error.title, 'Quantity not valid');

    // Return the rest (no quantity = all).
    const rest = await as(owner, api().post(`/api/loans/${lend.body.loan.id}/return`)).send({});
    assert.equal(rest.body.message, 'Returned. Stock goes up.');
    assert.equal((await as(owner, api().post(`/api/loans/${lend.body.loan.id}/return`)).send({})).body.error.title, 'Already returned');

    const moves = await as(owner, api().get('/api/inventory/movements?item=gallons'));
    const types = moves.body.movements.slice(0, 4).map((m) => m.type);
    assert.deepEqual(types.sort(), ['Lent', 'Lent', 'Returned', 'Returned']);
    const tl = await as(owner, api().get(`/api/admin/orders/${o.order_id}`));
    const steps = tl.body.timeline.map((t) => t.status);
    assert.ok(steps.includes('Gallon lent') && steps.includes('Gallon returned'));
  });
});

describe('Damaged gallon report (step 41)', () => {
  const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
  test('rider sends photo and note; new gallon -1, timeline, owner alerted, photo served', async () => {
    const juan = await one("SELECT user_id FROM users WHERE phone_number = '09170000003'");
    const o = await one('SELECT order_id, customer_name FROM orders WHERE rider_id = ? ORDER BY order_id LIMIT 1', [juan.user_id]);
    const other = await one('SELECT order_id FROM orders WHERE rider_id IS NULL OR rider_id <> ? ORDER BY order_id LIMIT 1', [juan.user_id]);
    const stock = async () => (await one("SELECT quantity_on_hand AS n FROM inventory_items WHERE item_name = 'New Gallon'")).n;
    const s0 = await stock();

    assert.equal((await as(rider, api().post('/api/damage')).send({ orderId: o.order_id, note: 'Cracked' })).body.error.title, 'Photo missing');
    assert.equal((await as(rider, api().post('/api/damage')).send({ orderId: o.order_id, photo: 'aGVsbG8=', note: 'x' })).body.error.title, 'Photo not valid');
    assert.equal((await as(rider, api().post('/api/damage')).send({ orderId: o.order_id, photo: PNG })).body.error.title, 'Note missing');
    assert.equal((await as(rider, api().post('/api/damage')).send({ orderId: other.order_id, photo: PNG, note: 'x' })).status, 403);

    const r = await as(rider, api().post('/api/damage')).send({ orderId: o.order_id, photo: PNG, note: 'Cracked at the handle' });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.equal(r.body.message, 'Sent to the owner. A new gallon replaces it.');
    assert.equal(r.body.report.by, 'Juan Dela Cruz');
    assert.equal(await stock(), s0 - 1);

    const img = await api().get(r.body.report.photo);
    assert.equal(img.status, 200);
    assert.match(img.headers['content-type'], /image\/png/);

    const moves = await as(owner, api().get('/api/inventory/movements?item=gallons'));
    assert.equal(moves.body.movements[0].label, 'Damaged customer gallon replaced');
    const tl = await as(owner, api().get(`/api/admin/orders/${o.order_id}`));
    assert.ok(tl.body.timeline.some((t) => t.status === 'Damaged gallon' && t.note.startsWith('Cracked at the handle')));
    const n = await as(owner, api().get('/api/notifications'));
    assert.equal(n.body.items[0].title, 'Damaged gallon');

    const list = await as(staff, api().get(`/api/damage?orderId=${o.order_id}`));
    assert.equal(list.body.reports.length, 1);
    assert.equal((await as(staff, api().get('/api/damage'))).status, 403);
    const mine = await as(owner, api().post('/api/damage')).send({ orderId: o.order_id, photo: PNG, note: 'Leaking' });
    assert.equal(mine.body.message, 'Saved. A new gallon replaces it.');
  });
});

describe('Customers list and records (step 42)', () => {
  test('list with accounts and logged customers, search, and a full profile', async () => {
    const list = await as(owner, api().get('/api/customers'));
    assert.equal(list.status, 200);
    const ana = await one("SELECT user_id FROM users WHERE phone_number = '09172001111'");
    const row = list.body.customers.find((c) => c.key === `u${ana.user_id}`);
    assert.equal(row.name, 'Ana Lim');
    assert.equal(row.account, true);
    assert.ok(row.orders >= 2, 'app order and the order logged with her phone');
    assert.ok(list.body.customers.find((c) => c.key === 'p09185550000' && c.name === 'Pedro Cruz' && c.owed === 105));
    const ben = list.body.customers.find((c) => c.name === 'Mang Ben');
    assert.equal(ben.borrowed, 1, 'Mang Ben still has 1 gallon out (step 40 test)');
    assert.ok(!list.body.customers.some((c) => c.key === 'n'), 'walk-ins without a name are left out');

    const s = await as(owner, api().get('/api/customers?q=0918 555 0000'));
    assert.deepEqual(s.body.customers.map((c) => c.name), ['Pedro Cruz']);

    const p = await as(owner, api().get(`/api/customers/u${ana.user_id}`));
    assert.equal(p.status, 200);
    assert.equal(p.body.customer.name, 'Ana Lim');
    assert.equal(p.body.customer.email, 'ana@example.com');
    assert.ok(p.body.orders.length >= 2);
    assert.ok(Array.isArray(p.body.addresses));
    assert.equal(typeof p.body.unpaid.owed, 'number');
    assert.equal(typeof p.body.stats.gallons, 'number');

    const ped = await as(owner, api().get('/api/customers/p09185550000'));
    assert.equal(ped.body.unpaid.owed, 105);
    assert.equal(ped.body.customer.account, false);

    assert.equal((await as(owner, api().get('/api/customers/pnobody'))).status, 404);
    assert.equal((await as(staff, api().get('/api/customers'))).status, 403);
  });
});
