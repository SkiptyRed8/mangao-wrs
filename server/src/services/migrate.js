// Small changes to an existing database, run when the server starts, so a laptop that already has
// data does not need RESET-DEMO-DATA.bat. Each change checks first, so running it again does nothing.
const { one, query } = require('../db');

const STATION_ADDRESS = '98 Riverside Street, Barangay Commonwealth, Quezon City';
const STATION_PIN = { lat: 14.6928230, lng: 121.0871699 };
// Placeholder pin used before Oct 14 (center of Commonwealth), replaced by the station's street.
const OLD_PIN = { lat: 14.6976, lng: 121.0886 };

async function columnExists(table, column) {
  const r = await one(
    'SELECT COUNT(*) AS c FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?',
    [table, column]
  );
  return Number(r.c) > 0;
}

async function migrate() {
  const done = [];
  if (!(await columnExists('station_settings', 'station_address'))) {
    await query("ALTER TABLE station_settings ADD COLUMN station_address VARCHAR(255) NULL COMMENT 'Shown on reports and the live map' AFTER station_phone");
    await query('UPDATE station_settings SET station_address = ? WHERE setting_id = 1 AND station_address IS NULL', [STATION_ADDRESS]);
    done.push('station address');
    const s = await one('SELECT station_latitude AS lat, station_longitude AS lng FROM station_settings WHERE setting_id = 1');
    const old = s && (s.lat === null || (Math.abs(Number(s.lat) - OLD_PIN.lat) < 1e-6 && Math.abs(Number(s.lng) - OLD_PIN.lng) < 1e-6));
    if (old) {
      await query('UPDATE station_settings SET station_latitude = ?, station_longitude = ? WHERE setting_id = 1', [STATION_PIN.lat, STATION_PIN.lng]);
      done.push('station pin on Riverside Street');
    }
  }
  return done;
}

module.exports = { migrate, STATION_ADDRESS, STATION_PIN };
