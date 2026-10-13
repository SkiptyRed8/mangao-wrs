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
