// Log-in tokens (JWT) and role checks.
const jwt = require('jsonwebtoken');
const config = require('../config');
const { one } = require('../db');
const { unauthorized, forbidden } = require('../utils/errors');

const TOKEN_DAYS = 30;

function signToken(user) {
  return jwt.sign({ sub: user.user_id, role: user.role }, config.jwtSecret, { expiresIn: `${TOKEN_DAYS}d` });
}

async function userFromHeader(req) {
  const header = req.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return null;
  let payload;
  try {
    payload = jwt.verify(token, config.jwtSecret);
  } catch {
    throw unauthorized('SESSION_ENDED', 'Session ended', 'Please log in again.');
  }
  const user = await one('SELECT * FROM users WHERE user_id = ?', [payload.sub]);
  if (!user) throw unauthorized('SESSION_ENDED', 'Session ended', 'Please log in again.');
  if (!user.is_active) throw unauthorized('ACCOUNT_INACTIVE', 'Account deactivated', 'Ask the owner to activate your account.');
  return user;
}

/** Needs a logged-in user (req.user). */
async function requireAuth(req, res, next) {
  const user = await userFromHeader(req);
  if (!user) throw unauthorized('LOGIN_REQUIRED', 'Please log in', 'Log in to continue.');
  req.user = user;
  next();
}

/**
 * Logged-in users get req.user; guests send their phone's guest code in the X-Guest-Token header
 * (req.guestToken). Used by the customer order routes, which work for both.
 */
async function optionalAuth(req, res, next) {
  req.user = await userFromHeader(req);
  const g = String(req.get('x-guest-token') || '').trim();
  req.guestToken = /^[A-Za-z0-9_-]{16,64}$/.test(g) ? g : null;
  next();
}

/** Allows only the listed roles, e.g. requireRole('Owner', 'Staff'). */
const requireRole = (...roles) => (req, res, next) => {
  if (!req.user || !roles.includes(req.user.role)) {
    throw forbidden('NOT_ALLOWED', 'Not allowed', 'Your account cannot do this.');
  }
  next();
};

module.exports = { signToken, requireAuth, optionalAuth, requireRole, TOKEN_DAYS };
