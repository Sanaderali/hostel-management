# Public API (for websites / integrations)

Base URL (local): `http://localhost:8080/api/v1` · JSON in/out · CORS enabled.

## Getting a key
1. The **super admin** enables API access for a hostel and chooses allowed scopes + rate limit:
   `PUT /admin/hostels/{id}/api-access` `{ "enabled": true, "scopes": ["students:read"], "rateLimit": 60 }`
2. A user of that hostel opens **App → ⋮ → API access → New key** (or `POST /me/api-keys`).
   The key (`hk_xxxxxxxx_…`) is shown **once**. Turning access off or revoking a key works immediately.

Send it as `X-API-Key: <key>` (or `Authorization: Bearer <key>`).
**Keep keys on your website's server**, not in browser JavaScript.

## Scopes
`students:read` `students:write` `bills:read` `bills:write`. A key can only do what the admin
allowed AND what the hostel's plan includes (bills need the Standard plan or higher → otherwise `402`).

## Endpoints (same shape for `students` and `bills`)
| | |
|---|---|
| `GET /students?limit=50&offset=0&updated_since=ISO` | list → `{data:[…], meta:{limit,offset,total}}` |
| `GET /students/{id}` | one |
| `POST /students` | create (`name` required) |
| `PUT /students/{id}` | partial update |
| `DELETE /students/{id}` | soft delete |

Errors: `{ "error": { "code", "message" } }` — `401 invalid_api_key`, `403 api_access_disabled | insufficient_scope`,
`402 feature_not_in_plan`, `429 rate_limited` (see `Retry-After`).
Rate-limit headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`.

```bash
curl -H "X-API-Key: hk_..." http://localhost:8080/api/v1/students?limit=5
```

## Admin endpoints (super admin session token)
`POST /auth/login` · `GET|POST /admin/hostels` · `POST /admin/hostels/{id}/users` ·
`PUT /admin/hostels/{id}/api-access` · `PUT /admin/hostels/{id}/subscription` `{plan, cycle, expiresAt}`

## App sync endpoints
`GET /sync/{entity}?since=cursor` and `POST /sync/{entity}` (used by the mobile app; last write wins).
