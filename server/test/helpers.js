// Shared test setup: a separate database (mangao_wrs_test) rebuilt with the demo data.
process.env.NODE_ENV = 'test';
process.env.DB_NAME = process.env.TEST_DB_NAME || 'mangao_wrs_test';

const request = require('supertest');
const { setupDatabase } = require('../scripts/setup-db');

async function freshDb() {
  await setupDatabase({ demo: true, database: process.env.DB_NAME, quiet: true });
}

const api = () => request(require('../src/app'));

async function closeDb() {
  await require('../src/db').pool.end();
}

module.exports = { freshDb, api, closeDb };

async function loginAs(phone, password) {
  const res = await api().post('/api/auth/login').send({ phone, password });
  return res.body.token;
}

module.exports.loginAs = loginAs;
