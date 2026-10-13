// Log in, sign up and forgot password (FR-01, Login 1-4).
const { Router } = require('express');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const config = require('../config');
const { one, query, transaction } = require('../db');
const { signToken, requireAuth } = require('../middleware/auth');
const { bad, unauthorized, notFound, conflict, HttpError } = require('../utils/errors');
const { MIN_PASSWORD, normalizePhone, isPhone, normalizeEmail, isEmail, text } = require('../utils/validate');
const { shapeUser } = require('../services/users');
const { mailReady, maskEmail, sendResetCode } = require('../services/mail');

const router = Router();

const CODE_MINUTES = 10; // the code works for 10 minutes
const RESEND_SECONDS = 60; // a new code can be asked for after 60 seconds
const MAX_TRIES = 5; // wrong tries before the code stops working
const RESET_MINUTES = 15; // time to type the new password after the code is correct

const field = (name) => ({ field: name });

// ---------------------------------------------------------------- Log in

// POST /api/auth/login { phone, password } -> { token, user }
router.post('/login', async (req, res) => {
  const phone = normalizePhone((req.body || {}).phone);
  const password = String((req.body || {}).password || '');
  if (!phone || !password) throw bad('DETAILS_MISSING', 'Details missing', 'Type your phone number and password');
  const user = await one('SELECT * FROM users WHERE phone_number = ?', [phone]);
  const ok = user && (await bcrypt.compare(password, user.password_hash));
  if (!ok) throw unauthorized('DETAILS_WRONG', 'Details wrong', 'Check your phone number and password');
  if (!user.is_active) throw unauthorized('ACCOUNT_INACTIVE', 'Cannot log in until activated again', 'Contact the station');
  res.json({ token: signToken(user), user: shapeUser(user) });
});

// GET /api/auth/me -> { user } (the app checks the saved session when it opens)
router.get('/me', requireAuth, (req, res) => {
  res.json({ user: shapeUser(req.user) });
});

// ---------------------------------------------------------------- Sign up (customers only)

function checkPasswords(password, confirm) {
  if (password.length < MIN_PASSWORD) {
    throw bad('PASSWORD_SHORT', 'Password too short', `Use at least ${MIN_PASSWORD} characters.`, field('password'));
  }
  if (password !== confirm) {
    throw bad('PASSWORDS_DIFFERENT', 'Passwords do not match', 'Type the same password in both fields.', field('confirm'));
  }
}

// POST /api/auth/signup { name, phone, email, password, confirm, consent } -> 201 { token, user }
// A guest who signs up (X-Guest-Token header) keeps the orders made on this phone (Customer 10).
router.post('/signup', async (req, res) => {
  const b = req.body || {};
  const name = text(b.name, 100);
  const rawPhone = text(b.phone, 20);
  const email = normalizeEmail(b.email);
  const phone = normalizePhone(rawPhone);
  const password = String(b.password || '');
  const confirm = String(b.confirm ?? b.password ?? '');

  if (!name) throw bad('NAME_MISSING', 'Name missing', 'Type your full name.', field('name'));
  if (!rawPhone || !email) {
    throw bad('PHONE_EMAIL_MISSING', 'Phone number or email missing', 'Both are required', field(!rawPhone ? 'phone' : 'email'));
  }
  if (!isPhone(phone)) throw bad('PHONE_INVALID', 'Phone number not valid', 'Use 11 digits, like 0917 200 1111.', field('phone'));
  if (!isEmail(email)) throw bad('EMAIL_INVALID', 'Email not valid', 'Check the email and try again.', field('email'));
  checkPasswords(password, confirm);
  if (b.consent !== true) {
    throw bad('CONSENT_REQUIRED', 'Agree to continue', 'Tick the box to agree to the Terms and Data Privacy Notice', field('consent'));
  }

  const phoneUsed = () => conflict('PHONE_USED', 'Phone number already used', 'Log in instead', field('phone'));
  const emailUsed = () => conflict('EMAIL_USED', 'Email already used', 'Use another email', field('email'));
  if (await one('SELECT user_id FROM users WHERE phone_number = ?', [phone])) throw phoneUsed();
  if (await one('SELECT user_id FROM users WHERE email = ?', [email])) throw emailUsed();

  const hash = await bcrypt.hash(password, 10);
  const guestToken = String(req.get('x-guest-token') || '').trim();
  let userId;
  try {
    userId = await transaction(async (conn) => {
      const [r] = await conn.query(
        "INSERT INTO users (full_name, phone_number, email, password_hash, role, privacy_consent_at) VALUES (?, ?, ?, ?, 'Customer', NOW())",
        [name, phone, email, hash]
      );
      if (/^[A-Za-z0-9_-]{16,64}$/.test(guestToken)) {
        await conn.query('UPDATE orders SET customer_id = ?, guest_token = NULL WHERE guest_token = ? AND customer_id IS NULL', [
          r.insertId,
          guestToken,
        ]);
        await conn.query('UPDATE notifications SET user_id = ?, guest_token = NULL WHERE guest_token = ? AND user_id IS NULL', [
          r.insertId,
          guestToken,
        ]);
      }
      return r.insertId;
    });
  } catch (err) {
    // Two sign ups at the same moment: the unique keys still stop a second account.
    if (err && err.code === 'ER_DUP_ENTRY') throw /email/i.test(err.message) ? emailUsed() : phoneUsed();
    throw err;
  }
  const user = await one('SELECT * FROM users WHERE user_id = ?', [userId]);
  res.status(201).json({ token: signToken(user), user: shapeUser(user) });
});

// ---------------------------------------------------------------- Forgot password (all roles)

const newCode = () => String(crypto.randomInt(0, 1000000)).padStart(6, '0');

async function findByEmail(raw) {
  const email = normalizeEmail(raw);
  if (!email) throw bad('EMAIL_MISSING', 'Email missing', 'Type the email on your account.', field('email'));
  const user = await one('SELECT * FROM users WHERE email = ?', [email]);
  if (!user) throw notFound('EMAIL_NOT_FOUND', 'Email not found', 'No account uses this email. Check it and try again.', field('email'));
  return user;
}

// POST /api/auth/forgot { email } -> { email (masked), expiresIn, resendIn, emailSent, devCode? }
// Also used by "Resend code": the old code stops working.
router.post('/forgot', async (req, res) => {
  const user = await findByEmail((req.body || {}).email);

  const last = await one(
    'SELECT TIMESTAMPDIFF(SECOND, created_at, NOW()) AS age FROM password_resets WHERE user_id = ? ORDER BY reset_id DESC LIMIT 1',
    [user.user_id]
  );
  if (last && last.age < RESEND_SECONDS) {
    const wait = RESEND_SECONDS - last.age;
    throw new HttpError(429, 'WAIT', 'Wait a moment', `You can ask for a new code in ${wait} seconds.`, { resendIn: wait });
  }

  const code = newCode();
  await transaction(async (conn) => {
    await conn.query('UPDATE password_resets SET used_at = NOW() WHERE user_id = ? AND used_at IS NULL', [user.user_id]);
    await conn.query('INSERT INTO password_resets (user_id, code_hash, expires_at) VALUES (?, ?, NOW() + INTERVAL ? MINUTE)', [
      user.user_id,
      await bcrypt.hash(code, 8),
      CODE_MINUTES,
    ]);
  });

  let sent = false;
  try {
    sent = (await sendResetCode(user.email, user.full_name, code)).sent;
  } catch (err) {
    console.error('[email] could not send the reset code:', err.message);
    await query('UPDATE password_resets SET used_at = NOW() WHERE user_id = ? AND used_at IS NULL', [user.user_id]);
    throw new HttpError(503, 'EMAIL_NOT_SENT', 'Email not sent', 'Try again in a moment.');
  }

  const out = { email: maskEmail(user.email), expiresIn: CODE_MINUTES * 60, resendIn: RESEND_SECONDS, emailSent: sent };
  if (!sent && config.env !== 'production' && !mailReady()) out.devCode = code; // demo only, see services/mail.js
  res.json(out);
});

// POST /api/auth/forgot/verify { email, code } -> { resetToken }
router.post('/forgot/verify', async (req, res) => {
  const user = await findByEmail((req.body || {}).email);
  const code = String((req.body || {}).code || '').replace(/\D/g, '');
  const wrong = () => bad('CODE_WRONG', 'Code wrong or expired', 'Tap Resend code to get a new one.', field('code'));

  const row = await one(
    'SELECT *, expires_at < NOW() AS expired FROM password_resets WHERE user_id = ? AND used_at IS NULL ORDER BY reset_id DESC LIMIT 1',
    [user.user_id]
  );
  if (!row || row.expired || row.attempts >= MAX_TRIES || code.length !== 6) {
    if (row && code.length === 6) await query('UPDATE password_resets SET attempts = attempts + 1 WHERE reset_id = ?', [row.reset_id]);
    throw wrong();
  }
  if (!(await bcrypt.compare(code, row.code_hash))) {
    await query('UPDATE password_resets SET attempts = attempts + 1 WHERE reset_id = ?', [row.reset_id]);
    throw wrong();
  }
  const resetToken = jwt.sign({ sub: user.user_id, rid: row.reset_id, purpose: 'reset' }, config.jwtSecret, {
    expiresIn: `${RESET_MINUTES}m`,
  });
  res.json({ resetToken });
});

// POST /api/auth/forgot/reset { resetToken, password, confirm } -> { ok }
router.post('/forgot/reset', async (req, res) => {
  const b = req.body || {};
  const password = String(b.password || '');
  const confirm = String(b.confirm ?? '');
  const ended = () => bad('RESET_ENDED', 'Code wrong or expired', 'Start again and ask for a new code.');

  let payload;
  try {
    payload = jwt.verify(String(b.resetToken || ''), config.jwtSecret);
  } catch {
    throw ended();
  }
  if (payload.purpose !== 'reset') throw ended();
  checkPasswords(password, confirm);

  const done = await transaction(async (conn) => {
    const [r] = await conn.query(
      'UPDATE password_resets SET used_at = NOW() WHERE reset_id = ? AND user_id = ? AND used_at IS NULL',
      [payload.rid, payload.sub]
    );
    if (r.affectedRows !== 1) return false;
    await conn.query('UPDATE users SET password_hash = ? WHERE user_id = ?', [await bcrypt.hash(password, 10), payload.sub]);
    return true;
  });
  if (!done) throw ended();
  res.json({ ok: true, message: 'Password changed. Log in with your new password.' });
});

module.exports = router;
