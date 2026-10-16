const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb, loginAs, setNow } = require('./helpers');
const { one, query } = require('../src/db');

let owner, staff, juan, maria;
before(async () => {
  await freshDb();
  owner = await loginAs('09170000001', 'owner123');
  staff = await loginAs('09170000002', 'staff123');
  juan = await loginAs('09170000003', 'rider123');
  maria = await loginAs('09171234567', 'maria123');
});
after(async () => {
  setNow(null);
  await closeDb();
});
const as = (t, r) => r.set('Authorization', `Bearer ${t}`);
const stock = async (name) => (await one('SELECT quantity_on_hand AS q FROM inventory_items WHERE item_name = ?', [name])).q;
const tank = async () => (await as(owner, api().get('/api/work/tank'))).body;
/** Today (Philippine date) at a clock time, e.g. todayAt('09:45'). */
function todayAt(hm) {
  const p = new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 10);
  return `${p}T${hm}:00+08:00`;
}

describe('Log Walk-in (FR-03; Admin Home 5, Staff 10)', () => {
  test('2 gallons refill, Paid: P30 each, tank +2, seals -6, no status steps', async () => {
    const r = await as(staff, api().post('/api/work/walk-in')).send({ quantity: 2, type: 'Refill', paid: true });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.equal(r.body.total, 60);
    assert.equal(r.body.message, 'Walk-in saved: 2 gallons, Paid');
    assert.equal((await tank()).count, 2);
    assert.equal(await stock('Seal'), 414);
    const o = await one('SELECT * FROM orders WHERE order_id = ?', [r.body.id]);
    assert.equal(o.status, 'Recorded');
    assert.equal(o.payment_status, 'Paid');
  });

  test('package, Unpaid, with a name: P150 and 1 new gallon used', async () => {
    const r = await as(owner, api().post('/api/work/walk-in')).send({ quantity: 1, type: 'Package', paid: false, name: 'Aling Rosa' });
    assert.equal(r.body.total, 150);
    assert.equal(r.body.message, 'Walk-in saved: 1 gallon, Unpaid');
    assert.equal(await stock('New Gallon'), 23);
    assert.equal(await stock('Seal'), 411);
  });

  test('quantity missing; riders and customers cannot log', async () => {
    const r = await as(staff, api().post('/api/work/walk-in')).send({ quantity: 0 });
    assert.equal(r.body.error.title, 'Quantity missing');
    assert.equal((await as(juan, api().post('/api/work/walk-in')).send({ quantity: 1 })).status, 403);
    assert.equal((await as(maria, api().post('/api/work/walk-in')).send({ quantity: 1 })).status, 403);
  });
});

let ben, mila, mariaOrder;
describe('Log Delivery Order (FR-03; Admin Home 5A, Staff 4)', () => {
  test('call order goes straight to Processing with the owner as rider; owner told when staff logs it', async () => {
    setNow(todayAt('09:45'));
    const r = await as(staff, api().post('/api/work/delivery')).send({
      name: 'Ben Cruz', phone: '0918 555 2211', address: '5 Sampaguita St., Batasan Hills', quantity: 2, type: 'Refill', channel: 'Call', payment: 'Pay on delivery',
    });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    ben = r.body.order;
    assert.equal(ben.status, 'Processing');
    assert.equal(ben.total, 70);
    assert.equal(ben.sourceText, 'Call');
    assert.equal(ben.riderRole, 'Owner');
    assert.equal(ben.estText, 'by 10:15 AM');
    assert.equal(r.body.message, 'Order saved');
    const n = await one("SELECT * FROM notifications WHERE notification_type = 'Logged Order' ORDER BY notification_id DESC LIMIT 1");
    assert.equal(n.message, 'Joy: Ben Cruz, 2 gallons · Call');
    assert.equal((await tank()).count, 3, 'logged orders count only when sent out');
  });

  test('paid at station; missing fields message', async () => {
    const r = await as(owner, api().post('/api/work/delivery')).send({
      name: 'Mila Torres', phone: '09175550000', address: '8 Ilang-Ilang St., Holy Spirit', quantity: 2, channel: 'Walk-in', payment: 'Paid at station',
    });
    mila = r.body.order;
    assert.equal(mila.paymentStatus, 'Paid');
    assert.equal(mila.payment, 'Paid at station');
    assert.equal(mila.sourceText, 'Walk-in for delivery');
    const m = await as(staff, api().post('/api/work/delivery')).send({ name: 'X', phone: '09175550001', quantity: 1, channel: 'Text' });
    assert.equal(m.body.error.title, 'Name, phone, address or quantity missing');
    assert.deepEqual(m.body.error.fields, ['address']);
  });
});

describe('Mark Out for Delivery in batches (FR-05; Staff 1-3, Admin Orders 5) and tank counter (FR-06)', () => {
  test('To Do lists Processing orders and the tank counter', async () => {
    const list = await as(owner, api().get('/api/admin/orders?view=new'));
    mariaOrder = list.body.orders.find((o) => o.name === 'Maria Santos');
    const juanId = (await one("SELECT user_id FROM users WHERE full_name = 'Juan Dela Cruz'")).user_id;
    await as(owner, api().post('/api/admin/orders/accept')).send({ ids: [mariaOrder.id], riderId: juanId });
    const t = await as(staff, api().get('/api/work/todo'));
    assert.equal(t.body.processing.length, 3);
    assert.equal(t.body.tank.count, 3);
    assert.equal(t.body.owner, false);
  });

  test('different riders go out as separate batches; tank +7, seals -21, customer told', async () => {
    const r = await as(staff, api().post('/api/work/out')).send({ ids: [mariaOrder.id, ben.id, mila.id] });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.message, '3 orders out for delivery');
    assert.equal(r.body.batches.length, 2);
    assert.deepEqual(r.body.batches.map((b) => b.rider).sort(), ['Juan', 'Owner']);
    assert.equal((await tank()).count, 10);
    assert.equal(await stock('Seal'), 390);
    const c = await as(maria, api().get(`/api/orders/${mariaOrder.id}`));
    assert.equal(c.body.order.status, 'Out for Delivery');
    const n = await one("SELECT message FROM notifications WHERE notification_type = 'Out for Delivery' ORDER BY notification_id DESC LIMIT 1");
    assert.equal(n.message, 'Your rider is on the way.');
    const again = await as(staff, api().post('/api/work/out')).send({ ids: [ben.id] });
    assert.equal(again.status, 409);
    const locked = await as(owner, api().post(`/api/admin/orders/${ben.id}/rider`)).send({ riderId: 1 });
    assert.equal(locked.status, 409, 'rider is locked once out');
  });
});

describe('Rider deliveries and not delivered (FR-05, FR-08; Rider 1-4, 6; Admin Orders 5, 6)', () => {
  test('rider sees only their batch; Delivered Paid closes the batch', async () => {
    const d = await as(juan, api().get('/api/rider/deliveries'));
    assert.deepEqual(d.body.orders.map((o) => o.name), ['Maria Santos']);
    assert.equal(d.body.sharing, true);
    const r = await as(juan, api().post(`/api/rider/orders/${mariaOrder.id}/delivered`)).send({ paid: true });
    assert.equal(r.body.message, 'Delivered. Paid. Location sharing off.');
    assert.equal((await as(juan, api().post(`/api/rider/orders/${ben.id}/delivered`)).send({ paid: true })).status, 404);
    const done = await as(juan, api().get('/api/rider/done-today'));
    assert.equal(done.body.delivered, 1);
    assert.equal(done.body.paidAmount, 105);
  });

  test('owner as rider: paid at station needs no question; not delivered with a note', async () => {
    const d = await as(owner, api().get('/api/rider/deliveries'));
    assert.deepEqual(d.body.orders.map((o) => o.name).sort(), ['Ben Cruz', 'Mila Torres']);
    const m = await as(owner, api().post(`/api/rider/orders/${mila.id}/delivered`)).send({});
    assert.equal(m.body.message, 'Delivered.');
    const b = await as(owner, api().post(`/api/rider/orders/${ben.id}/not-delivered`)).send({ note: 'Not home' });
    assert.equal(b.body.message, 'Owner and customer notified. Location sharing off.');
    const n = await one("SELECT message FROM notifications WHERE notification_type = 'Not Delivered' AND user_id = 1 ORDER BY notification_id DESC LIMIT 1");
    assert.equal(n.message, 'Ben Cruz: Not home. Re-deliver or cancel.');
    const board = await as(owner, api().get('/api/admin/orders?view=not-delivered'));
    assert.equal(board.body.orders[0].reason, 'Not home');
  });

  test('re-deliver: back to Processing, not counted again; then Delivered Unpaid and marked paid', async () => {
    const before = (await tank()).count;
    const r = await as(owner, api().post(`/api/admin/orders/${ben.id}/redeliver`));
    assert.equal(r.body.message, 'Back to Processing.');
    assert.equal(r.body.order.status, 'Processing');
    await as(owner, api().post('/api/work/out')).send({ ids: [ben.id] });
    assert.equal((await tank()).count, before, 'not counted again');
    const u = await as(owner, api().post(`/api/admin/orders/${ben.id}/delivered`)).send({ paid: false });
    assert.equal(u.body.message, 'Delivered; customer owes P70.00 Location sharing off.');
    setNow(todayAt('09:55'));
    const p = await as(owner, api().post(`/api/admin/orders/${ben.id}/paid`));
    assert.equal(p.body.message, 'Marked paid.');
    assert.equal(p.body.order.paymentStatus, 'Paid');
    assert.equal((await as(owner, api().post(`/api/admin/orders/${ben.id}/paid`))).status, 409);
  });

  test('cancel an order with a reason; customer sees it', async () => {
    setNow(null);
    const o = await as(maria, api().post('/api/orders')).send({ type: 'Refill', quantity: 1, address: { mode: 'typed', house: '1', street: 'A St.', barangay: 'Holy Spirit' } });
    await as(owner, api().post('/api/admin/orders/accept')).send({ ids: [o.body.order.id], riderId: 1 });
    const c = await as(owner, api().post(`/api/admin/orders/${o.body.order.id}/cancel`)).send({ reason: 'Customer asked to cancel' });
    assert.equal(c.body.message, 'Order cancelled. Customer notified.');
    const seen = await as(maria, api().get(`/api/orders/${o.body.order.id}`));
    assert.equal(seen.body.order.status, 'Cancelled');
    assert.equal(seen.body.order.reason, 'Customer asked to cancel');
  });
});

describe('Tank alert at the limit; only the owner resets (FR-06; Admin Home 6, Staff 1)', () => {
  test('alert once at the limit, staff cannot reset, owner resets to 0', async () => {
    await as(owner, api().put('/api/settings/tank-limit')).send({ tankLimit: 12 });
    await as(staff, api().post('/api/work/walk-in')).send({ quantity: 3, paid: true });
    const t = await tank();
    assert.equal(t.alert, true);
    const n = await query("SELECT * FROM notifications WHERE notification_type = 'Tank'");
    assert.equal(n.length, 1);
    assert.equal(n[0].title, 'Tank at 12');
    assert.equal((await as(staff, api().post('/api/work/tank/reset'))).status, 403);
    const r = await as(owner, api().post('/api/work/tank/reset'));
    assert.equal(r.body.count, 0);
    assert.equal(r.body.message, 'Counter = 0; alert cleared');
  });
});

describe('Stock (FR-07; Admin Inventory 1-4, Admin Home 7)', () => {
  test('add stock, damaged or lost, movement history with filter, low-stock alert', async () => {
    const a = await as(owner, api().post('/api/inventory/gallons/add')).send({ quantity: 10, note: 'Supplier' });
    assert.equal(a.body.message, 'Stock goes up. Entry saved.');
    assert.equal(a.body.quantity, 33);
    const d = await as(owner, api().post('/api/inventory/gallons/remove')).send({ quantity: 1, kind: 'Damaged' });
    assert.equal(d.body.message, 'Stock goes down. Entry saved.');
    const inv = await as(owner, api().get('/api/inventory'));
    assert.deepEqual(inv.body.gallons, { quantity: 32, level: 30, low: false });
    await as(owner, api().post('/api/inventory/gallons/remove')).send({ quantity: 2, kind: 'Lost' });
    const low = await query("SELECT * FROM notifications WHERE notification_type = 'Low Stock'");
    assert.equal(low.length, 1);
    assert.equal(low[0].message, 'Gallons: 30 left');
    const all = await as(owner, api().get('/api/inventory/movements?item=gallons'));
    assert.equal(all.body.movements[0].label, 'Lost');
    assert.ok(all.body.movements.some((m) => m.label === 'Package sold' && m.automatic));
    const seals = await as(owner, api().get('/api/inventory/movements?item=seals&type=Automatic'));
    assert.ok(seals.body.movements.every((m) => m.automatic && m.item === 'seals'));
    assert.ok(seals.body.movements.some((m) => m.label === 'Order sent out for delivery'));
    assert.equal((await as(staff, api().get('/api/inventory'))).status, 403);
  });
});

describe("Owner Home, daily sales, alerts, staff Done Today (FR-10, FR-12, FR-16; FR-11)", () => {
  test("Home tiles and stock alerts", async () => {
    const h = await as(owner, api().get('/api/admin/home'));
    assert.equal(h.status, 200);
    assert.equal(h.body.counts.new, 1, 'Pedro is still new');
    assert.equal(h.body.today.walkIns, 3);
    assert.equal(h.body.today.delivered, 3);
    assert.equal(h.body.today.gallons, 13);
    assert.equal(h.body.today.moneyEarned, 60 + 70 + 105 + 70 + 90);
    assert.equal(h.body.today.unpaid, 150);
    assert.ok(h.body.stock.find((s) => s.item === 'gallons').low);
  });

  test('daily sales report', async () => {
    const r = await as(owner, api().get('/api/sales/daily'));
    assert.equal(r.body.summary.packages, 1);
    assert.equal(r.body.summary.deliveryGallons, 7);
    assert.equal(r.body.summary.walkInGallons, 6);
    assert.equal(r.body.summary.riderPaid, 105);
    assert.equal(r.body.orders.length, 6);
    assert.ok(r.body.orders.some((o) => o.tag === 'Paid at station'));
    assert.equal((await as(owner, api().get('/api/sales/daily?date=2099-01-01'))).status, 400);
  });

  test('owner alerts list and read', async () => {
    const n = await as(owner, api().get('/api/notifications'));
    const types = new Set(n.body.items.map((i) => i.type));
    for (const t of ['New Order', 'Logged Order', 'Not Delivered', 'Tank', 'Low Stock']) assert.ok(types.has(t), t);
    assert.ok(n.body.unread > 0);
    await as(owner, api().post('/api/notifications/read')).send({ all: true });
    assert.equal((await as(owner, api().get('/api/notifications/unread'))).body.unread, 0);
  });

  test('staff Done Today', async () => {
    const d = await as(staff, api().get('/api/work/done-today'));
    assert.equal(d.body.gallons, 13);
    const whats = d.body.items.map((i) => i.what);
    for (const w of ['Walk-in saved', 'Delivery logged', 'Sent out']) assert.ok(whats.includes(w), w);
  });

  test('customer My Orders: active and past, unpaid balance', async () => {
    const r = await as(maria, api().get('/api/orders'));
    assert.equal(r.body.orders.length, 2);
    assert.deepEqual(r.body.orders.map((o) => o.status).sort(), ["Cancelled", "Delivered"]);
    assert.equal(r.body.unpaid, 0);
  });
});
