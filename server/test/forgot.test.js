const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb } = require('./helpers');
const { query } = require('../src/db');

before(freshDb);
after(closeDb);

// Lets the next "Resend code" through without waiting 60 seconds.
const skipWait = () => query('UPDATE password_resets SET created_at = created_at - INTERVAL 2 MINUTE');

async function getCode(email) {
  const r = await api().post('/api/auth/forgot').send({ email });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.match(r.body.devCode, /^\d{6}$/); // email is not set up in tests
  return r;
}

describe('Forgot password, every role (Login 2, 2A)', () => {
  test('code -> verify -> new password -> log in with it', async () => {
    const sent = await getCode('JOY.staff@example.com');
    assert.equal(sent.body.email, 'j••••@example.com');
    assert.equal(sent.body.expiresIn, 600);
    assert.equal(sent.body.resendIn, 60);
    assert.equal(sent.body.emailSent, false);

    const v = await api().post('/api/auth/forgot/verify').send({ email: 'joy.staff@example.com', code: sent.body.devCode });
    assert.equal(v.status, 200);
    assert.ok(v.body.resetToken);

    const r = await api().post('/api/auth/forgot/reset').send({ resetToken: v.body.resetToken, password: 'newpass1', confirm: 'newpass1' });
    assert.equal(r.status, 200);
    assert.equal(r.body.message, 'Password changed. Log in with your new password.');

    const oldPw = await api().post('/api/auth/login').send({ phone: '09170000002', password: 'staff123' });
    assert.equal(oldPw.status, 401);
    const newPw = await api().post('/api/auth/login').send({ phone: '09170000002', password: 'newpass1' });
    assert.equal(newPw.status, 200);

    const again = await api().post('/api/auth/forgot/reset').send({ resetToken: v.body.resetToken, password: 'x123456', confirm: 'x123456' });
    assert.equal(again.status, 400, 'a reset can be used once only');
  });

  test('email not found', async () => {
    const r = await api().post('/api/auth/forgot').send({ email: 'ana.lim@gmial.com' });
    assert.equal(r.status, 404);
    assert.equal(r.body.error.title, 'Email not found');
    assert.equal(r.body.error.message, 'No account uses this email. Check it and try again.');
  });

  test('code wrong or expired, and Resend code makes the old code stop working', async () => {
    const first = await getCode('ana@example.com');
    const wrongCode = first.body.devCode === '000000' ? '111111' : '000000';
    const w = await api().post('/api/auth/forgot/verify').send({ email: 'ana@example.com', code: wrongCode });
    assert.equal(w.status, 400);
    assert.equal(w.body.error.title, 'Code wrong or expired');
    assert.equal(w.body.error.message, 'Tap Resend code to get a new one.');

    const early = await api().post('/api/auth/forgot').send({ email: 'ana@example.com' });
    assert.equal(early.status, 429, 'Resend code waits 60 seconds');
    assert.ok(early.body.error.resendIn > 0);

    await skipWait();
    const second = await getCode('ana@example.com');
    const old = await api().post('/api/auth/forgot/verify').send({ email: 'ana@example.com', code: first.body.devCode });
    if (first.body.devCode !== second.body.devCode) assert.equal(old.status, 400, 'old code no longer works');

    await query("UPDATE password_resets SET expires_at = NOW() - INTERVAL 1 MINUTE WHERE used_at IS NULL");
    const expired = await api().post('/api/auth/forgot/verify').send({ email: 'ana@example.com', code: second.body.devCode });
    assert.equal(expired.status, 400);
    assert.equal(expired.body.error.title, 'Code wrong or expired');
  });

  test('five wrong tries stop the code', async () => {
    await skipWait();
    const sent = await getCode('juan.rider@example.com');
    const wrongCode = sent.body.devCode === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) await api().post('/api/auth/forgot/verify').send({ email: 'juan.rider@example.com', code: wrongCode });
    const r = await api().post('/api/auth/forgot/verify').send({ email: 'juan.rider@example.com', code: sent.body.devCode });
    assert.equal(r.status, 400);
  });

  test('passwords do not match, and too short', async () => {
    await skipWait();
    const sent = await getCode('owner@example.com');
    const v = await api().post('/api/auth/forgot/verify').send({ email: 'owner@example.com', code: sent.body.devCode });
    const m = await api().post('/api/auth/forgot/reset').send({ resetToken: v.body.resetToken, password: 'abcdef12', confirm: 'abcdef' });
    assert.equal(m.status, 400);
    assert.equal(m.body.error.title, 'Passwords do not match');
    assert.equal(m.body.error.message, 'Type the same password in both fields.');
    const s = await api().post('/api/auth/forgot/reset').send({ resetToken: v.body.resetToken, password: 'abc', confirm: 'abc' });
    assert.equal(s.body.error.title, 'Password too short');
    const ok = await api().post('/api/auth/forgot/reset').send({ resetToken: v.body.resetToken, password: 'owner456', confirm: 'owner456' });
    assert.equal(ok.status, 200, 'the reset still works after a message');
  });
});
