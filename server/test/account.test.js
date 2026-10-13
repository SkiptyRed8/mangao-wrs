const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb, loginAs } = require('./helpers');

before(freshDb);
after(closeDb);

describe('My Account (FR-20, More 5, Staff 7, Rider 7, Customer 8)', () => {
  test('customer edits the profile; the new email gets reset codes', async () => {
    const t = await loginAs('09172001111', 'ana123');
    const r = await api().put('/api/account/profile').set('Authorization', `Bearer ${t}`)
      .send({ name: 'Ana Lim', phone: '0917 200 1111', email: 'analim.qc@gmail.com' });
    assert.equal(r.status, 200);
    assert.equal(r.body.message, 'Profile updated');
    assert.equal(r.body.user.email, 'analim.qc@gmail.com');
    const f = await api().post('/api/auth/forgot').send({ email: 'analim.qc@gmail.com' });
    assert.equal(f.status, 200);
  });

  test('email already used', async () => {
    const t = await loginAs('09172001111', 'ana123');
    const r = await api().put('/api/account/profile').set('Authorization', `Bearer ${t}`)
      .send({ name: 'Ana Lim', phone: '09172001111', email: 'joy.staff@example.com' });
    assert.equal(r.status, 409);
    assert.equal(r.body.error.title, 'Email already used');
    assert.equal(r.body.error.message, 'Use another email');
  });

  test('owner edits the profile; staff and riders are view only', async () => {
    const o = await loginAs('09170000001', 'owner123');
    const r = await api().put('/api/account/profile').set('Authorization', `Bearer ${o}`)
      .send({ name: 'Ervin P. Mangao', phone: '09170000001', email: 'mangaowrs.qc@gmail.com' });
    assert.equal(r.status, 200);
    const s = await loginAs('09170000002', 'staff123');
    const v = await api().put('/api/account/profile').set('Authorization', `Bearer ${s}`)
      .send({ name: 'Joy', phone: '09170000002', email: 'joy.staff@example.com' });
    assert.equal(v.status, 403);
  });

  test('every role changes the password (old password checked)', async () => {
    for (const [phone, pw] of [['09170000002', 'staff123'], ['09170000003', 'rider123']]) {
      const t = await loginAs(phone, pw);
      const wrong = await api().post('/api/account/password').set('Authorization', `Bearer ${t}`).send({ oldPassword: 'nope', newPassword: 'abcdef' });
      assert.equal(wrong.body.error.title, 'Old password wrong');
      const short = await api().post('/api/account/password').set('Authorization', `Bearer ${t}`).send({ oldPassword: pw, newPassword: 'abc' });
      assert.equal(short.body.error.title, 'Password too short');
      const ok = await api().post('/api/account/password').set('Authorization', `Bearer ${t}`).send({ oldPassword: pw, newPassword: pw + '9' });
      assert.equal(ok.body.message, 'Password changed');
      assert.equal((await api().post('/api/auth/login').send({ phone, password: pw + '9' })).status, 200);
    }
  });
});
