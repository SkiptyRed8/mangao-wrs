// Log in (FR-01, Login 1, 2, 4). Sign up and forgot password are added in steps T08 and T09.
const { Router } = require('express');
const bcrypt = require('bcryptjs');
const { one } = require('../db');
const { signToken, requireAuth } = require('../middleware/auth');
const { bad, unauthorized } = require('../utils/errors');
const { normalizePhone } = require('../utils/validate');
const { shapeUser } = require('../services/users');

const router = Router();

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

module.exports = router;
