// The Express app: routes are added here as each step is built.
const express = require('express');
const cors = require('cors');
const { notFoundRoute, errorHandler } = require('./utils/errors');

const app = express();
app.use(cors());
app.use(express.json({ limit: '5mb' }));

app.get('/', (req, res) => res.json({ app: 'Mangao WRS API', health: '/health' }));
app.use('/health', require('./routes/health'));
app.use('/api/auth', require('./routes/auth'));
app.use('/api/account', require('./routes/account'));
app.use('/api/staff', require('./routes/staff'));
app.use('/api/settings', require('./routes/settings'));

app.use(notFoundRoute);
app.use(errorHandler);

module.exports = app;
