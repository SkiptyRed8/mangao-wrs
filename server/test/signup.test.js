const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb } = require('./helpers');
const { one, query } = require('../src/db');

before(freshDb);
after(closeDb);

const form = (over = {}) => ({
  name: 'Maria Santos',
  phone: '0918 555 1234',
  email: 'Maria.Santos@Gmail.com',
  password: 'maria123',
  confirm: 'maria123',
  consent: true,
  ...over,
});

describe('Sign up, customers only (Login 3, 3A)', () => {
  test('creates a customer, logs in right away and saves the consent time', async () => {
    const r = await api().post('/api/auth/signup').send(form());
    assert.equal(r.status, 201);
    assert.ok(r.body.token);
    assert.equal(r.body.user.role, 'Customer');
    assert.equal(r.body.user.phone, '09185551234');
    assert.equal(r.body.user.email, 'maria.santos@gmail.com');
    const row = await one('SELECT privacy_consent_at FROM users WHERE phone_number = ?', ['09185551234']);
    assert.ok(row.privacy_consent_at);
    const me = await api().get('/api/auth/me').set('Authorization', `Bearer ${r.body.token}`);
    assert.equal(me.body.user.name, 'Maria Santos');
    const login = await api().post('/api/auth/login').send({ phone: '09185551234', password: 'maria123' });
    assert.equal(login.status, 200);
  });

  test('messages from the wireframes', async () => {
    const cases = [
      [{ email: '' }, 'Phone number or email missing', 'Both are required', 'email'],
      [{ phone: '' }, 'Phone number or email missing', 'Both are required', 'phone'],
      [{ consent: false }, 'Agree to continue', 'Tick the box to agree to the Terms and Data Privacy Notice', 'consent'],
      [{ phone: '09172001111', email: 'new1@gmail.com' }, 'Phone number already used', 'Log in instead', 'phone'],
      [{ phone: '09185550000', email: 'ana@example.com' }, 'Email already used', 'Use another email', 'email'],
      [{ name: '  ' }, 'Name missing', null, 'name'],
      [{ phone: '12345' }, 'Phone number not valid', null, 'phone'],
      [{ email: 'maria@' }, 'Email not valid', null, 'email'],
      [{ password: 'abc', confirm: 'abc' }, 'Password too short', null, 'password'],
      [{ confirm: 'other123' }, 'Passwords do not match', null, 'confirm'],
    ];
    for (const [over, title, message, fieldName] of cases) {
      const r = await api().post('/api/auth/signup').send(form({ phone: '09185559999', email: 'x9@gmail.com', ...over }));
      assert.ok(r.status === 400 || r.status === 409, `${title}: ${r.status}`);
      assert.equal(r.body.error.title, title);
      if (message) assert.equal(r.body.error.message, message);
      assert.equal(r.body.error.field, fieldName);
    }
    const count = await one("SELECT COUNT(*) AS n FROM users WHERE phone_number = '09185559999'");
    assert.equal(count.n, 0);
  });

  test('a guest who signs up keeps the orders made on this phone', async () => {
    const guest = 'g'.repeat(32);
    await query(
      `INSERT INTO orders (order_source, order_type, guest_token, customer_name, contact_phone, delivery_address_text, quantity, unit_price, total_amount, status, payment_method, payment_status)
       VALUES ('App', 'Refill', ?, 'Guest', '09185557777', '1 Test St.', 2, 35, 70, 'New', 'COD', 'Pending')`,
      [guest]
    ).catch((e) => {
      throw new Error('orders columns changed: ' + e.message);
    });
    const r = await api().post('/api/auth/signup').set('X-Guest-Token', guest).send(form({ phone: '09185557777', email: 'g@gmail.com' }));
    assert.equal(r.status, 201);
    const o = await one('SELECT customer_id, guest_token FROM orders WHERE contact_phone = ?', ['09185557777']);
    assert.equal(o.customer_id, r.body.user.id);
    assert.equal(o.guest_token, null);
  });

  test('staff, riders and the owner cannot be created by sign up', async () => {
    const r = await api().post('/api/auth/signup').send(form({ phone: '09185551111', email: 'r@gmail.com', role: 'Owner' }));
    assert.equal(r.status, 201);
    assert.equal(r.body.user.role, 'Customer');
  });
});
