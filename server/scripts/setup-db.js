// Builds the database from database/schema.sql and sets the owner account from .env.
//   npm run db:setup   -> fresh database with the owner only
//   npm run db:demo    -> fresh database plus demo staff, rider, customer and starting stock
// The old database is removed through MySQL (DROP DATABASE). Never delete the folders in
// C:\xampp\mysql\data by hand - that breaks MySQL.
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
const config = require('../src/config');
const { normalizePhone, normalizeEmail } = require('../src/utils/validate');
const { dbHint, dbErrorText } = require('../src/utils/dbHints');

const SCHEMA = path.join(__dirname, '..', '..', 'database', 'schema.sql');

const DEMO_USERS = [
  { name: 'Joy Ramos', phone: '09170000002', email: 'joy.staff@example.com', password: 'staff123', role: 'Staff' },
  { name: 'Juan Dela Cruz', phone: '09170000003', email: 'juan.rider@example.com', password: 'rider123', role: 'Rider' },
  { name: 'Ana Lim', phone: '09172001111', email: 'ana@example.com', password: 'ana123', role: 'Customer' },
  { name: 'Maria Santos', phone: '09171234567', email: 'maria@example.com', password: 'maria123', role: 'Customer' },
  { name: 'Pedro Reyes', phone: '09172221010', email: 'pedro@example.com', password: 'pedro123', role: 'Customer' },
];

// Two new app orders waiting on the Order Board (owner: Accept or Decline).
const DEMO_ORDERS = [
  { phone: '09171234567', qty: 3, address: '8 Ilang-Ilang St., Holy Spirit', lat: 14.6826, lng: 121.0785, notes: 'Leave at the gate', mins: 12 },
  { phone: '09172221010', qty: 1, address: '5 Mabuhay St., Commonwealth', lat: 14.7031, lng: 121.0912, notes: null, mins: 5 },
];

async function setupDatabase({ demo = false, database = config.db.database, quiet = false } = {}) {
  const log = (...a) => !quiet && console.log(...a);
  if (!/^[A-Za-z0-9_]+$/.test(database)) throw new Error('DB_NAME may only use letters, numbers and _');
  const sql = fs
    .readFileSync(SCHEMA, 'utf8')
    .replace(/CREATE DATABASE IF NOT EXISTS mangao_wrs/g, `CREATE DATABASE IF NOT EXISTS \`${database}\``)
    .replace(/USE mangao_wrs;/g, `USE \`${database}\`;`);

  const conn = await mysql.createConnection({
    host: config.db.host,
    port: config.db.port,
    user: config.db.user,
    password: config.db.password,
    multipleStatements: true,
    timezone: '+08:00',
  });
  try {
    await conn.query("SET time_zone = '+08:00'");
    await conn.query(`DROP DATABASE IF EXISTS \`${database}\``);
    await conn.query(sql);
    log(`Database "${database}" created.`);

    const o = config.owner;
    await conn.query('UPDATE users SET full_name = ?, phone_number = ?, email = ?, password_hash = ? WHERE user_id = 1', [
      o.name,
      normalizePhone(o.phone),
      normalizeEmail(o.email),
      await bcrypt.hash(o.password, 10),
    ]);
    log(`Owner account: ${o.name} / ${normalizePhone(o.phone)} (password from server/.env)`);

    if (demo) {
      for (const u of DEMO_USERS) {
        await conn.query(
          'INSERT INTO users (full_name, phone_number, email, password_hash, role, privacy_consent_at) VALUES (?, ?, ?, ?, ?, ?)',
          [u.name, u.phone, u.email, await bcrypt.hash(u.password, 10), u.role, u.role === 'Customer' ? new Date() : null]
        );
      }
      const [[ana]] = await conn.query("SELECT user_id FROM users WHERE phone_number = '09172001111'");
      await conn.query(
        `INSERT INTO customer_addresses (customer_id, address_name, house_unit_no, street, barangay, landmark, latitude, longitude)
         VALUES (?, 'Home', '12', 'Malaya St.', 'Commonwealth', 'Near the plaza', 14.6976, 121.0886)`,
        [ana.user_id]
      );
      // Starting stock: 24 new gallons (low-stock level 30, so the alert shows) and 420 seals.
      await conn.query("UPDATE inventory_items SET quantity_on_hand = 24 WHERE item_name = 'New Gallon'");
      await conn.query("UPDATE inventory_items SET quantity_on_hand = 420 WHERE item_name = 'Seal'");
      await conn.query(
        `INSERT INTO stock_movements (item_id, recorded_by, movement_type, quantity_change, note)
         SELECT item_id, 1, 'Added', quantity_on_hand, 'Starting stock' FROM inventory_items`
      );
      // Station phone (address and pin come from schema.sql; the owner can move the pin in Prices & Settings).
      await conn.query(
        'UPDATE station_settings SET station_phone = ? WHERE setting_id = 1',
        [normalizePhone(o.phone)]
      );
      for (const d of DEMO_ORDERS) {
        const [[c]] = await conn.query('SELECT user_id, full_name FROM users WHERE phone_number = ?', [d.phone]);
        const at = new Date(Date.now() - d.mins * 60 * 1000);
        const [r] = await conn.query(
          `INSERT INTO orders (order_source, order_type, customer_id, customer_name, contact_phone, delivery_address_text,
             delivery_latitude, delivery_longitude, quantity, unit_price, total_amount, notes, status, payment_method, created_at)
           VALUES ('App', 'Refill', ?, ?, ?, ?, ?, ?, ?, 35, ?, ?, 'New', 'COD', ?)`,
          [c.user_id, c.full_name, d.phone, d.address, d.lat, d.lng, d.qty, 35 * d.qty, d.notes, at]
        );
        await conn.query(
          "INSERT INTO order_status_history (order_id, status, changed_by, changed_at) VALUES (?, 'Waiting for order to be accepted', ?, ?)",
          [r.insertId, c.user_id, at]
        );
      }
      log('Demo accounts (phone / password):');
      log(`  Owner    ${normalizePhone(o.phone)} / ${o.password}`);
      for (const u of DEMO_USERS) log(`  ${u.role.padEnd(8)} ${u.phone} / ${u.password}`);
    }
  } finally {
    await conn.end();
  }
}

module.exports = { setupDatabase, DEMO_USERS };

if (require.main === module) {
  setupDatabase({ demo: process.argv.includes('--demo') })
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(`Database setup failed: ${dbErrorText(err)}`);
      const hint = dbHint(err);
      if (hint) console.error(`What to do: ${hint}`);
      process.exit(1);
    });
}
