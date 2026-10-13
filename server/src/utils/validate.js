// Input checks shared by the routes.
const MIN_PASSWORD = 6;

/** 0917 200 1111, +63 917..., 917... -> 09172001111 */
function normalizePhone(raw) {
  if (raw === undefined || raw === null) return '';
  let d = String(raw).replace(/[^0-9]/g, '');
  if (d.startsWith('63') && d.length === 12) d = '0' + d.slice(2);
  if (d.length === 10 && d.startsWith('9')) d = '0' + d;
  return d;
}

const isPhone = (p) => /^09\d{9}$/.test(p);

function normalizeEmail(raw) {
  return raw === undefined || raw === null ? '' : String(raw).trim().toLowerCase();
}

const isEmail = (e) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e) && e.length <= 100;

/** Trimmed text cut to max length; '' when missing. */
function text(v, max = 255) {
  if (v === undefined || v === null) return '';
  return String(v).trim().slice(0, max);
}

/** Whole number in [min, max], or null. */
function int(v, min, max) {
  const n = Number(v);
  if (!Number.isInteger(n) || n < min || n > max) return null;
  return n;
}

module.exports = { MIN_PASSWORD, normalizePhone, isPhone, normalizeEmail, isEmail, text, int };
