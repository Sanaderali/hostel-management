import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { nowIso } from './db.js';
import {
  generateApiKey, hashPassword, parseKeyPrefix, safeEqualHex, hashKey,
  signToken, verifyPassword, verifyToken,
} from './security.js';

// ---- Plans / scopes (mirror lib/core/entitlements/entitlements.dart) -------
export const PLANS = {
  basic: ['students'],
  standard: ['students', 'bills', 'notifications'],
  pro: ['students', 'bills', 'notifications', 'reports', 'multiHostel'],
};
export const RESOURCES = {
  students: {
    table: 'students', feature: 'students',
    required: ['name'],
    fields: { name: 'text', course: 'text', phone: 'text', location: 'text', room: 'text', inHostel: 'bool' },
    cols: { inHostel: 'in_hostel' },
  },
  bills: {
    table: 'bills', feature: 'bills',
    required: ['type', 'month'],
    fields: { studentId: 'text?', type: 'text', month: 'text', amount: 'num', paid: 'bool' },
    cols: { studentId: 'student_id' },
  },
};
export const ALL_SCOPES = Object.keys(RESOURCES).flatMap((r) => [`${r}:read`, `${r}:write`]);

export class HttpError extends Error {
  constructor(status, code, message) { super(message ?? code); this.status = status; this.code = code; }
}
const bad = (m) => new HttpError(400, 'bad_request', m);

export function createApp({ db, secret = 'dev-secret' }) {
  const routes = [];
  const route = (method, path, handler) => routes.push({
    method,
    re: new RegExp('^' + path.replace(/:(\w+)/g, '(?<$1>[^/]+)') + '/?$'),
    handler,
  });
  const q = (sql, ...p) => db.prepare(sql).all(...p);
  const one = (sql, ...p) => db.prepare(sql).get(...p);
  const run = (sql, ...p) => db.prepare(sql).run(...p);
  const json = (s) => JSON.parse(s);

  // ---- auth ---------------------------------------------------------------
  function bearer(req) {
    const h = req.headers.authorization ?? '';
    return h.startsWith('Bearer ') ? h.slice(7) : null;
  }

  function sessionUser(req) {
    const payload = verifyToken(bearer(req), secret);
    const user = payload && one('SELECT * FROM users WHERE id = ?', payload.uid);
    if (!user) throw new HttpError(401, 'unauthorized', 'Login required');
    return user;
  }

  function requireAdmin(req) {
    const u = sessionUser(req);
    if (u.role !== 'superadmin') throw new HttpError(403, 'forbidden', 'Admin only');
    return u;
  }

  function hostelState(hostelId) {
    const sub = one('SELECT * FROM subscriptions WHERE hostel_id = ?', hostelId) ?? { plan: 'basic', cycle: 'monthly' };
    const expired = sub.expires_at && new Date(sub.expires_at) < new Date();
    const plan = expired ? 'basic' : sub.plan;
    const a = one('SELECT * FROM hostel_api_access WHERE hostel_id = ?', hostelId);
    return {
      sub, plan, features: PLANS[plan],
      api: { enabled: !!a?.enabled, scopes: a ? json(a.scopes) : [], rateLimit: a?.rate_limit ?? 60 },
    };
  }

  const windows = new Map(); // keyId -> {start, count}
  function rateLimit(keyId, limit, res) {
    const now = Date.now();
    let w = windows.get(keyId);
    if (!w || now - w.start >= 60_000) windows.set(keyId, (w = { start: now, count: 0 }));
    w.count++;
    res.headers['X-RateLimit-Limit'] = limit;
    res.headers['X-RateLimit-Remaining'] = Math.max(0, limit - w.count);
    if (w.count > limit) {
      res.headers['Retry-After'] = Math.ceil((60_000 - (now - w.start)) / 1000);
      throw new HttpError(429, 'rate_limited', 'Too many requests');
    }
  }

  /** Authenticates session token OR API key and checks plan + scope for one resource action. */
  function dataAuth(req, res, resource, action) {
    const need = `${resource}:${action}`;
    const raw = req.headers['x-api-key'] ?? (bearer(req)?.startsWith('hk_') ? bearer(req) : null);
    let hostelId, scopes, state;
    if (raw) {
      const prefix = parseKeyPrefix(raw);
      const k = prefix && one('SELECT * FROM api_keys WHERE prefix = ?', prefix);
      if (!k || k.revoked_at || !safeEqualHex(k.key_hash, hashKey(raw))) {
        throw new HttpError(401, 'invalid_api_key', 'Invalid or revoked API key');
      }
      state = hostelState(k.hostel_id);
      if (!state.api.enabled) throw new HttpError(403, 'api_access_disabled', 'API access is disabled for this hostel');
      rateLimit(k.id, state.api.rateLimit, res);
      run('UPDATE api_keys SET last_used_at = ? WHERE id = ?', new Date().toISOString(), k.id);
      hostelId = k.hostel_id;
      const keyScopes = json(k.scopes);
      scopes = state.api.scopes.filter((s) => keyScopes.includes(s)); // admin ∩ key
    } else {
      const u = sessionUser(req);
      if (!u.hostel_id) throw new HttpError(403, 'forbidden', 'Account has no hostel');
      hostelId = u.hostel_id;
      state = hostelState(hostelId);
      scopes = ALL_SCOPES;
    }
    if (!state.features.includes(RESOURCES[resource].feature)) {
      throw new HttpError(402, 'feature_not_in_plan', `Your plan does not include ${resource}`);
    }
    if (!scopes.includes(need)) throw new HttpError(403, 'insufficient_scope', `Missing scope ${need}`);
    return hostelId;
  }

  // ---- resource helpers -----------------------------------------------------
  const colOf = (r, f) => r.cols[f] ?? f;
  const toApi = (r, row) => ({
    id: row.id,
    ...Object.fromEntries(Object.entries(r.fields).map(([f, t]) =>
      [f, t === 'bool' ? !!row[colOf(r, f)] : row[colOf(r, f)]])),
    updatedAt: row.updated_at,
  });

  function cleanInput(r, input, { partial }) {
    if (typeof input !== 'object' || input === null || Array.isArray(input)) throw bad('Body must be an object');
    const out = {};
    for (const [f, t] of Object.entries(r.fields)) {
      if (!(f in input)) continue;
      const v = input[f];
      const ok = t === 'bool' ? typeof v === 'boolean'
        : t === 'num' ? typeof v === 'number' && Number.isFinite(v)
        : t === 'text?' ? v === null || typeof v === 'string'
        : typeof v === 'string';
      if (!ok) throw bad(`Field "${f}" has the wrong type`);
      out[f] = t === 'bool' ? (v ? 1 : 0) : v;
    }
    if (!partial) for (const f of r.required) if (!(f in out) || out[f] === '') throw bad(`Field "${f}" is required`);
    return out;
  }

  function upsert(r, hostelId, id, fields) {
    const ex = one(`SELECT * FROM ${r.table} WHERE id = ?`, id);
    if (ex && ex.hostel_id !== hostelId) throw new HttpError(409, 'id_conflict', 'ID belongs to another hostel');
    if (ex) fields = { ...Object.fromEntries(Object.keys(r.fields).map((f) => [f, ex[colOf(r, f)]])), ...fields };
    const names = Object.keys(fields);
    const cols = names.map((f) => colOf(r, f));
    const sql = `INSERT INTO ${r.table} (id, hostel_id, ${cols.join(',')}, updated_at, deleted)
      VALUES (?, ?, ${cols.map(() => '?').join(',')}, ?, 0)
      ON CONFLICT(id) DO UPDATE SET ${[...cols, 'updated_at'].map((c) => `${c}=excluded.${c}`).join(',')}, deleted=0`;
    run(sql, id, hostelId, ...names.map((f) => fields[f]), nowIso());
    return one(`SELECT * FROM ${r.table} WHERE id = ?`, id);
  }

  const resource = (name) => {
    const r = RESOURCES[name];
    if (!r) throw new HttpError(404, 'not_found', 'Unknown resource');
    return r;
  };

  // ---- routes: auth / account ---------------------------------------------
  route('GET', '/health', () => ({ ok: true }));

  route('POST', '/api/v1/auth/login', ({ body }) => {
    const u = one('SELECT * FROM users WHERE email = ?', String(body.email ?? '').toLowerCase());
    if (!u || !verifyPassword(String(body.password ?? ''), u.password_hash)) {
      throw new HttpError(401, 'invalid_credentials', 'Wrong email or password');
    }
    const token = signToken({ uid: u.id }, secret, 30 * 24 * 3600);
    return { token, user: { id: u.id, email: u.email, name: u.name, role: u.role, hostelId: u.hostel_id } };
  });

  route('GET', '/api/v1/me', ({ req }) => {
    const u = sessionUser(req);
    const hostel = u.hostel_id && one('SELECT id, name FROM hostels WHERE id = ?', u.hostel_id);
    const state = u.hostel_id ? hostelState(u.hostel_id) : null;
    return {
      user: { id: u.id, email: u.email, name: u.name, role: u.role },
      hostel, plan: state?.plan, apiAccess: state?.api,
    };
  });

  route('GET', '/api/v1/me/entitlements', ({ req }) => {
    const u = sessionUser(req);
    if (!u.hostel_id) return { plan: 'basic', features: PLANS.basic, cycle: 'monthly', expiresAt: null };
    const s = hostelState(u.hostel_id);
    return { plan: s.plan, features: s.features, cycle: s.sub.cycle, expiresAt: s.sub.expires_at ?? null };
  });

  // ---- routes: per-user API keys --------------------------------------------
  const keyView = (k) => ({
    id: k.id, name: k.name, prefix: `hk_${k.prefix}_…`, scopes: json(k.scopes),
    createdAt: k.created_at, lastUsedAt: k.last_used_at, revokedAt: k.revoked_at,
  });

  route('GET', '/api/v1/me/api-keys', ({ req }) => {
    const u = sessionUser(req);
    return { data: q('SELECT * FROM api_keys WHERE user_id = ? ORDER BY created_at DESC', u.id).map(keyView) };
  });

  route('POST', '/api/v1/me/api-keys', ({ req, body }) => {
    const u = sessionUser(req);
    if (!u.hostel_id) throw new HttpError(403, 'forbidden', 'Account has no hostel');
    const { api } = hostelState(u.hostel_id);
    if (!api.enabled) throw new HttpError(403, 'api_access_disabled', 'API access is not enabled for your hostel. Contact the administrator.');
    const name = String(body.name ?? '').trim();
    if (!name) throw bad('"name" is required');
    const scopes = body.scopes ?? api.scopes;
    if (!Array.isArray(scopes) || !scopes.length || scopes.some((s) => !api.scopes.includes(s))) {
      throw new HttpError(403, 'scope_not_allowed', `Allowed scopes: ${api.scopes.join(', ') || 'none'}`);
    }
    const { key, prefix, hash } = generateApiKey();
    const id = randomUUID();
    run('INSERT INTO api_keys (id,user_id,hostel_id,name,prefix,key_hash,scopes,created_at) VALUES (?,?,?,?,?,?,?,?)',
      id, u.id, u.hostel_id, name, prefix, hash, JSON.stringify(scopes), new Date().toISOString());
    // The full key is returned exactly once.
    return { status: 201, body: { ...keyView(one('SELECT * FROM api_keys WHERE id = ?', id)), key } };
  });

  route('DELETE', '/api/v1/me/api-keys/:id', ({ req, params }) => {
    const u = sessionUser(req);
    const r = run('UPDATE api_keys SET revoked_at = ? WHERE id = ? AND user_id = ? AND revoked_at IS NULL',
      new Date().toISOString(), params.id, u.id);
    if (!r.changes) throw new HttpError(404, 'not_found', 'Key not found');
    return { status: 204 };
  });

  // ---- routes: admin (super admin) ------------------------------------------
  const hostelView = (h) => {
    const s = hostelState(h.id);
    return {
      id: h.id, name: h.name, plan: s.sub.plan, cycle: s.sub.cycle, expiresAt: s.sub.expires_at ?? null,
      apiAccess: s.api,
      users: one('SELECT COUNT(*) n FROM users WHERE hostel_id = ?', h.id).n,
      activeKeys: one('SELECT COUNT(*) n FROM api_keys WHERE hostel_id = ? AND revoked_at IS NULL', h.id).n,
    };
  };
  const hostelOr404 = (id) => one('SELECT * FROM hostels WHERE id = ?', id) ?? (() => { throw new HttpError(404, 'not_found', 'Hostel not found'); })();

  route('GET', '/api/v1/admin/hostels', ({ req }) => {
    requireAdmin(req);
    return { data: q('SELECT * FROM hostels ORDER BY created_at').map(hostelView) };
  });

  route('POST', '/api/v1/admin/hostels', ({ req, body }) => {
    requireAdmin(req);
    const name = String(body.name ?? '').trim();
    if (!name) throw bad('"name" is required');
    const id = randomUUID();
    run('INSERT INTO hostels (id,name,created_at) VALUES (?,?,?)', id, name, new Date().toISOString());
    run('INSERT INTO subscriptions (hostel_id) VALUES (?)', id);
    run('INSERT INTO hostel_api_access (hostel_id) VALUES (?)', id);
    return { status: 201, body: hostelView(hostelOr404(id)) };
  });

  route('POST', '/api/v1/admin/hostels/:id/users', ({ req, params, body }) => {
    requireAdmin(req);
    hostelOr404(params.id);
    const email = String(body.email ?? '').toLowerCase().trim();
    if (!email.includes('@') || String(body.password ?? '').length < 8) throw bad('Valid email and password (8+ chars) required');
    if (!['owner', 'staff'].includes(body.role ?? 'owner')) throw bad('role must be owner or staff');
    if (one('SELECT 1 x FROM users WHERE email = ?', email)) throw new HttpError(409, 'email_taken', 'Email already used');
    const id = randomUUID();
    run('INSERT INTO users (id,email,name,password_hash,role,hostel_id) VALUES (?,?,?,?,?,?)',
      id, email, body.name ?? email, hashPassword(body.password), body.role ?? 'owner', params.id);
    return { status: 201, body: { id, email, role: body.role ?? 'owner', hostelId: params.id } };
  });

  route('PUT', '/api/v1/admin/hostels/:id/api-access', ({ req, params, body }) => {
    requireAdmin(req);
    hostelOr404(params.id);
    const scopes = body.scopes ?? [];
    if (!Array.isArray(scopes) || scopes.some((s) => !ALL_SCOPES.includes(s))) throw bad(`scopes must be from: ${ALL_SCOPES.join(', ')}`);
    const rl = body.rateLimit ?? 60;
    if (!Number.isInteger(rl) || rl < 1 || rl > 100000) throw bad('rateLimit must be 1..100000 requests/minute');
    run(`INSERT INTO hostel_api_access (hostel_id, enabled, scopes, rate_limit) VALUES (?,?,?,?)
         ON CONFLICT(hostel_id) DO UPDATE SET enabled=excluded.enabled, scopes=excluded.scopes, rate_limit=excluded.rate_limit`,
      params.id, body.enabled ? 1 : 0, JSON.stringify(scopes), rl);
    return hostelView(hostelOr404(params.id));
  });

  route('PUT', '/api/v1/admin/hostels/:id/subscription', ({ req, params, body }) => {
    requireAdmin(req);
    hostelOr404(params.id);
    if (!PLANS[body.plan]) throw bad(`plan must be one of: ${Object.keys(PLANS).join(', ')}`);
    if (!['monthly', 'yearly'].includes(body.cycle ?? 'monthly')) throw bad('cycle must be monthly or yearly');
    if (body.expiresAt && Number.isNaN(Date.parse(body.expiresAt))) throw bad('expiresAt must be an ISO date');
    run(`INSERT INTO subscriptions (hostel_id, plan, cycle, expires_at) VALUES (?,?,?,?)
         ON CONFLICT(hostel_id) DO UPDATE SET plan=excluded.plan, cycle=excluded.cycle, expires_at=excluded.expires_at`,
      params.id, body.plan, body.cycle ?? 'monthly', body.expiresAt ?? null);
    return hostelView(hostelOr404(params.id));
  });

  // ---- routes: mobile/desktop app sync contract ------------------------------
  route('GET', '/api/v1/sync/:entity', ({ req, res, params, query }) => {
    const r = resource(params.entity);
    const hostelId = dataAuth(req, res, params.entity, 'read');
    const rows = q(`SELECT * FROM ${r.table} WHERE hostel_id = ? AND deleted = 0 AND updated_at > ?
                    ORDER BY updated_at LIMIT 201`, hostelId, query.get('since') ?? '');
    const page = rows.slice(0, 200);
    return {
      items: page.map((x) => toApi(r, x)),
      next_cursor: page.length ? page.at(-1).updated_at : query.get('since'),
      has_more: rows.length > 200,
    };
  });

  route('POST', '/api/v1/sync/:entity', ({ req, res, params, body }) => {
    const r = resource(params.entity);
    const hostelId = dataAuth(req, res, params.entity, 'write');
    const data = typeof body.data === 'string' ? json(body.data) : (body.data ?? {});
    if (typeof body.id !== 'string' || !body.id) throw bad('"id" is required');
    if (body.op === 'delete') {
      run(`UPDATE ${r.table} SET deleted = 1, updated_at = ? WHERE id = ? AND hostel_id = ?`, nowIso(), body.id, hostelId);
      return { ok: true };
    }
    if (body.op !== 'upsert') throw bad('op must be upsert or delete');
    const ex = one(`SELECT updated_at FROM ${r.table} WHERE id = ?`, body.id);
    if (ex && data.updatedAt && ex.updated_at > data.updatedAt) return { ok: true, skipped: 'stale' }; // last write wins
    upsert(r, hostelId, body.id, cleanInput(r, data, { partial: false }));
    return { ok: true };
  });

  // ---- routes: data (session token or API key) ---------------------------
  route('GET', '/api/v1/:resource', ({ req, res, params, query }) => {
    const r = resource(params.resource);
    const hostelId = dataAuth(req, res, params.resource, 'read');
    const limit = Math.min(Math.max(parseInt(query.get('limit') ?? '50', 10) || 50, 1), 200);
    const offset = Math.max(parseInt(query.get('offset') ?? '0', 10) || 0, 0);
    const since = query.get('updated_since') ?? '';
    const where = 'hostel_id = ? AND deleted = 0 AND updated_at > ?';
    const rows = q(`SELECT * FROM ${r.table} WHERE ${where} ORDER BY updated_at LIMIT ? OFFSET ?`, hostelId, since, limit, offset);
    const total = one(`SELECT COUNT(*) n FROM ${r.table} WHERE ${where}`, hostelId, since).n;
    return { data: rows.map((x) => toApi(r, x)), meta: { limit, offset, total } };
  });

  route('GET', '/api/v1/:resource/:id', ({ req, res, params }) => {
    const r = resource(params.resource);
    const hostelId = dataAuth(req, res, params.resource, 'read');
    const row = one(`SELECT * FROM ${r.table} WHERE id = ? AND hostel_id = ? AND deleted = 0`, params.id, hostelId);
    if (!row) throw new HttpError(404, 'not_found', 'Not found');
    return toApi(r, row);
  });

  route('POST', '/api/v1/:resource', ({ req, res, params, body }) => {
    const r = resource(params.resource);
    const hostelId = dataAuth(req, res, params.resource, 'write');
    const id = randomUUID();
    return { status: 201, body: toApi(r, upsert(r, hostelId, id, cleanInput(r, body, { partial: false }))) };
  });

  route('PUT', '/api/v1/:resource/:id', ({ req, res, params, body }) => {
    const r = resource(params.resource);
    const hostelId = dataAuth(req, res, params.resource, 'write');
    const ex = one(`SELECT * FROM ${r.table} WHERE id = ? AND hostel_id = ? AND deleted = 0`, params.id, hostelId);
    if (!ex) throw new HttpError(404, 'not_found', 'Not found');
    return toApi(r, upsert(r, hostelId, params.id, cleanInput(r, body, { partial: true })));
  });

  route('DELETE', '/api/v1/:resource/:id', ({ req, res, params }) => {
    const r = resource(params.resource);
    const hostelId = dataAuth(req, res, params.resource, 'write');
    const n = run(`UPDATE ${r.table} SET deleted = 1, updated_at = ? WHERE id = ? AND hostel_id = ? AND deleted = 0`,
      nowIso(), params.id, hostelId).changes;
    if (!n) throw new HttpError(404, 'not_found', 'Not found');
    return { status: 204 };
  });

  // ---- http plumbing ----------------------------------------------------------
  const CORS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type, X-API-Key',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Expose-Headers': 'X-RateLimit-Limit, X-RateLimit-Remaining, Retry-After',
  };

  async function readBody(req) {
    let size = 0;
    const chunks = [];
    for await (const c of req) {
      if ((size += c.length) > 1_000_000) throw new HttpError(413, 'too_large', 'Body too large');
      chunks.push(c);
    }
    if (!chunks.length) return {};
    try { return JSON.parse(Buffer.concat(chunks).toString()); } catch { throw bad('Invalid JSON'); }
  }

  const server = createServer(async (req, rawRes) => {
    const res = { headers: { ...CORS, 'Content-Type': 'application/json' } };
    const send = (status, body) => {
      rawRes.writeHead(status, res.headers);
      rawRes.end(body === undefined || status === 204 ? undefined : JSON.stringify(body));
    };
    try {
      if (req.method === 'OPTIONS') return send(204);
      const url = new URL(req.url, 'http://x');
      let matched = false;
      for (const r of routes) {
        if (r.method !== req.method) continue;
        const m = r.re.exec(url.pathname);
        if (!m) continue;
        matched = true;
        const body = ['POST', 'PUT'].includes(req.method) ? await readBody(req) : {};
        const out = await r.handler({ req, res, params: m.groups ?? {}, query: url.searchParams, body });
        return out && 'status' in out ? send(out.status, out.body) : send(200, out);
      }
      throw new HttpError(matched ? 405 : 404, 'not_found', 'No such endpoint');
    } catch (e) {
      if (e instanceof HttpError) return send(e.status, { error: { code: e.code, message: e.message } });
      console.error(e);
      send(500, { error: { code: 'server_error', message: 'Unexpected error' } });
    }
  });
  return server;
}
