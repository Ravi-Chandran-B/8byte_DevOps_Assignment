// Mock the 'pg' Pool BEFORE requiring index.js, so app.js never opens a
// real DB connection during tests — this is what makes `npm test` work
// in CI without needing RDS reachable from GitHub Actions runners.
jest.mock('pg', () => {
  const mPool = {
    query: jest.fn(),
  };
  return { Pool: jest.fn(() => mPool) };
});

const request = require('supertest');
const { app, pool } = require('./index');

describe('GET /health', () => {
  it('returns 200 and status ok', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });
});

describe('GET /metrics', () => {
  it('returns 200 and Prometheus-format text', async () => {
    const res = await request(app).get('/metrics');
    expect(res.statusCode).toBe(200);
    expect(res.text).toContain('http_requests_total');
    expect(res.headers['content-type']).toMatch(/text/);
  });

  it('increments http_requests_total after a request', async () => {
    await request(app).get('/health');
    const res = await request(app).get('/metrics');
    expect(res.text).toMatch(/http_requests_total\{.*route="\/health".*\}\s+\d+/);
  });
});

describe('GET /', () => {
  it('returns 200 with db_time and hostname when DB query succeeds', async () => {
    pool.query.mockResolvedValueOnce({
      rows: [{ current_time: '2026-08-29T00:00:00.000Z' }],
    });

    const res = await request(app).get('/');
    expect(res.statusCode).toBe(200);
    expect(res.body.message).toMatch(/Hello from EKS/);
    expect(res.body.db_time).toBe('2026-08-29T00:00:00.000Z');
    expect(res.body.hostname).toBeDefined();
  });

  it('returns 500 with an error message when the DB query fails', async () => {
    pool.query.mockRejectedValueOnce(new Error('connection refused'));

    const res = await request(app).get('/');
    expect(res.statusCode).toBe(500);
    expect(res.body.error).toBe('DB connection failed');
    expect(res.body.details).toBe('connection refused');
  });
});