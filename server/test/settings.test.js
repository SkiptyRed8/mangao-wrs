const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { freshDb, api, closeDb, loginAs } = require('./helpers');
const { one } = require('../src/db');

let owner;
before(async () => {
  await freshDb();
  owner = await loginAs('09170000001', 'owner123');
});
after(closeDb);
const asOwner = (req) => req.set('Authorization', `Bearer ${owner}`);

describe('Prices & Settings (FR-09, Admin More 3)', () => {
  test('price list for everyone (P30 / P35 / P150)', async () => {
    const r = await api().get('/api/settings/prices');
    assert.deepEqual(r.body.prices, { walkIn: 30, delivery: 35, package: 150 });
  });

  test('owner sees all settings; others cannot', async () => {
    const r = await asOwner(api().get('/api/settings'));
    assert.equal(r.body.tankLimit, 60);
    assert.deepEqual(r.body.lowStock, { gallons: 30, seals: 60 });
    assert.ok(r.body.station.lat);
    const staff = await loginAs('09170000002', 'staff123');
    assert.equal((await api().get('/api/settings').set('Authorization', `Bearer ${staff}`)).status, 403);
  });

  test('edit prices keeps the history; only changed prices get a new row', async () => {
    const r = await asOwner(api().put('/api/settings/prices')).send({ walkIn: 30, delivery: 40, package: 150 });
    assert.equal(r.body.message, 'Applies to new orders only.');
    assert.deepEqual(r.body.prices, { walkIn: 30, delivery: 40, package: 150 });
    const n = await one("SELECT COUNT(*) AS n FROM prices WHERE item_type = 'Refill Delivery'");
    assert.equal(n.n, 2);
    const w = await one("SELECT COUNT(*) AS n FROM prices WHERE item_type = 'Refill Walk-in'");
    assert.equal(w.n, 1);
    const bad = await asOwner(api().put('/api/settings/prices')).send({ walkIn: 0, delivery: 40, package: 150 });
    assert.equal(bad.body.error.title, 'Price not valid');
  });

  test('tank limit also changes the running count', async () => {
    const r = await asOwner(api().put('/api/settings/tank-limit')).send({ tankLimit: 70 });
    assert.equal(r.body.tankLimit, 70);
    assert.equal(r.body.message, 'Alert uses the new number.');
    const c = await one('SELECT tank_limit FROM tank_cycles WHERE ended_at IS NULL');
    assert.equal(c.tank_limit, 70);
    assert.equal((await asOwner(api().put('/api/settings/tank-limit')).send({ tankLimit: 0 })).status, 400);
  });

  test('low-stock levels and station location', async () => {
    const l = await asOwner(api().put('/api/settings/low-stock')).send({ gallons: 40, seals: 80 });
    assert.deepEqual(l.body.lowStock, { gallons: 40, seals: 80 });
    assert.equal(l.body.message, 'Warnings use the new levels.');
    const p = await asOwner(api().put('/api/settings/location')).send({ lat: 14.7, lng: 121.09 });
    assert.equal(p.body.station.lat, 14.7);
    assert.equal(p.body.message, 'Distances use the new location.');
    assert.equal((await asOwner(api().put('/api/settings/location')).send({ lat: 0, lng: 0 })).status, 400);
  });
});

describe('Station address and pin (Oct 14)', () => {
  test('new database has the station address and Riverside Street pin; the owner can change the address', async () => {
    const { loginAs } = require('./helpers');
    const owner = await loginAs('09170000001', 'owner123');
    const s = await api().get('/api/settings').set('Authorization', `Bearer ${owner}`);
    assert.equal(s.body.station.address, '98 Riverside Street, Barangay Commonwealth, Quezon City');
    const r = await api().put('/api/settings/location').set('Authorization', `Bearer ${owner}`)
      .send({ lat: 14.6931, lng: 121.0875, address: '98 Riverside St., Brgy. Commonwealth, QC' });
    assert.equal(r.status, 200);
    assert.equal(r.body.station.address, '98 Riverside St., Brgy. Commonwealth, QC');
    const empty = await api().put('/api/settings/location').set('Authorization', `Bearer ${owner}`).send({ lat: 14.6931, lng: 121.0875, address: ' ' });
    assert.equal(empty.body.error.title, 'Address missing');
    const map = await api().get('/api/map').set('Authorization', `Bearer ${owner}`);
    assert.equal(map.body.station.address, '98 Riverside St., Brgy. Commonwealth, QC');
  });

  test('an older database gets the address column; the old placeholder pin moves to Riverside Street', async () => {
    const { query, one } = require('../src/db');
    await query('ALTER TABLE station_settings DROP COLUMN station_address');
    await query('UPDATE station_settings SET station_latitude = 14.6976, station_longitude = 121.0886 WHERE setting_id = 1');
    const { migrate } = require('../src/services/migrate');
    assert.deepEqual(await migrate(), ['station address', 'station pin on Riverside Street']);
    const s = await one('SELECT * FROM station_settings WHERE setting_id = 1');
    assert.equal(s.station_address, '98 Riverside Street, Barangay Commonwealth, Quezon City');
    assert.equal(Number(s.station_latitude), 14.692823);
    assert.deepEqual(await migrate(), [], 'second run changes nothing');
  });
});
