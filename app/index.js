const express = require('express');
const { Pool } = require('pg');
const client = require('prom-client');

const app = express();
const PORT = process.env.PORT || 80;

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl: { rejectUnauthorized: false },
});

// ---------- Prometheus metrics ----------
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [register],
});
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  registers: [register],
});

app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const labels = { method: req.method, route: req.path, status: res.statusCode };
    httpRequestsTotal.inc(labels);
    end(labels);
  });
  next();
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
// -----------------------------------------

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.get('/', async (req, res) => {
  try {
    const result = await pool.query('SELECT NOW() as current_time');
    res.json({
      message: 'Hello from EKS! Connected to RDS Postgres.',
      db_time: result.rows[0].current_time,
      hostname: require('os').hostname(),
    });
  } catch (err) {
    res.status(500).json({ error: 'DB connection failed', details: err.message });
  }
});

// Only start listening when run directly (`node index.js`), not when
// required by tests (`require('./index')` in index.test.js). This is the
// standard Express pattern for making an app testable with supertest
// without needing a real network port or real DB connection in CI.
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`App listening on port ${PORT}`);
  });
}

module.exports = { app, pool };