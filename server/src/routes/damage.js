// Report Damaged Gallon (FR-18; UC-10; Rider 4, Staff 2/5, Admin Orders 5). The owner, staff or the
// order's rider sends a photo and a note. The server saves the photo, takes one new gallon from stock
// as the replacement ("Damaged customer gallon replaced"), adds it to the order's timeline and alerts
// the owner. The order continues.
//  POST /api/damage { orderId, photo (base64 JPEG/PNG, data: prefix allowed), note } -> { report, message }
//  GET  /api/damage?orderId= -> { reports }
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Router } = require('express');
const { one, query, transaction } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad, notFound, forbidden } = require('../utils/errors');
const { text } = require('../utils/validate');
const { now } = require('../services/time');
const { moveStock } = require('../services/process');
const { addHistory, notifyOwner } = require('../services/orders');
const realtime = require('../services/realtime');

const router = Router();
router.use(requireAuth, requireRole('Owner', 'Staff', 'Rider'));

const UPLOADS = path.join(__dirname, '..', '..', 'uploads');
const DIR = path.join(UPLOADS, 'damage');
const MAX_BYTES = 3 * 1024 * 1024;

function readPhoto(raw) {
  if (!raw) throw bad('PHOTO_MISSING', 'Photo missing', 'Take a photo of the damaged gallon.', { field: 'photo' });
  const m = /^data:image\/(jpeg|jpg|png|webp);base64,/.exec(String(raw));
  const buf = Buffer.from(m ? String(raw).slice(m[0].length) : String(raw), 'base64');
  let ext = null;
  if (buf[0] === 0xff && buf[1] === 0xd8) ext = 'jpg';
  else if (buf.slice(0, 4).toString('hex') === '89504e47') ext = 'png';
  else if (buf.slice(0, 4).toString() === 'RIFF' && buf.slice(8, 12).toString() === 'WEBP') ext = 'webp';
  if (!ext) throw bad('PHOTO_INVALID', 'Photo not valid', 'Use a JPG or PNG photo.', { field: 'photo' });
  if (buf.length > MAX_BYTES) throw bad('PHOTO_TOO_BIG', 'Photo too big', 'Use a photo under 3 MB.', { field: 'photo' });
  return { buf, ext };
}

const shape = (r) => ({
  id: r.report_id,
  orderId: r.order_id,
  name: r.customer_name || '',
  note: r.note || '',
  photo: r.photo_path ? `/uploads/${r.photo_path}` : null,
  by: r.role === 'Owner' ? 'Owner' : r.full_name || '',
  at: r.created_at,
});

router.get('/', async (req, res) => {
  const params = [];
  let where = '';
  if (req.query.orderId) {
    where = 'WHERE d.order_id = ?';
    params.push(Number(req.query.orderId) || 0);
  } else if (req.user.role !== 'Owner') {
    throw forbidden('NOT_ALLOWED', 'Not allowed', 'Open the order to see its reports.');
  }
  const rows = await query(
    `SELECT d.*, u.full_name, u.role FROM damage_reports d LEFT JOIN users u ON u.user_id = d.reported_by ${where} ORDER BY d.created_at DESC LIMIT 200`,
    params
  );
  res.json({ reports: rows.map(shape) });
});

router.post('/', async (req, res) => {
  const b = req.body || {};
  const order = await one('SELECT * FROM orders WHERE order_id = ?', [Number(b.orderId) || 0]);
  if (!order) throw notFound('ORDER_NOT_FOUND', 'Order not found', 'It may have been removed.');
  if (req.user.role === 'Rider' && order.rider_id !== req.user.user_id) {
    throw forbidden('NOT_YOUR_ORDER', 'Not your delivery', 'Only the rider of this order can report it.');
  }
  if (['Declined', 'Cancelled'].includes(order.status)) {
    throw bad('ORDER_CLOSED', 'Order is closed', 'This order was declined or cancelled.');
  }
  const photo = readPhoto(b.photo);
  const note = text(b.note, 255);
  if (!note) throw bad('NOTE_MISSING', 'Note missing', 'Write what is damaged, e.g. cracked at the handle.', { field: 'note' });

  fs.mkdirSync(DIR, { recursive: true });
  const file = `${crypto.randomBytes(16).toString('hex')}.${photo.ext}`;
  fs.writeFileSync(path.join(DIR, file), photo.buf);

  const name = order.customer_name || (order.order_source === 'Walk-in' ? 'Walk-in' : 'Guest');
  const reporter = req.user.role === 'Owner' ? 'Owner' : req.user.full_name;
  const t = now();
  let replaced = true;
  const id = await transaction(async (conn) => {
    const [r] = await conn.query(
      'INSERT INTO damage_reports (order_id, customer_name, reported_by, photo_path, note, created_at) VALUES (?, ?, ?, ?, ?, ?)',
      [order.order_id, name, req.user.user_id, `damage/${file}`, note, t]
    );
    const [[stock]] = await conn.query("SELECT quantity_on_hand AS n FROM inventory_items WHERE item_name = 'New Gallon' FOR UPDATE");
    if (stock.n >= 1) {
      await moveStock(conn, 'New Gallon', -1, { type: 'Damaged', note: 'Damaged customer gallon replaced', orderId: order.order_id, userId: req.user.user_id, at: t });
    } else {
      replaced = false;
    }
    await addHistory(conn, order.order_id, 'Damaged gallon', req.user.user_id, replaced ? `${note}. Replaced with a new gallon.` : `${note}. No new gallon in stock.`, t);
    if (req.user.role !== 'Owner') {
      await notifyOwner(conn, {
        type: 'Damaged Gallon',
        orderId: order.order_id,
        title: 'Damaged gallon',
        message: `${name} (order #${order.order_id}): ${note}. Reported by ${reporter}.`,
      });
    }
    return r.insertId;
  });
  realtime.orderChanged(order.order_id);
  realtime.ownerRefresh('stock');
  const row = await one('SELECT d.*, u.full_name, u.role FROM damage_reports d LEFT JOIN users u ON u.user_id = d.reported_by WHERE d.report_id = ?', [id]);
  res.status(201).json({
    report: shape(row),
    replaced,
    message: replaced
      ? req.user.role === 'Owner'
        ? 'Saved. A new gallon replaces it.'
        : 'Sent to the owner. A new gallon replaces it.'
      : 'Saved. No new gallon in stock: add stock to replace it.',
  });
});

module.exports = router;
module.exports.UPLOADS = UPLOADS;
