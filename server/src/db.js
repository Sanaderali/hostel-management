import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const SCHEMA = `
CREATE TABLE IF NOT EXISTS hostels (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS subscriptions (
  hostel_id TEXT PRIMARY KEY REFERENCES hostels(id),
  plan TEXT NOT NULL DEFAULT 'basic',
  cycle TEXT NOT NULL DEFAULT 'monthly',
  expires_at TEXT);

-- Admin-controlled switch: may this hostel's users create API keys, and with which scopes?
CREATE TABLE IF NOT EXISTS hostel_api_access (
  hostel_id TEXT PRIMARY KEY REFERENCES hostels(id),
  enabled INTEGER NOT NULL DEFAULT 0,
  scopes TEXT NOT NULL DEFAULT '[]',
  rate_limit INTEGER NOT NULL DEFAULT 60);

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('superadmin','owner','staff')),
  hostel_id TEXT REFERENCES hostels(id));

CREATE TABLE IF NOT EXISTS api_keys (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  hostel_id TEXT NOT NULL REFERENCES hostels(id),
  name TEXT NOT NULL, prefix TEXT NOT NULL UNIQUE, key_hash TEXT NOT NULL,
  scopes TEXT NOT NULL, created_at TEXT NOT NULL,
  revoked_at TEXT, last_used_at TEXT);

CREATE TABLE IF NOT EXISTS students (
  id TEXT PRIMARY KEY, hostel_id TEXT NOT NULL REFERENCES hostels(id),
  name TEXT NOT NULL, course TEXT NOT NULL DEFAULT '', phone TEXT NOT NULL DEFAULT '',
  location TEXT NOT NULL DEFAULT '', room TEXT NOT NULL DEFAULT '',
  in_hostel INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS students_sync ON students(hostel_id, updated_at);

CREATE TABLE IF NOT EXISTS bills (
  id TEXT PRIMARY KEY, hostel_id TEXT NOT NULL REFERENCES hostels(id),
  student_id TEXT, type TEXT NOT NULL, month TEXT NOT NULL,
  amount REAL NOT NULL DEFAULT 0, paid INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS bills_sync ON bills(hostel_id, updated_at);
`;

export function openDb(path = ':memory:') {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec('PRAGMA foreign_keys = ON;');
  db.exec(SCHEMA);
  return db;
}

// Strictly increasing timestamps so "updated_at > cursor" delta sync never skips rows.
let last = 0;
export function nowIso() {
  let t = Date.now();
  if (t <= last) t = last + 1;
  last = t;
  return new Date(t).toISOString();
}
