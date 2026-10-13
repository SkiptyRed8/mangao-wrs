// Sends emails (the forgot-password code) through Gmail SMTP with nodemailer.
// While SMTP_USER is empty in .env, nothing is sent: the code is printed in the server window
// and, outside production, also returned to the app so the flow can be shown in a demo.
const nodemailer = require('nodemailer');
const config = require('../config');

const mailReady = () => !!(config.mail.user && config.mail.pass);

let transport = null;
function getTransport() {
  if (!transport) {
    transport = nodemailer.createTransport({
      host: config.mail.host,
      port: config.mail.port,
      secure: config.mail.port === 465,
      auth: { user: config.mail.user, pass: config.mail.pass },
    });
  }
  return transport;
}

/** a.lim@gmail.com -> a••••@gmail.com */
function maskEmail(email) {
  const [name, domain] = String(email).split('@');
  if (!domain) return email;
  return `${name.slice(0, 1)}••••@${domain}`;
}

/** Sends the 6-digit reset code. Returns { sent: true } or { sent: false } when email is not set up. */
async function sendResetCode(to, name, code) {
  if (!mailReady()) {
    if (config.env !== 'test') console.log(`[email not set up] password reset code for ${to}: ${code}`);
    return { sent: false };
  }
  await getTransport().sendMail({
    from: config.mail.from,
    to,
    subject: `${code} is your Mangao password reset code`,
    text:
      `Hi ${name},\n\n` +
      `Your code to reset your password is ${code}.\n` +
      'It works for 10 minutes. If you did not ask for this, you can ignore this email.\n\n' +
      'Mangao Water Refilling Station',
    html:
      `<p>Hi ${escapeHtml(name)},</p>` +
      `<p>Your code to reset your password is</p><p style="font-size:28px;font-weight:700;letter-spacing:6px">${code}</p>` +
      '<p>It works for 10 minutes. If you did not ask for this, you can ignore this email.</p>' +
      '<p>Mangao Water Refilling Station</p>',
  });
  return { sent: true };
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

module.exports = { mailReady, maskEmail, sendResetCode };
