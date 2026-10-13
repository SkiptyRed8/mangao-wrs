// Staff & Riders (FR-02, Admin More 2): the owner adds, edits, deactivates and resets the
// passwords of staff and riders. The Owner account is listed but cannot be changed here.
const { Router } = require('express');
const bcrypt = require('bcryptjs');
const { one, query } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad, notFound, forbidden } = require('../utils/errors');
const { readProfile, checkFree, duplicateError, checkNewPassword, tempPassword } = require('../services/accounts');
const { shapeUser } = require('../services/users');

const router = Router();
router.use(requireAuth, requireRole('Owner'));

const PHONE_MSG = 'Another account uses this number';

async function staffMember(id) {
  const u = await one("SELECT * FROM users WHERE user_id = ? AND role IN ('Owner','Staff','Rider')", [Number(id) || 0]);
  if (!u) throw notFound('ACCOUNT_NOT_FOUND', 'Account not found', 'It may have been removed.');
  if (u.role === 'Owner') throw forbidden('OWNER_LOCKED', 'Owner account', 'The owner account cannot be changed here. Use My Account.');
  return u;
}

// GET /api/staff -> { accounts: [owner, then staff and riders] }
router.get('/', async (req, res) => {
  const rows = await query(
    `SELECT * FROM users WHERE role IN ('Owner','Staff','Rider')
     ORDER BY role = 'Owner' DESC, is_active DESC, full_name`
  );
  res.json({ accounts: rows.map(shapeUser) });
});

// POST /api/staff { name, phone, email, role: Staff|Rider, password } -> 201 { account }
router.post('/', async (req, res) => {
  const b = req.body || {};
  const p = readProfile(b);
  if (!['Staff', 'Rider'].includes(b.role)) throw bad('ROLE_MISSING', 'Choose Staff or Rider', 'Pick one of the two.', { field: 'role' });
  const password = String(b.password || '');
  checkNewPassword(password);
  await checkFree(p.phone, p.email, 0, PHONE_MSG);
  let r;
  try {
    r = await query('INSERT INTO users (full_name, phone_number, email, password_hash, role) VALUES (?, ?, ?, ?, ?)', [
      p.name,
      p.phone,
      p.email,
      await bcrypt.hash(password, 10),
      b.role,
    ]);
  } catch (err) {
    throw duplicateError(err, PHONE_MSG);
  }
  res.status(201).json({ account: shapeUser(await one('SELECT * FROM users WHERE user_id = ?', [r.insertId])), message: 'Account created. Can log in.' });
});

// GET /api/staff/:id -> { account }
router.get('/:id', async (req, res) => {
  res.json({ account: shapeUser(await staffMember(req.params.id)) });
});

// PUT /api/staff/:id { name, phone, email } -> { account }
router.put('/:id', async (req, res) => {
  const u = await staffMember(req.params.id);
  const p = readProfile(req.body);
  await checkFree(p.phone, p.email, u.user_id, PHONE_MSG);
  try {
    await query('UPDATE users SET full_name = ?, phone_number = ?, email = ? WHERE user_id = ?', [p.name, p.phone, p.email, u.user_id]);
  } catch (err) {
    throw duplicateError(err, PHONE_MSG);
  }
  res.json({ account: shapeUser(await one('SELECT * FROM users WHERE user_id = ?', [u.user_id])), message: 'Account updated' });
});

// POST /api/staff/:id/deactivate and /activate -> { account }
for (const [action, active, message] of [
  ['deactivate', 0, 'Cannot log in until activated again'],
  ['activate', 1, 'Account active. Can log in.'],
]) {
  router.post(`/:id/${action}`, async (req, res) => {
    const u = await staffMember(req.params.id);
    await query('UPDATE users SET is_active = ? WHERE user_id = ?', [active, u.user_id]);
    res.json({ account: shapeUser(await one('SELECT * FROM users WHERE user_id = ?', [u.user_id])), message });
  });
}

// POST /api/staff/:id/reset-password -> { tempPassword } (backup when they cannot get the email code)
router.post('/:id/reset-password', async (req, res) => {
  const u = await staffMember(req.params.id);
  const temp = tempPassword();
  await query('UPDATE users SET password_hash = ? WHERE user_id = ?', [await bcrypt.hash(temp, 10), u.user_id]);
  res.json({ tempPassword: temp, message: `Give this to ${u.full_name}. They can change it after logging in.` });
});

module.exports = router;
