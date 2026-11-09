import { createHash, createHmac, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

export function hashPassword(password) {
  const salt = randomBytes(16);
  return `${salt.toString('hex')}:${scryptSync(password, salt, 64).toString('hex')}`;
}

export function verifyPassword(password, stored) {
  const [salt, hash] = stored.split(':');
  const actual = scryptSync(password, Buffer.from(salt, 'hex'), 64);
  const expected = Buffer.from(hash, 'hex');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

const b64 = (b) => Buffer.from(b).toString('base64url');

export function signToken(payload, secret, ttlSeconds) {
  const body = b64(JSON.stringify({ ...payload, exp: Math.floor(Date.now() / 1000) + ttlSeconds }));
  return `${body}.${createHmac('sha256', secret).update(body).digest('base64url')}`;
}

export function verifyToken(token, secret) {
  const [body, sig] = (token ?? '').split('.');
  if (!body || !sig) return null;
  const good = createHmac('sha256', secret).update(body).digest('base64url');
  if (sig.length !== good.length || !timingSafeEqual(Buffer.from(sig), Buffer.from(good))) return null;
  const payload = JSON.parse(Buffer.from(body, 'base64url').toString());
  return payload.exp > Date.now() / 1000 ? payload : null;
}

/** API key format: hk_<8 char prefix>_<32 char secret>. Only a SHA-256 hash is stored. */
export function generateApiKey() {
  const prefix = randomBytes(6).toString('base64url').slice(0, 8);
  const key = `hk_${prefix}_${randomBytes(24).toString('base64url')}`;
  return { key, prefix, hash: hashKey(key) };
}

export const hashKey = (key) => createHash('sha256').update(key).digest('hex');

export function parseKeyPrefix(key) {
  const m = /^hk_([A-Za-z0-9_-]{8})_/.exec(key ?? '');
  return m ? m[1] : null;
}

export function safeEqualHex(a, b) {
  return a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));
}
