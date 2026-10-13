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
});

module.exports = server;
