// Live Map (step 34; Admin Orders 7, Staff 9): the rider marker and the order pins of the orders on
// the road. Staff can see and call; no order changes here.
const { Router } = require('express');
const { query } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { stationPoint } = require('../services/orders');
const { now } = require('../services/time');

const router = Router();
router.use(requireAuth, requireRole('Owner', 'Staff'));

// GET /api/map -> { station, riders: [...], orders: [...] }
router.get('/', async (req, res) => {
  const station = await stationPoint();
  const orders = await query(
    `SELECT o.order_id, o.customer_name, o.quantity, o.order_type, o.status, o.rider_id, o.delivery_address_text,
       o.delivery_latitude AS lat, o.delivery_longitude AS lng, o.contact_phone
     FROM orders o WHERE o.status = 'Out for Delivery' ORDER BY o.out_at, o.order_id`
  );
  const riderIds = [...new Set(orders.map((o) => o.rider_id).filter(Boolean))];
  const riders = riderIds.length
    ? await query(
        `SELECT u.user_id, u.full_name, u.role, u.phone_number, l.latitude, l.longitude, l.updated_at, l.is_sharing
         FROM users u LEFT JOIN rider_locations l ON l.rider_id = u.user_id WHERE u.user_id IN (?)`,
        [riderIds]
      )
    : [];
  const t = now().getTime();
  res.json({
    station: { lat: station.lat, lng: station.lng },
    riders: riders.map((r) => ({
      id: r.user_id,
      name: r.role === 'Owner' ? 'Owner' : r.full_name,
      phone: r.phone_number,
      lat: r.latitude === null ? null : Number(r.latitude),
      lng: r.longitude === null ? null : Number(r.longitude),
      updatedAt: r.updated_at,
      minutesAgo: r.updated_at ? Math.max(0, Math.round((t - new Date(r.updated_at).getTime()) / 60000)) : null,
      orders: orders.filter((o) => o.rider_id === r.user_id).map((o) => o.order_id),
    })),
    orders: orders.map((o, i) => ({
      n: i + 1,
      id: o.order_id,
      name: o.customer_name || 'Guest',
      phone: o.contact_phone || '',
      quantity: o.quantity,
      type: o.order_type,
      status: o.status,
      riderId: o.rider_id,
      address: o.delivery_address_text || '',
      lat: o.lat === null ? null : Number(o.lat),
      lng: o.lng === null ? null : Number(o.lng),
    })),
  });
});

module.exports = router;
