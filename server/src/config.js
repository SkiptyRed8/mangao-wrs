// Settings from server/.env (see .env.example).
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env'), quiet: true });

const env = process.env;

module.exports = {
  port: Number(env.PORT || 3100),
  env: env.NODE_ENV || 'development',
  jwtSecret: env.JWT_SECRET || 'dev-only-secret',
  db: {
    host: env.DB_HOST || 'localhost',
    port: Number(env.DB_PORT || 3306),
    user: env.DB_USER || 'root',
    password: env.DB_PASSWORD || '',
    database: env.DB_NAME || 'mangao_wrs',
  },
  owner: {
    name: env.OWNER_NAME || 'Ervin P. Mangao',
    phone: env.OWNER_PHONE || '09170000001',
    email: env.OWNER_EMAIL || 'owner@example.com',
    password: env.OWNER_PASSWORD || 'owner123',
  },
  mail: {
    host: env.SMTP_HOST || 'smtp.gmail.com',
    port: Number(env.SMTP_PORT || 465),
    user: env.SMTP_USER || '',
    pass: env.SMTP_PASS || '',
    from: env.MAIL_FROM || 'Mangao Water Refilling Station <no-reply@example.com>',
  },
};
