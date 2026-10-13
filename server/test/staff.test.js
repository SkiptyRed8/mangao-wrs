const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb, loginAs } = require('./helpers');

let owner;
before(async () => {
  await freshDb();
  owner = await loginAs('09170000001', 'owner123');
});
after(closeDb);

const asOwner = (req) => req.set('Authorization', `Bearer ${owner}`);

describe('Staff & Riders (FR-02, Admin More 2)', () => {
  test('list shows the Owner first, then staff and riders', async () => {
    const r = await asOwner(api().get('/api/staff'));
    assert.equal(r.status, 200);
    assert.equal(r.body.accounts[0].role, 'Owner');
    assert.deepEqual(r.body.accounts.slice(1).map((a) => a.name).sort(), ['Joy Ramos', 'Juan Dela Cruz']);
  });

  test('only the owner can open it', async () => {
    const staff = await loginAs('09170000002', 'staff123');
    const r = await api().get('/api/staff').set('Authorization', `Bearer ${staff}`);
    assert.equal(r.status, 403);
    assert.equal((await api().get('/api/staff')).status, 401);
  });

  let rosa;
  test('add account -> can log in', async () => {
    const r = await asOwner(api().post('/api/staff')).send({
      name: 'Rosa Diaz', phone: '0917 333 4444', email: 'rosa@gmail.com', role: 'Staff', password: 'rosa123',
    });
    assert.equal(r.status, 201);
    assert.equal(r.body.message, 'Account created. Can log in.');
    rosa = r.body.account;
    assert.equal(rosa.role, 'Staff');
    const login = await api().post('/api/auth/login').send({ phone: '09173334444', password: 'rosa123' });
    assert.equal(login.status, 200);
  });

  test('add account messages', async () => {
    const base = { name: 'X', phone: '09173335555', email: 'x@gmail.com', role: 'Rider', password: 'xxxxxx' };
    for (const [over, title] of [
      [{ role: 'Owner' }, 'Choose Staff or Rider'],
      [{ phone: '09170000002' }, 'Phone number already used'],
      [{ email: 'ana@example.com' }, 'Email already used'],
      [{ email: '' }, 'Phone number or email missing'],
      [{ password: '123' }, 'Password too short'],
    ]) {
      const r = await asOwner(api().post('/api/staff')).send({ ...base, ...over });
      assert.equal(r.body.error.title, title);
    }
  });

  test('edit, deactivate (cannot log in), activate', async () => {
    const e = await asOwner(api().put(`/api/staff/${rosa.id}`)).send({ name: 'Rosa M. Diaz', phone: '09173334444', email: 'rosa.diaz@gmail.com' });
    assert.equal(e.status, 200);
    assert.equal(e.body.account.name, 'Rosa M. Diaz');
    assert.equal(e.body.message, 'Account updated');

    const d = await asOwner(api().post(`/api/staff/${rosa.id}/deactivate`));
    assert.equal(d.body.account.active, false);
    const blocked = await api().post('/api/auth/login').send({ phone: '09173334444', password: 'rosa123' });
    assert.equal(blocked.body.error.title, 'Cannot log in until activated again');

    const a = await asOwner(api().post(`/api/staff/${rosa.id}/activate`));
    assert.equal(a.body.account.active, true);
    const ok = await api().post('/api/auth/login').send({ phone: '09173334444', password: 'rosa123' });
    assert.equal(ok.status, 200);
  });

  test('a deactivated staff member is logged out on the next request', async () => {
    const token = await loginAs('09173334444', 'rosa123');
    await asOwner(api().post(`/api/staff/${rosa.id}/deactivate`));
    const me = await api().get('/api/auth/me').set('Authorization', `Bearer ${token}`);
    assert.equal(me.status, 401);
    await asOwner(api().post(`/api/staff/${rosa.id}/activate`));
  });

  test('reset password gives a temporary password that works', async () => {
    const r = await asOwner(api().post(`/api/staff/${rosa.id}/reset-password`));
    assert.match(r.body.tempPassword, /^wrs-\d{4}$/);
    assert.equal(r.body.message, 'Give this to Rosa M. Diaz. They can change it after logging in.');
    const login = await api().post('/api/auth/login').send({ phone: '09173334444', password: r.body.tempPassword });
    assert.equal(login.status, 200);
  });

  test('the Owner account cannot be changed or deactivated here', async () => {
    const d = await asOwner(api().post('/api/staff/1/deactivate'));
    assert.equal(d.status, 403);
    const c = await asOwner(api().put('/api/staff/4')).send({ name: 'A', phone: '09170000009', email: 'a@b.com' });
    assert.equal(c.status, 404, 'customers are not staff');
  });
});
