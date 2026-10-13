// Export Report (Admin Sales 4). The owner chooses the report, date and format; the server gives a
// download link that works for 5 minutes (so the log-in token never goes in a web address).
//  POST /api/export { report: daily|weekly|unpaid, date, format: pdf|xlsx } -> { fileName, url, message }
//  GET  /api/export/file?ticket=... -> the file (Content-Disposition: attachment)
const { Router } = require('express');
const jwt = require('jsonwebtoken');
const config = require('../config');
const { one } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad, unauthorized } = require('../utils/errors');
const { now, phParts } = require('../services/time');
const { exportFile } = require('../services/export');

const router = Router();
const REPORTS = ['daily', 'weekly', 'unpaid'];
const FORMATS = ['pdf', 'xlsx'];
const today = () => {
  const p = phParts(now());
  return `${p.y}-${String(p.mo + 1).padStart(2, '0')}-${String(p.d).padStart(2, '0')}`;
};

function check(report, date, format) {
  if (!REPORTS.includes(report)) throw bad('REPORT_MISSING', 'Choose a report', 'Daily, Weekly or Unpaid accounts.');
  if (!FORMATS.includes(format)) throw bad('FORMAT_MISSING', 'Choose a format', 'PDF or Spreadsheet.');
  const d = date || today();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) throw bad('DATE_INVALID', 'Date not valid', 'Pick the date again.');
  if (d > today()) throw bad('DATE_FUTURE', 'No sales yet', 'Pick today or an earlier day.');
  return d;
}

router.post('/', requireAuth, requireRole('Owner'), async (req, res) => {
  const { report, format } = req.body || {};
  const date = check(report, (req.body || {}).date, format);
  const ticket = jwt.sign({ sub: req.user.user_id, report, date, format, kind: 'export' }, config.jwtSecret, { expiresIn: '5m' });
  // Build it once now so problems show here and the name is known.
  const f = await exportFile(report, date, format);
  res.json({ fileName: f.fileName, url: `/api/export/file?ticket=${encodeURIComponent(ticket)}`, message: 'File ready' });
});

router.get('/file', async (req, res) => {
  let t;
  try {
    t = jwt.verify(String(req.query.ticket || ''), config.jwtSecret);
  } catch {
    throw unauthorized('LINK_EXPIRED', 'Link expired', 'Tap Create file again.');
  }
  if (t.kind !== 'export') throw unauthorized('LINK_EXPIRED', 'Link expired', 'Tap Create file again.');
  const u = await one("SELECT is_active FROM users WHERE user_id = ? AND role = 'Owner'", [t.sub]);
  if (!u || !u.is_active) throw unauthorized('LINK_EXPIRED', 'Link expired', 'Tap Create file again.');
  const f = await exportFile(t.report, check(t.report, t.date, t.format), t.format);
  res.set('Content-Type', f.type);
  res.set('Content-Disposition', `attachment; filename="${f.fileName}"`);
  res.set('Cache-Control', 'no-store');
  res.send(f.buf);
});

module.exports = router;
