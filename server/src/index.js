import { openDb } from './db.js';
import { createApp } from './app.js';
import { seedDemo } from './seed.js';

const port = Number(process.env.PORT ?? 8080);
const db = openDb(process.env.DB_PATH ?? './data/hostel.db');
const secret = process.env.SESSION_SECRET ?? 'dev-secret-change-me';
if (process.env.NODE_ENV === 'production' && secret.startsWith('dev-')) {
  throw new Error('Set SESSION_SECRET in production');
}

if (process.env.SEED_DEMO !== 'false' && seedDemo(db)) {
  console.log('Seeded demo data:\n  admin: admin@hostel.local / admin12345\n  owner: owner@demo.local  / owner12345');
}
createApp({ db, secret }).listen(port, () => console.log(`Hostel API on http://localhost:${port}/api/v1`));
