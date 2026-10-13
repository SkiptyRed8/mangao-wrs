// Current prices (newest row of each item) and station settings.
const { query, one } = require('../db');

const ITEMS = { 'Refill Walk-in': 'walkIn', 'Refill Delivery': 'delivery', Package: 'package' };

async function currentPrices(conn) {
  const run = conn ? (sql, p) => conn.query(sql, p).then(([r]) => r) : query;
  const rows = await run(
    `SELECT p.item_type, p.amount FROM prices p
     JOIN (SELECT item_type, MAX(price_id) AS id FROM prices GROUP BY item_type) n ON n.id = p.price_id`
  );
  const out = { walkIn: 0, delivery: 0, package: 0 };
  for (const r of rows) out[ITEMS[r.item_type]] = Number(r.amount);
  return out;
}

async function stationSettings() {
  const s = await one('SELECT * FROM station_settings WHERE setting_id = 1');
  const items = await query('SELECT item_name, low_stock_level FROM inventory_items');
  const level = (name) => (items.find((i) => i.item_name === name) || {}).low_stock_level || 0;
  return {
    tankLimit: s.tank_limit,
    sealsPerGallon: s.seals_per_gallon,
    lowStock: { gallons: level('New Gallon'), seals: level('Seal') },
    station: {
      lat: s.station_latitude === null ? null : Number(s.station_latitude),
      lng: s.station_longitude === null ? null : Number(s.station_longitude),
      phone: s.station_phone || '',
    },
  };
}

module.exports = { ITEMS, currentPrices, stationSettings };
