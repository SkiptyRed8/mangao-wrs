// Step 43: one full business day through every role, checking that the numbers agree everywhere
// (tank counter, seals, new gallons, daily and weekly sales, unpaid accounts, customers, alerts).
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb, loginAs } = require('./helpers');
const { one } = require('../src/db');

let owner, staff, rider;
before(async () => {
  await freshDb();
  owner = await loginAs('09170000001', 'owner123');
  staff = await loginAs('09170000002', 'staff123');
  rider = await loginAs('09170000003', 'rider123');
});
after(closeDb);

const as = (token, req) => req.set('Authorization', `Bearer ${token}`);
const GUEST = 'guest-' + 'f'.repeat(24);
const typed = { mode: 'typed', house: '7', street: 'Kalayaan St.', barangay: 'Commonwealth' };
const stock = async (name) => (await one('SELECT quantity_on_hand AS n FROM inventory_items WHERE item_name = ?', [name])).n;
const ok = (r, status = 200) => {
  assert.equal(r.status, status, `${r.req && r.req.method} ${r.req && r.req.path}: ${JSON.stringify(r.body)}`);
  return r.body;
};

test('a full day: customers, owner, staff and rider; every total agrees', async () => {
  // ---- Owner: settings for the day
  ok(await as(owner, api().put('/api/settings/tank-limit')).send({ tankLimit: 10 }));
  const prices = ok(await api().get('/api/settings/prices')).prices;
  assert.deepEqual([prices.walkIn, prices.delivery, prices.package], [30, 35, 150]);
  const seals0 = await stock('Seal');
  const gallons0 = await stock('New Gallon');

  // ---- Customers: a new account and a guest order; a third order is cancelled before it is accepted
  const carla = ok(
    await api().post('/api/auth/signup').send({
      name: 'Carla Diaz', phone: '0918 400 5000', email: 'carla@example.com', password: 'carla123', confirm: 'carla123', consent: true,
    }),
    201
  ).token;
  const c1 = ok(await as(carla, api().post('/api/orders')).send({ type: 'Refill', quantity: 4, phone: '09184005000', address: typed }), 201);
  const g1 = ok(
    await api().post('/api/orders').set('X-Guest-Token', GUEST).send({ type: 'Package', quantity: 1, phone: '09185556666', name: 'Tess', address: typed }),
    201
  );
  const c2 = ok(await as(carla, api().post('/api/orders')).send({ type: 'Refill', quantity: 1, phone: '09184005000', address: typed }), 201);
  const cancelled = ok(await as(carla, api().post(`/api/orders/${c2.order.id}/cancel`)));
  assert.equal(cancelled.order.status, 'Cancelled');

  // Owner gets "New order" alerts and sees the orders on the board.
  const bell = ok(await as(owner, api().get('/api/notifications')));
  assert.ok(bell.items.filter((n) => n.type === 'New Order').length >= 2);
  const board = ok(await as(owner, api().get('/api/admin/orders?view=new')));
  const juan = await one("SELECT user_id FROM users WHERE phone_number = '09170000003'");

  // ---- Owner: accept Carla and Tess (rider Juan); decline the demo order of Pedro
  ok(await as(owner, api().post('/api/admin/orders/accept')).send({ ids: [c1.order.id, g1.order.id], riderId: juan.user_id }));
  const pedro = board.orders.find((o) => o.name === 'Pedro Reyes');
  ok(await as(owner, api().post(`/api/admin/orders/${pedro.id}/decline`)).send({ reason: 'Closed' }));
  const late = await as(carla, api().post(`/api/orders/${c1.order.id}/cancel`));
  assert.ok(late.status >= 400, 'cannot cancel after accept');
  const guestNote = ok(await api().get('/api/notifications').set('X-Guest-Token', GUEST));
  assert.match(guestNote.items[0].message, /package order is processing/);

  // ---- Staff: a phone order (rider Owner) and two walk-ins (one unpaid)
  const logged = ok(
    await as(staff, api().post('/api/work/delivery')).send({
      name: 'Mang Lito', phone: '0917 888 1111', address: '3 Mapagkawanggawa St.', quantity: 2, channel: 'Call',
    }),
    201
  );
  ok(await as(staff, api().post('/api/work/walk-in')).send({ quantity: 3, type: 'Refill', paid: true }), 201);
  ok(await as(staff, api().post('/api/work/walk-in')).send({ quantity: 1, type: 'Refill', paid: false, name: 'Aling Rosa' }), 201);

  // ---- Staff sends out everything in Processing: one batch per rider
  const todo = ok(await as(staff, api().get('/api/work/todo')));
  const ids = todo.processing.map((o) => o.id).sort();
  assert.deepEqual(ids, [c1.order.id, g1.order.id, logged.order.id].sort());
  const out = ok(await as(staff, api().post('/api/work/out')).send({ ids }));
  assert.equal(out.batches.length, 2, 'Juan and the owner');

  // Tank: 3 + 1 walk-ins + 4 + 1 + 2 = 11 gallons; limit 10 -> one "Tank" alert. Seals 3 per gallon, 1 new gallon per package.
  const tank = ok(await as(staff, api().get('/api/work/tank')));
  assert.equal(tank.count, 11);
  assert.equal(tank.alert, true);
  assert.equal(await stock('Seal'), seals0 - 33);
  assert.equal(await stock('New Gallon'), gallons0 - 1);
  const ownerBell = ok(await as(owner, api().get('/api/notifications')));
  assert.equal(ownerBell.items.filter((n) => n.type === 'Tank').length, 1);

  // ---- Rider: Carla paid, Tess unpaid
  ok(await as(rider, api().post('/api/rider/location')).send({ lat: 14.69, lng: 121.08 }));
  ok(await as(rider, api().post(`/api/rider/orders/${c1.order.id}/delivered`)).send({ paid: true }));
  ok(await as(rider, api().post(`/api/rider/orders/${g1.order.id}/delivered`)).send({ paid: false }));
  assert.equal(ok(await as(rider, api().get('/api/rider/deliveries'))).orders.length, 0);

  // ---- Owner delivers the phone order: not home, then re-delivered (tank not counted twice) and paid
  ok(await as(owner, api().post(`/api/admin/orders/${logged.order.id}/not-delivered`)).send({ note: 'Not home' }));
  ok(await as(owner, api().post(`/api/admin/orders/${logged.order.id}/redeliver`)));
  ok(await as(owner, api().post('/api/work/out')).send({ ids: [logged.order.id] }));
  assert.equal(ok(await as(owner, api().get('/api/work/tank'))).count, 11, 'not counted again');
  ok(await as(owner, api().post(`/api/admin/orders/${logged.order.id}/delivered`)).send({ paid: true }));

  // ---- Daily report: paid = 140 (Carla) + 90 (walk-in) + 70 (Lito) = 300; unpaid = 150 (Tess) + 30 (Rosa)
  const d = ok(await as(owner, api().get('/api/sales/daily')));
  assert.equal(d.summary.moneyEarned, 300);
  assert.equal(d.summary.unpaid, 180);
  assert.equal(d.summary.gallons, 11);
  assert.equal(d.summary.packages, 1);
  assert.equal(d.summary.walkInGallons, 4);
  assert.equal(d.summary.deliveryGallons, 7);
  assert.equal(d.summary.riderPaid, 210, 'Carla 140 + Lito 70 collected on delivery');
  assert.equal(d.orders.length, 5);

  // Weekly report has the same totals for today.
  const w = ok(await as(owner, api().get('/api/sales/weekly')));
  const todayRow = w.days.find((x) => x.date === d.date);
  assert.equal(todayRow.moneyEarned, 300);
  assert.equal(w.totals.moneyEarned, 300);

  // Unpaid accounts: Tess 150, Aling Rosa 30. Owner marks Tess paid -> money earned 450, unpaid 30.
  const u = ok(await as(owner, api().get('/api/sales/unpaid')));
  assert.equal(u.total, 180);
  const tess = u.customers.find((c) => c.name === 'Tess');
  assert.equal(tess.owed, 150);
  ok(await as(owner, api().post(`/api/admin/orders/${g1.order.id}/paid`)));
  const d2 = ok(await as(owner, api().get('/api/sales/daily')));
  assert.equal(d2.summary.moneyEarned, 450);
  assert.equal(d2.summary.unpaid, 30);
  assert.equal(ok(await as(owner, api().get('/api/sales/unpaid'))).total, 30);

  // Owner Home agrees with the daily report; the tank is refilled and the counter starts again.
  const home = ok(await as(owner, api().get('/api/admin/home')));
  assert.equal(home.today.moneyEarned, 450);
  assert.equal(home.tank.alert, true);
  ok(await as(owner, api().post('/api/work/tank/reset')));
  assert.equal(ok(await as(staff, api().get('/api/work/tank'))).count, 0);

  // Customer side: Carla's order history and alerts; the guest still sees her order.
  const mine = ok(await as(carla, api().get('/api/orders')));
  assert.deepEqual(mine.orders.map((o) => o.status).sort(), ['Cancelled', 'Delivered']);
  const carlaBell = ok(await as(carla, api().get('/api/notifications')));
  const titles = carlaBell.items.map((n) => n.title);
  for (const t of ['Order accepted', 'Out for delivery', 'Delivered']) assert.ok(titles.includes(t), `Carla got "${t}"`);
  assert.equal(ok(await api().get('/api/orders').set('X-Guest-Token', GUEST)).orders.length, 1);

  // Customers list and profile; Done Today for staff and rider.
  const list = ok(await as(owner, api().get('/api/customers?q=carla')));
  assert.equal(list.customers.length, 1);
  const profile = ok(await as(owner, api().get(`/api/customers/${list.customers[0].key}`)));
  assert.equal(profile.stats.gallons, 4);
  assert.equal(profile.stats.spent, 140);
  const staffDone = ok(await as(staff, api().get('/api/work/done-today')));
  assert.ok(staffDone.gallons >= 4);
  const riderDone = ok(await as(rider, api().get('/api/rider/done-today')));
  assert.equal(riderDone.delivered, 2);

  // Export of the day works.
  const ex = ok(await as(owner, api().post('/api/export')).send({ report: 'daily', format: 'pdf' }));
  assert.equal((await api().get(ex.url)).status, 200);

  // Roles stay in their lanes.
  assert.equal((await as(staff, api().get('/api/sales/daily'))).status, 403);
  assert.equal((await as(rider, api().get('/api/admin/orders'))).status, 403);
  assert.equal((await as(carla, api().get('/api/work/todo'))).status, 403);
  assert.equal((await as(rider, api().post('/api/work/tank/reset'))).status, 403);
});
