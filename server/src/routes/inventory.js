// Inventory (FR-07; Admin Inventory 1-4): New Gallons and Seals. Add stock, Damaged or Lost,
// automatic entries (seals 3 per gallon, 1 new gallon per package), Movement History with a filter.
const { Router } = require('express');
const { one, query, transaction } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad, notFound } = require('../utils/errors');
const { int, text } = require('../utils/validate');
const { now, phAt } = require('../services/time');
const { moveStock } = require('../services/process');

const router = Router();
router.use(requireAuth, requireRole('Owner'));

const ITEMS = { gallons: 'New Gallon', seals: 'Seal' };
const itemOf = (key) => {
  if (!ITEMS[key]) throw notFound('ITEM_NOT_FOUND', 'Not found', 'Use gallons or seals.');
  return ITEMS[key];
};

function shapeMove(m) {
  const auto = m.order_id !== null || m.recorded_by === null;
  const label = m.note && auto ? m.note : { Added: 'Stock added', Damaged: 'Damaged', Lost: 'Lost', Used: 'Used', Adjusted: 'Adjusted', Lent: 'Lent', Returned: 'Returned' }[m.movement_type];
  return {
    id: m.movement_id,
    item: m.item_name === 'Seal' ? 'seals' : 'gallons',
    itemLabel: m.item_name === 'Seal' ? 'Seals' : 'New Gallons',
    change: m.quantity_change,
    type: m.movement_type,
    label,
    note: auto ? '' : m.note || '',
    orderId: m.order_id,
    automatic: auto,
    by: m.recorded_role === 'Owner' ? 'Owner' : m.recorded_name || '',
    at: m.created_at,
  };
}

const MOVE_SELECT = `SELECT m.*, i.item_name, u.full_name AS recorded_name, u.role AS recorded_role
  FROM stock_movements m JOIN inventory_items i ON i.item_id = m.item_id LEFT JOIN users u ON u.user_id = m.recorded_by`;

// GET /api/inventory -> { gallons, seals, sealsPerGallon }
router.get('/', async (req, res) => {
  const items = await query('SELECT * FROM inventory_items');
  const s = await one('SELECT seals_per_gallon FROM station_settings WHERE setting_id = 1');
  const out = { sealsPerGallon: s.seals_per_gallon };
  for (const i of items) {
    out[i.item_name === 'Seal' ? 'seals' : 'gallons'] = { quantity: i.quantity_on_hand, level: i.low_stock_level, low: i.quantity_on_hand <= i.low_stock_level };
  }
  res.json(out);
});

// GET /api/inventory/movements?item=gallons|seals|all&type=Added|Damaged|Lost|Automatic&from=YYYY-MM-DD&to=YYYY-MM-DD
router.get('/movements', async (req, res) => {
  const where = [];
  const params = [];
  if (ITEMS[req.query.item]) {
    where.push('i.item_name = ?');
    params.push(ITEMS[req.query.item]);
  }
  if (req.query.type === 'Automatic') where.push('(m.order_id IS NOT NULL OR m.recorded_by IS NULL)');
  else if (['Added', 'Damaged', 'Lost'].includes(req.query.type)) {
    where.push('m.movement_type = ? AND m.order_id IS NULL');
    params.push(req.query.type);
  }
  for (const [key, op, add] of [['from', '>=', 0], ['to', '<', 1]]) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(req.query[key] || '')) {
      const d = phAt(new Date(`${req.query[key]}T12:00:00+08:00`), 0, 0);
      where.push(`m.created_at ${op} ?`);
      params.push(new Date(d.getTime() + add * 86400000));
    }
  }
  const rows = await query(`${MOVE_SELECT} ${where.length ? `WHERE ${where.join(' AND ')}` : ''} ORDER BY m.created_at DESC, m.movement_id DESC LIMIT 300`, params);
  res.json({ movements: rows.map(shapeMove) });
});

function readDate(v) {
  if (!v) return now();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) throw bad('DATE_INVALID', 'Date not valid', 'Pick the date again.');
  const d = new Date(`${v}T12:00:00+08:00`);
  if (d.getTime() > now().getTime() + 86400000) throw bad('DATE_FUTURE', 'Date is in the future', 'Pick today or an earlier day.');
  const today = phAt(now(), 0, 0);
  return d >= today ? now() : d;
}

// POST /api/inventory/:item/add { quantity, date, note } -> stock goes up
router.post('/:item/add', async (req, res) => {
  const name = itemOf(req.params.item);
  const b = req.body || {};
  const qty = int(b.quantity, 1, 100000);
  if (qty === null) throw bad('QTY_MISSING', 'Quantity missing', 'Tap + to set how many were added.', { field: 'quantity' });
  const at = readDate(b.date);
  const after = await transaction((conn) => moveStock(conn, name, qty, { type: 'Added', note: text(b.note, 255) || null, userId: req.user.user_id, at }));
  res.json({ quantity: after, message: 'Stock goes up. Entry saved.' });
});

// POST /api/inventory/:item/remove { quantity, kind: Damaged|Lost, note } -> stock goes down
router.post('/:item/remove', async (req, res) => {
  const name = itemOf(req.params.item);
  const b = req.body || {};
  const qty = int(b.quantity, 1, 100000);
  if (qty === null) throw bad('QTY_MISSING', 'Quantity missing', 'Tap + to set how many.', { field: 'quantity' });
  const kind = b.kind === 'Lost' ? 'Lost' : 'Damaged';
  const after = await transaction((conn) => moveStock(conn, name, -qty, { type: kind, note: text(b.note, 255) || null, userId: req.user.user_id }));
  res.json({ quantity: after, message: 'Stock goes down. Entry saved.' });
});

module.exports = router;
