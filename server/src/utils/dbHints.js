// Plain-language hints for the usual database problems on the laptop (XAMPP).
const HINTS = {
  ECONNREFUSED: 'MySQL is not running. Open the XAMPP Control Panel and press Start beside MySQL (or double-click START.bat).',
  ER_ACCESS_DENIED_ERROR: 'Wrong MySQL user or password. Check DB_USER and DB_PASSWORD in server/.env (XAMPP: root and an empty password).',
  ER_BAD_DB_ERROR: 'The database does not exist yet. Double-click RESET-DEMO-DATA.bat (or run: npm run db:demo).',
  ER_NO_SUCH_TABLE: 'A table is missing. Double-click RESET-DEMO-DATA.bat (or run: npm run db:demo).',
  ENOTFOUND: 'DB_HOST in server/.env is wrong. Use localhost.',
  ETIMEDOUT: 'MySQL did not answer. Check that MySQL is running in XAMPP.',
  PROTOCOL_CONNECTION_LOST: 'MySQL stopped while the server was using it. Start MySQL again in XAMPP.',
};

/** The error code, also when Node wraps it (connecting to "localhost" tries two addresses). */
function dbErrorCode(err) {
  if (!err) return '';
  if (err.code) return err.code;
  if (Array.isArray(err.errors) && err.errors[0] && err.errors[0].code) return err.errors[0].code;
  return '';
}

function dbHint(err) {
  return HINTS[dbErrorCode(err)] || null;
}

function dbErrorText(err) {
  const code = dbErrorCode(err);
  const msg = (err && err.message) || (Array.isArray(err && err.errors) ? err.errors.map((e) => e.message).join('; ') : '');
  return `${code} ${msg}`.trim() || String(err);
}

module.exports = { dbHint, dbErrorCode, dbErrorText };
