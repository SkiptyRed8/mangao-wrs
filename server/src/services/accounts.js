// Checks shared by Sign up, Staff & Riders and My Account: name, phone number and email
// (both required, Login 3A and Customer 8), and that no other account uses them.
const crypto = require('crypto');
const { one } = require('../db');
const { bad, conflict } = require('../utils/errors');
const { MIN_PASSWORD, normalizePhone, isPhone, normalizeEmail, isEmail, text } = require('../utils/validate');

const field = (name) => ({ field: name });

/** Reads and checks { name, phone, email } from a request body. */
function readProfile(b = {}) {
  const name = text(b.name, 100);
  const rawPhone = text(b.phone, 20);
  const email = normalizeEmail(b.email);
  const phone = normalizePhone(rawPhone);
  if (!name) throw bad('NAME_MISSING', 'Name missing', 'Type the full name.', field('name'));
  if (!rawPhone || !email) {
    throw bad('PHONE_EMAIL_MISSING', 'Phone number or email missing', 'Both are required', field(!rawPhone ? 'phone' : 'email'));
  }
  if (!isPhone(phone)) throw bad('PHONE_INVALID', 'Phone number not valid', 'Use 11 digits, like 0917 200 1111.', field('phone'));
  if (!isEmail(email)) throw bad('EMAIL_INVALID', 'Email not valid', 'Check the email and try again.', field('email'));
  return { name, phone, email };
}

const phoneUsed = (msg = 'Log in instead') => conflict('PHONE_USED', 'Phone number already used', msg, field('phone'));
const emailUsed = () => conflict('EMAIL_USED', 'Email already used', 'Use another email', field('email'));

/** Throws when another account (not exceptId) has this phone number or email. */
async function checkFree(phone, email, exceptId = 0, phoneMsg) {
  if (await one('SELECT user_id FROM users WHERE phone_number = ? AND user_id <> ?', [phone, exceptId])) throw phoneUsed(phoneMsg);
  if (await one('SELECT user_id FROM users WHERE email = ? AND user_id <> ?', [email, exceptId])) throw emailUsed();
}

/** Maps a duplicate-key error from MySQL (two saves at the same moment) to the same messages. */
function duplicateError(err, phoneMsg) {
  if (err && err.code === 'ER_DUP_ENTRY') return /email/i.test(err.message) ? emailUsed() : phoneUsed(phoneMsg);
  return err;
}

function checkNewPassword(password, confirm) {
  if (password.length < MIN_PASSWORD) {
    throw bad('PASSWORD_SHORT', 'Password too short', `Use at least ${MIN_PASSWORD} characters.`, field('password'));
  }
  if (confirm !== undefined && password !== confirm) {
    throw bad('PASSWORDS_DIFFERENT', 'Passwords do not match', 'Type the same password in both fields.', field('confirm'));
  }
}

/** Temporary password the owner reads out to a staff member or rider, e.g. wrs-4821. */
const tempPassword = () => `wrs-${String(crypto.randomInt(0, 10000)).padStart(4, '0')}`;

module.exports = { readProfile, checkFree, duplicateError, checkNewPassword, tempPassword, phoneUsed, emailUsed };
