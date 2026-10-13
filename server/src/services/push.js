// Push notifications to phones (step 36) with Firebase Cloud Messaging (HTTP v1 API).
// Turned on when server/.env has FIREBASE_SERVICE_ACCOUNT=path\to\service-account.json
// (Firebase console > Project settings > Service accounts > Generate new private key).
// Without it, nothing is sent: the app still gets every alert in the app (bell and banner).
const fs = require('fs');
const jwt = require('jsonwebtoken');
const { query } = require('../db');

let creds; // undefined = not read yet, false = push off
let access = { token: null, exp: 0 };

function credentials() {
  if (creds !== undefined) return creds;
  const file = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!file) return (creds = false);
  try {
    creds = JSON.parse(fs.readFileSync(file, 'utf8'));
    console.log(`[push] Firebase project ${creds.project_id}: push notifications on`);
  } catch (err) {
    console.error(`[push] cannot read FIREBASE_SERVICE_ACCOUNT (${err.message}); push notifications off`);
    creds = false;
  }
  return creds;
}

const enabled = () => !!credentials();

async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  if (access.token && access.exp - 60 > now) return access.token;
  const c = credentials();
  const assertion = jwt.sign(
    { iss: c.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 },
    c.private_key,
    { algorithm: 'RS256' }
  );
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${assertion}`,
  });
  if (!res.ok) throw new Error(`token ${res.status}`);
  const d = await res.json();
  access = { token: d.access_token, exp: now + (d.expires_in || 3600) };
  return access.token;
}

async function deliver({ userId, guestToken, title, message, type, orderId }) {
  const rows = userId
    ? await query('SELECT push_token FROM device_tokens WHERE user_id = ?', [userId])
    : await query('SELECT push_token FROM device_tokens WHERE guest_token = ?', [guestToken]);
  if (!rows.length) return;
  const token = await accessToken();
  const c = credentials();
  for (const r of rows) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${c.project_id}/messages:send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          token: r.push_token,
          notification: { title, body: message },
          data: { type: String(type || ''), orderId: orderId ? String(orderId) : '' },
          android: { priority: 'high' },
        },
      }),
    });
    if (res.status === 404 || res.status === 400) {
      // The phone uninstalled the app or the token expired.
      await query('DELETE FROM device_tokens WHERE push_token = ?', [r.push_token]);
    }
  }
}

/** Sends a push to the phones of one account or guest. Never throws and never slows the request. */
function send(n) {
  if (!enabled() || (!n.userId && !n.guestToken)) return;
  setTimeout(() => deliver(n).catch((err) => console.error('[push]', err.message)), 300);
}

module.exports = { send, enabled };
