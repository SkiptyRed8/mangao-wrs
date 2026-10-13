// GET /health - is the server running, and can it reach the database?
const { Router } = require('express');
const { one } = require('../db');
const { dbHint, dbErrorText } = require('../utils/dbHints');

const router = Router();

router.get('/', async (req, res) => {
  const out = { ok: true, app: 'mangao-system', time: new Date().toISOString() };
  try {
    const r = await one('SELECT COUNT(*) AS users FROM users');
    out.database = 'ok';
    out.users = Number(r.users);
    res.json(out);
  } catch (err) {
    res.status(503).json({ ...out, ok: false, database: 'error', reason: dbErrorText(err), hint: dbHint(err) });
  }
});

module.exports = router;
