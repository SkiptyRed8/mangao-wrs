// Delivery addresses (Customer 3A, Customer 7): pinned on the map or typed.
// Customers are in Quezon City, so only house / unit no., block / lot, street and barangay are asked.
const BARANGAYS = require('../data/qc-barangays.json');
const { bad } = require('../utils/errors');
const { text } = require('../utils/validate');
const { addressText } = require('./orders');

const byLower = new Map(BARANGAYS.map((b) => [b.toLowerCase(), b]));

/** Philippines box; the pin must be on land near Metro Manila to be used. */
const inArea = (lat, lng) => lat > 14.3 && lat < 15.0 && lng > 120.8 && lng < 121.3;

/**
 * Reads { mode: 'pin'|'typed', house, blockLot, street, barangay, landmark, lat, lng } and returns the
 * clean fields plus the one-line text. Pinned: lat/lng needed (street and barangay come from the map).
 * Typed: house, street and barangay needed.
 */
function readAddress(b = {}) {
  const pinned = b.mode === 'pin';
  const a = {
    pinned,
    house: text(b.house, 20),
    blockLot: text(b.blockLot, 30),
    street: text(b.street, 100),
    barangay: text(b.barangay, 60),
    landmark: text(b.landmark, 150),
    lat: b.lat === null || b.lat === undefined || b.lat === '' ? null : Number(b.lat),
    lng: b.lng === null || b.lng === undefined || b.lng === '' ? null : Number(b.lng),
  };
  if (a.barangay) a.barangay = byLower.get(a.barangay.toLowerCase()) || a.barangay;

  if (pinned) {
    if (!Number.isFinite(a.lat) || !Number.isFinite(a.lng)) {
      throw bad('PIN_MISSING', 'Pin missing', 'Move the map to place the pin.', { field: 'pin' });
    }
    if (!inArea(a.lat, a.lng)) throw bad('OUTSIDE_AREA', 'Outside delivery area', 'Place the pin in Quezon City.', { field: 'pin' });
  } else {
    const missing = [];
    if (!a.house) missing.push('house');
    if (!a.street) missing.push('street');
    if (!a.barangay) missing.push('barangay');
    if (missing.length) {
      throw bad('ADDRESS_MISSING', 'Fill in the missing fields', 'House / unit no., Street and Barangay are needed', { fields: missing });
    }
    if (!byLower.has(a.barangay.toLowerCase())) {
      throw bad('BARANGAY_UNKNOWN', 'Choose a barangay', 'Pick it from the Quezon City list.', { fields: ['barangay'] });
    }
    if (!Number.isFinite(a.lat) || !Number.isFinite(a.lng) || !inArea(a.lat, a.lng)) {
      a.lat = null;
      a.lng = null;
    }
  }
  a.text = addressText(a);
  return a;
}

/** A saved address row -> the app's address object. */
function shapeAddress(r) {
  const a = {
    id: r.address_id,
    name: r.address_name,
    house: r.house_unit_no || '',
    blockLot: r.block_lot || '',
    street: r.street || '',
    barangay: r.barangay || '',
    city: r.city,
    landmark: r.landmark || '',
    lat: r.latitude === null ? null : Number(r.latitude),
    lng: r.longitude === null ? null : Number(r.longitude),
  };
  a.mode = a.house ? 'typed' : 'pin';
  a.pinned = a.mode === 'pin';
  a.text = addressText(a);
  return a;
}

module.exports = { BARANGAYS, readAddress, shapeAddress, inArea };
