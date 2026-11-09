import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb } from '../src/db.js';
import { createApp } from '../src/app.js';
import { seedDemo } from '../src/seed.js';

let server, base;
before(async () => {
  const db = openDb();
  seedDemo(db);
  server = createApp({ db, secret: 't' }).listen(0);
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}/api/v1`;
});
after(() => server.close());

const call = async (method, path, { token, key, body } = {}) => {
  const r = await fetch(base + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token && { Authorization: `Bearer ${token}` }), ...(key && { 'X-API-Key': key }) },
    body: body && JSON.stringify(body),
  });
  return { status: r.status, headers: r.headers, json: r.status === 204 ? null : await r.json() };
};
const login = async (email, password) => (await call('POST', '/auth/login', { body: { email, password } })).json.token;

test('full flow: admin gates API access, owner creates key, website uses it', async () => {
  const admin = await login('admin@hostel.local', 'admin12345');
  const owner = await login('owner@demo.local', 'owner12345');

  // Admin creates a new hostel + owner; API access is OFF by default.
  const h = (await call('POST', '/admin/hostels', { token: admin, body: { name: 'New Hostel' } })).json;
  await call('POST', `/admin/hostels/${h.id}/users`, { token: admin, body: { email: 'new@h.local', password: 'password123' } });
  const newOwner = await login('new@h.local', 'password123');
  let r = await call('POST', '/me/api-keys', { token: newOwner, body: { name: 'site' } });
  assert.equal(r.status, 403);
  assert.equal(r.json.error.code, 'api_access_disabled');

  // Non-admin cannot use admin routes.
  assert.equal((await call('GET', '/admin/hostels', { token: owner })).status, 403);

  // Admin enables read-only students on a standard plan.
  await call('PUT', `/admin/hostels/${h.id}/subscription`, { token: admin, body: { plan: 'standard', cycle: 'monthly' } });
  await call('PUT', `/admin/hostels/${h.id}/api-access`, { token: admin, body: { enabled: true, scopes: ['students:read', 'bills:read'], rateLimit: 3 } });

  // Owner can't ask for a scope admin didn't grant.
  r = await call('POST', '/me/api-keys', { token: newOwner, body: { name: 'x', scopes: ['students:write'] } });
  assert.equal(r.json.error.code, 'scope_not_allowed');

  r = await call('POST', '/me/api-keys', { token: newOwner, body: { name: 'website', scopes: ['students:read'] } });
  assert.equal(r.status, 201);
  const { key, id } = r.json;
  assert.match(key, /^hk_/);
  assert.ok(!JSON.stringify((await call('GET', '/me/api-keys', { token: newOwner })).json).includes(key), 'key is shown only once');

  // Website calls with the key.
  assert.equal((await call('GET', '/students', { key })).status, 200);
  assert.equal((await call('POST', '/students', { key, body: { name: 'Z' } })).json.error.code, 'insufficient_scope');
  assert.equal((await call('GET', '/bills', { key })).json.error.code, 'insufficient_scope'); // key lacks bills:read
  assert.equal((await call('GET', '/students', { key: key + 'x' })).status, 401);

  // Rate limit (3/min): 2 used above successfully-authed (GET ok, POST, GET bills) -> next exceeds.
  r = await call('GET', '/students', { key });
  assert.equal(r.status, 429);
  assert.ok(r.headers.get('retry-after'));

  // Revoking and disabling take effect immediately.
  await call('DELETE', `/me/api-keys/${id}`, { token: newOwner });
  assert.equal((await call('GET', '/students', { key })).status, 401);
});

test('tenant isolation, CRUD and plan gating', async () => {
  const owner = await login('owner@demo.local', 'owner12345');
  const admin = await login('admin@hostel.local', 'admin12345');
  const other = (await call('POST', '/admin/hostels', { token: admin, body: { name: 'Other' } })).json;
  await call('POST', `/admin/hostels/${other.id}/users`, { token: admin, body: { email: 'o@h.local', password: 'password123' } });
  const otherTok = await login('o@h.local', 'password123');

  const created = (await call('POST', '/students', { token: owner, body: { name: 'New Kid', room: '9' } })).json;
  assert.equal((await call('GET', `/students/${created.id}`, { token: otherTok })).status, 404);
  assert.equal((await call('GET', '/students', { token: otherTok })).json.meta.total, 0);
  assert.equal((await call('PUT', `/students/${created.id}`, { token: owner, body: { room: '10' } })).json.room, '10');
  assert.equal((await call('POST', '/students', { token: owner, body: {} })).status, 400);
  assert.equal((await call('GET', '/bills', { token: otherTok })).status, 402); // basic plan has no bills
  assert.equal((await call('DELETE', `/students/${created.id}`, { token: owner })).status, 204);
  assert.equal((await call('GET', `/students/${created.id}`, { token: owner })).status, 404);
});

test('app sync contract: delta pull, push, last-write-wins', async () => {
  const t = await login('owner@demo.local', 'owner12345');
  const first = (await call('GET', '/sync/students', { token: t })).json;
  assert.ok(first.items.length >= 4);
  assert.equal(first.has_more, false);
  assert.equal((await call('GET', `/sync/students?since=${encodeURIComponent(first.next_cursor)}`, { token: t })).json.items.length, 0);

  const row = { id: 'client-1', name: 'Offline', course: '', phone: '', location: '', room: '1', inHostel: true, updatedAt: new Date().toISOString() };
  await call('POST', '/sync/students', { token: t, body: { op: 'upsert', id: 'client-1', data: JSON.stringify(row) } });
  const delta = (await call('GET', `/sync/students?since=${encodeURIComponent(first.next_cursor)}`, { token: t })).json;
  assert.deepEqual(delta.items.map((i) => i.id), ['client-1']);

  const stale = { ...row, name: 'Stale', updatedAt: '2000-01-01T00:00:00.000Z' };
  const r = await call('POST', '/sync/students', { token: t, body: { op: 'upsert', id: 'client-1', data: JSON.stringify(stale) } });
  assert.equal(r.json.skipped, 'stale');
  assert.equal((await call('GET', '/students/client-1', { token: t })).json.name, 'Offline');
});
