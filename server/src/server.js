// Starts the API: npm run dev (restarts on code changes) or npm start.
const http = require('http');
const config = require('./config');
const app = require('./app');
const realtime = require('./services/realtime');

const server = http.createServer(app);
realtime.attach(server); // Socket.IO for real-time updates (step 35)

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`Port ${config.port} is already used by another program. Close the other server window and try again.`);
    process.exit(1);
  }
  throw err;
});

server.listen(config.port, () => {
  console.log(`Mangao WRS API running on http://localhost:${config.port}  (health check: /health)`);
  require('./services/migrate')
    .migrate()
    .then((done) => done.length && console.log(`[database] updated: ${done.join(', ')}`))
    .catch((err) => console.error('[database] update skipped:', err.message));
  const m = config.mail;
  if (m.user && m.pass) {
    const [name, domain] = m.user.split('@');
    console.log(`[email] Gmail account: ${name.slice(0, 2)}****@${domain || '?'} · App Password: ${m.pass.length} letters${m.pass.length === 16 ? '' : ' (should be 16)'}`);
  } else {
    console.log('[email] not set up: reset codes are printed here instead of emailed');
  }
});

module.exports = server;
