// Shared test setup: a separate database (mangao_wrs_test) rebuilt with the demo data.
// The same tests run against the Java server when API_URL is set (e.g. API_URL=http://localhost:3199):
// the clock is sent per request in the X-Test-Now header (the Java server reads it only in test mode).
process.env.NODE_ENV = 'test';
process.env.DB_NAME = process.env.TEST_DB_NAME || 'mangao_wrs_test';

const request = require('supertest');
const { setupDatabase } = require('../scripts/setup-db');

const API_URL = process.env.API_URL || null;
let testNow = null;

async function freshDb() {
  await setupDatabase({ demo: true, database: process.env.DB_NAME, quiet: true });
  if (API_URL) await request(API_URL).post('/__test/reset-pool').send({});
}

/** supertest for the server; with API_URL every request carries the test clock. */
function api() {
  if (!API_URL) return request(require('../src/app'));
  const agent = request(API_URL);
  const wrap = {};
  for (const m of ['get', 'post', 'put', 'delete', 'patch']) {
    wrap[m] = (path) => {
      const r = agent[m](path);
      return testNow ? r.set('X-Test-Now', testNow) : r;
    };
  }
  return wrap;
}

/** For tests: a fixed time ('2026-10-14T09:20:00+08:00' or a Date), or null for the real clock. */
function setNow(iso) {
  testNow = iso ? (iso instanceof Date ? iso.toISOString() : String(iso)) : null;
  if (!API_URL) require('../src/services/time').setNow(iso);
}

/** Runs the start-up database update (services/migrate). */
async function migrateDb() {
  if (API_URL) return (await request(API_URL).post('/__test/migrate').send({})).body.done;
  return require('../src/services/migrate').migrate();
}

async function closeDb() {
  await require('../src/db').pool.end();
}

async function loginAs(phone, password) {
  const res = await api().post('/api/auth/login').send({ phone, password });
  return res.body.token;
}

module.exports = { freshDb, api, closeDb, loginAs, setNow, migrateDb, API_URL };
