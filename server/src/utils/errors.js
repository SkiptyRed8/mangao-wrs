// Errors with the wording shown in the app: { error: { code, title, message } }.
const { dbHint, dbErrorCode } = require('./dbHints');

class HttpError extends Error {
  constructor(status, code, title, message, extra = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.title = title;
    this.extra = extra;
  }
}

const make = (status) => (code, title, message, extra) => new HttpError(status, code, title, message, extra);
const bad = make(400);
const unauthorized = make(401);
const forbidden = make(403);
const notFound = make(404);
const conflict = make(409);

function notFoundRoute(req, res) {
  res.status(404).json({ error: { code: 'NOT_FOUND', title: 'Not found', message: `${req.method} ${req.path} does not exist.` } });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  if (err instanceof HttpError) {
    return res.status(err.status).json({ error: { code: err.code, title: err.title, message: err.message, ...err.extra } });
  }
  if (err && err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: { code: 'BAD_JSON', title: 'Something went wrong', message: 'The app sent data the server could not read.' } });
  }
  const hint = dbHint(err);
  if (hint) {
    console.error(`[database] ${dbErrorCode(err)}: ${hint}`);
    return res.status(503).json({ error: { code: 'DATABASE', title: 'The system is not ready', message: 'The database is not available. Try again in a moment.' } });
  }
  console.error(err);
  return res.status(500).json({ error: { code: 'SERVER_ERROR', title: 'Something went wrong', message: 'Please try again.' } });
}

module.exports = { HttpError, bad, unauthorized, forbidden, notFound, conflict, notFoundRoute, errorHandler };
