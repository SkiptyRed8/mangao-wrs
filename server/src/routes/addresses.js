// Saved addresses (Customer 7): add (pin on map or type the address), edit, delete.
const { Router } = require('express');
const { query, one } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad, notFound } = require('../utils/errors');
const { text } = require('../utils/validate');
const { readAddress, shapeAddress } = require('../services/addresses');

const router = Router();
router.use(requireAuth, requireRole('Customer'));

const MAX_ADDRESSES = 10;

function readName(b) {
  const name = text((b || {}).name, 50);
  if (!name) throw bad('NAME_MISSING', 'Name missing', 'Type a name, like Home or Work.', { field: 'name' });
  return name;
}

async function mine(req) {
  const r = await one('SELECT * FROM customer_addresses WHERE address_id = ? AND customer_id = ?', [Number(req.params.id) || 0, req.user.user_id]);
  if (!r) throw notFound('ADDRESS_NOT_FOUND', 'Address not found', 'It may have been deleted.');
  return r;
}

const COLS = 'address_name = ?, house_unit_no = ?, block_lot = ?, street = ?, barangay = ?, landmark = ?, latitude = ?, longitude = ?';
const values = (name, a) => [name, a.house || null, a.blockLot || null, a.street || null, a.barangay || null, a.landmark || null, a.lat, a.lng];

// GET /api/addresses -> { addresses }
router.get('/', async (req, res) => {
  const rows = await query('SELECT * FROM customer_addresses WHERE customer_id = ? ORDER BY address_id', [req.user.user_id]);
  res.json({ addresses: rows.map(shapeAddress) });
});

// POST /api/addresses { name, mode, house, blockLot, street, barangay, landmark, lat, lng } -> 201 { address }
router.post('/', async (req, res) => {
  const name = readName(req.body);
  const a = readAddress(req.body);
  const n = await one('SELECT COUNT(*) AS n FROM customer_addresses WHERE customer_id = ?', [req.user.user_id]);
  if (n.n >= MAX_ADDRESSES) throw bad('TOO_MANY', 'Too many addresses', `Keep up to ${MAX_ADDRESSES}. Delete one first.`);
  const r = await query(`INSERT INTO customer_addresses SET customer_id = ?, ${COLS}`, [req.user.user_id, ...values(name, a)]);
  res.status(201).json({ address: shapeAddress(await one('SELECT * FROM customer_addresses WHERE address_id = ?', [r.insertId])), message: 'Address saved' });
});

// PUT /api/addresses/:id -> { address }
router.put('/:id', async (req, res) => {
  const row = await mine(req);
  const name = readName(req.body);
  const a = readAddress(req.body);
  await query(`UPDATE customer_addresses SET ${COLS} WHERE address_id = ?`, [...values(name, a), row.address_id]);
  res.json({ address: shapeAddress(await one('SELECT * FROM customer_addresses WHERE address_id = ?', [row.address_id])), message: 'Address updated' });
});

// DELETE /api/addresses/:id -> { ok } (past orders keep their own copy of the address)
router.delete('/:id', async (req, res) => {
  const row = await mine(req);
  await query('DELETE FROM customer_addresses WHERE address_id = ?', [row.address_id]);
  res.json({ ok: true, message: 'Address deleted' });
});

module.exports = router;
