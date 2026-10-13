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
app.use('/api/geo', require('./routes/geo'));
app.use('/api/addresses', require('./routes/addresses'));
app.use('/api/orders', require('./routes/orders'));
app.use('/api/admin/orders', require('./routes/admin-orders'));
app.use('/api/admin/home', require('./routes/admin-home'));
app.use('/api/work', require('./routes/work'));
app.use('/api/rider', require('./routes/rider'));
app.use('/api/inventory', require('./routes/inventory'));
app.use('/api/sales', require('./routes/sales'));
app.use('/api/notifications', require('./routes/notifications'));
app.use('/api/map', require('./routes/map'));
app.use('/api/export', require('./routes/export'));
app.use('/api/loans', require('./routes/loans'));
app.use('/api/damage', require('./routes/damage'));
// Damaged-gallon photos (random file names).
app.use('/uploads', express.static(require('./routes/damage').UPLOADS, { maxAge: '7d', index: false }));

app.use(notFoundRoute);
app.use(errorHandler);

module.exports = app;
