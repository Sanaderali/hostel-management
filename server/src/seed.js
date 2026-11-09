import { randomUUID } from 'node:crypto';
import { nowIso } from './db.js';
import { ALL_SCOPES } from './app.js';
import { hashPassword } from './security.js';

/** Dev data: 1 super admin + 1 demo hostel (pro plan, API enabled) + sample rows. */
export function seedDemo(db) {
  if (db.prepare('SELECT COUNT(*) n FROM users').get().n > 0) return false;
  const run = (sql, ...p) => db.prepare(sql).run(...p);
  const hid = randomUUID();
  const year = new Date(Date.now() + 365 * 864e5).toISOString();
  run('INSERT INTO users (id,email,name,password_hash,role,hostel_id) VALUES (?,?,?,?,?,NULL)',
    randomUUID(), 'admin@hostel.local', 'Super Admin', hashPassword('admin12345'), 'superadmin');
  run('INSERT INTO hostels (id,name,created_at) VALUES (?,?,?)', hid, 'Demo Hostel', new Date().toISOString());
  run("INSERT INTO subscriptions (hostel_id,plan,cycle,expires_at) VALUES (?, 'pro', 'yearly', ?)", hid, year);
  run('INSERT INTO hostel_api_access (hostel_id,enabled,scopes,rate_limit) VALUES (?,1,?,120)', hid, JSON.stringify(ALL_SCOPES));
  run('INSERT INTO users (id,email,name,password_hash,role,hostel_id) VALUES (?,?,?,?,?,?)',
    randomUUID(), 'owner@demo.local', 'Demo Owner', hashPassword('owner12345'), 'owner', hid);
  ['Moazam Naveed', 'Ali Khan', 'Usman Tariq', 'Hamza Shah'].forEach((name, i) =>
    run(`INSERT INTO students (id,hostel_id,name,course,phone,location,room,in_hostel,updated_at)
         VALUES (?,?,?,?,?,?,?,?,?)`, randomUUID(), hid, name, 'Bs.c Chemistry', `+92 333 444 545${i}`,
      'Mingora swat, Pakistan', String(27 + i), i === 2 ? 0 : 1, nowIso()));
  ['electricity', 'water', 'gas'].forEach((type, i) =>
    run(`INSERT INTO bills (id,hostel_id,type,month,amount,paid,updated_at) VALUES (?,?,?,?,?,?,?)`,
      randomUUID(), hid, type, '2022-08', 1200 + i * 350, type === 'water' ? 1 : 0, nowIso()));
  return true;
}
