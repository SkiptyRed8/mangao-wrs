// Real-time updates (Socket.IO, step 35) and the live rider location (step 34).
// The app connects with its log-in token (or the guest phone code) and joins rooms:
//   user:<id>, role:<Owner|Staff|Rider|Customer>, guest:<code>.
// Events the app listens to:
//   order         { id, status }            an order changed: lists and details reload
//   notification  { title, message, type, orderId }   shown as a banner (push on the web)
//   location      { riderId, lat, lng, at, sharing }   rider moved (live map)
// When the server runs without sockets (automatic tests), every function does nothing.
const jwt = require('jsonwebtoken');
const config = require('../config');
const { query, one } = require('../db');

let io = null;
const pending = new Map(); // orderId -> timer (several changes in one request make one event)

function attach(httpServer) {
  const { Server } = require('socket.io');
  io = new Server(httpServer, { cors: { origin: '*' } });
  io.use(async (socket, next) => {
    try {
      const { token, guest } = socket.handshake.auth || {};
      if (token) {
        const p = jwt.verify(token, config.jwtSecret);
        const u = await one('SELECT user_id, role, is_active FROM users WHERE user_id = ?', [p.sub]);
        if (!u || !u.is_active) return next(new Error('Session ended'));
        socket.data.user = u;
      } else if (typeof guest === 'string' && /^[A-Za-z0-9_-]{16,64}$/.test(guest)) {
        socket.data.guest = guest;
      } else {
        return next(new Error('Please log in'));
      }
      next();
    } catch {
      next(new Error('Session ended'));
    }
  });
  io.on('connection', (socket) => {
    const u = socket.data.user;
    if (u) {
      socket.join(`user:${u.user_id}`);
      socket.join(`role:${u.role}`);
    } else {
      socket.join(`guest:${socket.data.guest}`);
    }
  });
  return io;
}

const ready = () => io !== null;

/** Tells everyone who can see this order that it changed (owner, staff, its rider and its customer). */
function orderChanged(orderId) {
  if (!io || !orderId) return;
  clearTimeout(pending.get(orderId));
  // Wait for the database transaction to finish before the apps reload.
  pending.set(
    orderId,
    setTimeout(async () => {
      pending.delete(orderId);
      try {
        const o = await one('SELECT order_id, status, customer_id, guest_token, rider_id FROM orders WHERE order_id = ?', [orderId]);
        if (!o) return;
        const rooms = ['role:Owner', 'role:Staff'];
        if (o.customer_id) rooms.push(`user:${o.customer_id}`);
        else if (o.guest_token) rooms.push(`guest:${o.guest_token}`);
        if (o.rider_id) rooms.push(`user:${o.rider_id}`);
        io.to(rooms).emit('order', { id: o.order_id, status: o.status });
      } catch (err) {
        console.error('[realtime]', err.message);
      }
    }, 300)
  );
}

/** A new in-app notification for one account or guest phone. */
function notification({ userId, guestToken, title, message, type, orderId }) {
  if (!io) return;
  const room = userId ? `user:${userId}` : guestToken ? `guest:${guestToken}` : null;
  if (!room) return;
  setTimeout(() => io.to(room).emit('notification', { title, message, type, orderId: orderId || null }), 300);
}

/** Rider location: owner and staff, the rider, and the customers of the rider's orders on the road. */
async function location(riderId, payload) {
  if (!io) return;
  const rows = await query(
    "SELECT customer_id, guest_token FROM orders WHERE rider_id = ? AND status = 'Out for Delivery'",
    [riderId]
  );
  const rooms = new Set(['role:Owner', 'role:Staff', `user:${riderId}`]);
  for (const r of rows) rooms.add(r.customer_id ? `user:${r.customer_id}` : `guest:${r.guest_token}`);
  io.to([...rooms]).emit('location', { riderId, ...payload });
}

/** Something else the owner's screens show changed (stock, tank). */
function ownerRefresh(what) {
  if (!io) return;
  io.to(['role:Owner', 'role:Staff']).emit('refresh', { what });
}

module.exports = { attach, ready, orderChanged, notification, location, ownerRefresh };
