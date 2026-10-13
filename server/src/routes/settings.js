// Prices & Settings (FR-09, Admin More 3): prices (walk-in, delivery, package), tank limit,
// low-stock levels and the station location. New prices apply to new orders only:
// each order keeps a copy of the price it was made with.
const { Router } = require('express');
const { query, transaction } = require('../db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { bad } = require('../utils/errors');
const { int } = require('../utils/validate');
const { ITEMS, currentPrices, stationSettings } = require('../services/settings');

const router = Router();

// GET /api/settings/prices -> { prices } (anyone: customers and guests see the price list)
router.get('/prices', async (req, res) => {
  const s = await stationSettings();
  res.json({ prices: await currentPrices(), stationPhone: s.station.phone });
});

router.use(requireAuth, requireRole('Owner'));

// GET /api/settings -> { prices, tankLimit, lowStock, station }
router.get('/', async (req, res) => {
  res.json({ prices: await currentPrices(), ...(await stationSettings()) });
});

function money(v, label, key) {
  const n = Math.round(Number(v) * 100) / 100;
  if (!Number.isFinite(n) || n <= 0 || n > 10000) {
    throw bad('PRICE_INVALID', 'Price not valid', `Type a price above P0 for ${label}.`, { field: key });
  }
  return n;
}

// PUT /api/settings/prices { walkIn, delivery, package } -> { prices }
router.put('/prices', async (req, res) => {
  const b = req.body || {};
  const next = {
    walkIn: money(b.walkIn, 'Refill (walk-in)', 'walkIn'),
    delivery: money(b.delivery, 'Refill (delivery)', 'delivery'),
    package: money(b.package, 'Package', 'package'),
  };
  await transaction(async (conn) => {
    const now = await currentPrices(conn);
    for (const [item, key] of Object.entries(ITEMS)) {
      if (now[key] !== next[key]) {
        await conn.query('INSERT INTO prices (item_type, amount, set_by) VALUES (?, ?, ?)', [item, next[key], req.user.user_id]);
      }
    }
  });
  res.json({ prices: await currentPrices(), message: 'Applies to new orders only.' });
});

// PUT /api/settings/tank-limit { tankLimit } -> settings. The running count uses the new number.
router.put('/tank-limit', async (req, res) => {
  const limit = int((req.body || {}).tankLimit, 1, 1000);
  if (limit === null) throw bad('LIMIT_INVALID', 'Tank limit not valid', 'Type a whole number from 1 to 1000.', { field: 'tankLimit' });
  await transaction(async (conn) => {
    await conn.query('UPDATE station_settings SET tank_limit = ? WHERE setting_id = 1', [limit]);
    await conn.query('UPDATE tank_cycles SET tank_limit = ? WHERE ended_at IS NULL', [limit]);
  });
  res.json({ ...(await stationSettings()), message: 'Alert uses the new number.' });
});

// PUT /api/settings/low-stock { gallons, seals } -> settings
router.put('/low-stock', async (req, res) => {
  const b = req.body || {};
  const gallons = int(b.gallons, 0, 100000);
  const seals = int(b.seals, 0, 100000);
  if (gallons === null) throw bad('LEVEL_INVALID', 'Gallon level not valid', 'Type a whole number, 0 or more.', { field: 'gallons' });
  if (seals === null) throw bad('LEVEL_INVALID', 'Seal level not valid', 'Type a whole number, 0 or more.', { field: 'seals' });
  await query("UPDATE inventory_items SET low_stock_level = ? WHERE item_name = 'New Gallon'", [gallons]);
  await query("UPDATE inventory_items SET low_stock_level = ? WHERE item_name = 'Seal'", [seals]);
  res.json({ ...(await stationSettings()), message: 'Warnings use the new levels.' });
});

// PUT /api/settings/location { lat, lng } -> settings (Quezon City area)
router.put('/location', async (req, res) => {
  const lat = Number((req.body || {}).lat);
  const lng = Number((req.body || {}).lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < 4 || lat > 22 || lng < 116 || lng > 127) {
    throw bad('LOCATION_INVALID', 'Location not valid', 'Move the pin to the station and try again.');
  }
  await query('UPDATE station_settings SET station_latitude = ?, station_longitude = ? WHERE setting_id = 1', [
    lat.toFixed(7),
    lng.toFixed(7),
  ]);
  res.json({ ...(await stationSettings()), message: 'Distances use the new location.' });
});

module.exports = router;
