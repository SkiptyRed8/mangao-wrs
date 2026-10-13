// My Account (FR-20; More 5, Staff 7, Rider 7, Customer 8): every role changes its password;
// the owner and customers also edit their profile (staff and riders are edited by the owner).
const { Router } = require('express');
const bcrypt = require('bcryptjs');
const { one, query } = require('../db');
const { requireAuth } = require('../middleware/auth');
const { bad, forbidden } = require('../utils/errors');
const { readProfile, checkFree, duplicateError, checkNewPassword } = require('../services/accounts');
const { shapeUser } = require('../services/users');

const router = Router();
router.use(requireAuth);

const PHONE_MSG = 'Another account uses this number';

// PUT /api/account/profile { name, phone, email } -> { user }
router.put('/profile', async (req, res) => {
  if (!['Owner', 'Customer'].includes(req.user.role)) {
    throw forbidden('VIEW_ONLY', 'View only', 'Ask the owner to change your name, phone number or email.');
  }
  const p = readProfile(req.body);
  await checkFree(p.phone, p.email, req.user.user_id, PHONE_MSG);
  try {
    await query('UPDATE users SET full_name = ?, phone_number = ?, email = ? WHERE user_id = ?', [p.name, p.phone, p.email, req.user.user_id]);
  } catch (err) {
    throw duplicateError(err, PHONE_MSG);
  }
  res.json({ user: shapeUser(await one('SELECT * FROM users WHERE user_id = ?', [req.user.user_id])), message: 'Profile updated' });
});

// POST /api/account/password { oldPassword, newPassword } -> { ok }
router.post('/password', async (req, res) => {
  const b = req.body || {};
  const oldPassword = String(b.oldPassword || '');
  const newPassword = String(b.newPassword || '');
  if (!oldPassword) throw bad('OLD_MISSING', 'Old password missing', 'Type your current password.', { field: 'old' });
  if (!(await bcrypt.compare(oldPassword, req.user.password_hash))) {
    throw bad('OLD_WRONG', 'Old password wrong', 'Check it and try again. Forgot it? Log out and tap Forgot password.', { field: 'old' });
  }
  checkNewPassword(newPassword);
  await query('UPDATE users SET password_hash = ? WHERE user_id = ?', [await bcrypt.hash(newPassword, 10), req.user.user_id]);
  res.json({ ok: true, message: 'Password changed' });
});

module.exports = router;
