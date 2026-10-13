const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb } = require('./helpers');
const { query } = require('../src/db');

before(freshDb);
after(closeDb);

describe('Log in (FR-01, Login 1, 2, 4)', () => {
  test('each role logs in with phone number and password', async () => {
    for (const [phone, pw, role] of [
      ['09170000001', 'owner123', 'Owner'],
      ['0917 000 0002', 'staff123', 'Staff'],
      ['+63 917 000 0003', 'rider123', 'Rider'],
      ['09172001111', 'ana123', 'Customer'],
    ]) {
      const r = await api().post('/api/auth/login').send({ phone, password: pw });
      assert.equal(r.status, 200, phone);
      assert.equal(r.body.user.role, role);
      assert.ok(r.body.token);
      assert.equal(r.body.user.password_hash, undefined);
    }
  });

  test('details wrong', async () => {
    const r = await api().post('/api/auth/login').send({ phone: '09172001111', password: 'nope' });
    assert.equal(r.status, 401);
    assert.equal(r.body.error.title, 'Details wrong');
    assert.equal(r.body.error.message, 'Check your phone number and password');
    const u = await api().post('/api/auth/login').send({ phone: '09999999999', password: 'x' });
    assert.equal(u.body.error.title, 'Details wrong');
  });

  test('deactivated account cannot log in', async () => {
    await query("UPDATE users SET is_active = 0 WHERE phone_number = '09170000003'");
    const r = await api().post('/api/auth/login').send({ phone: '09170000003', password: 'rider123' });
    assert.equal(r.status, 401);
    assert.equal(r.body.error.title, 'Cannot log in until activated again');
    await query("UPDATE users SET is_active = 1 WHERE phone_number = '09170000003'");
  });

  test('saved session: /me with the token, and an ended session', async () => {
    const login = await api().post('/api/auth/login').send({ phone: '09170000002', password: 'staff123' });
    const me = await api().get('/api/auth/me').set('Authorization', `Bearer ${login.body.token}`);
    assert.equal(me.status, 200);
    assert.equal(me.body.user.name, 'Joy Ramos');
    const bad = await api().get('/api/auth/me').set('Authorization', 'Bearer not-a-token');
    assert.equal(bad.status, 401);
    assert.equal(bad.body.error.title, 'Session ended');
  });
});
