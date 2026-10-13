// MySQL connection pool and small helpers. Times are Philippine time (+08:00).
const mysql = require('mysql2/promise');
const config = require('./config');

const pool = mysql.createPool({
  ...config.db,
  waitForConnections: true,
  connectionLimit: 10,
  timezone: '+08:00',
  dateStrings: false,
  decimalNumbers: true,
});

pool.on('connection', (conn) => conn.query("SET time_zone = '+08:00'"));

/** Rows of a SELECT (or the result of other statements). */
async function query(sql, params = []) {
  const [rows] = await pool.query(sql, params);
  return rows;
}

/** First row of a SELECT, or null. */
async function one(sql, params = []) {
  const rows = await query(sql, params);
  return rows[0] || null;
}

/** Runs fn(conn) in one transaction; rolls back if it throws. */
async function transaction(fn) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const result = await fn(conn);
    await conn.commit();
    return result;
  } catch (err) {
    await conn.rollback().catch(() => {});
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = { pool, query, one, transaction };
