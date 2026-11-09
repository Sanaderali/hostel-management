# Hostel Management (Flutter)

Offline-first hostel management app. Dark/light theme, subscription-gated modules, delta sync.

## Dev setup
```bash
# Flutter stable (3.47+ / Dart 3.13+)
flutter pub get
dart run build_runner build -d      # generates drift code (*.g.dart, git-ignored)
flutter run                         # uses the built-in mock backend
flutter test
```
Real backend later: `--dart-define=USE_MOCK_BACKEND=false --dart-define=API_BASE_URL=https://...`

## Architecture (lib/)
| Path | Role |
|---|---|
| `core/database` | Drift (SQLite). Single source of truth; UI only reads local DB, so it is instant and works offline. |
| `core/sync` | `SyncEngine`: pushes the **outbox** (offline writes), then pulls only changes since a per-entity **cursor**. Runs on app start and when internet returns. `RemoteDataSource` = mock now, REST later. |
| `core/entitlements` | `Plan` → `Feature` set, cached locally. `ref.watch(hasFeatureProvider(Feature.bills))`. Expired plan falls back to free tier. |
| `core/modules` | `AppModule` + `registry.dart`. Home cards and routes are generated from this list. |
| `features/*` | One folder per module (students, bills). |

### Add a new feature
1. Add a `Feature` value (if it's paid) and put it in the relevant `Plan`s.
2. Add table(s) in `app_database.dart`, bump `schemaVersion`, add a migration.
3. Create `features/<name>/` with a repository (implement `SyncHandler`) and `<name>_module.dart`.
4. Register in `core/modules/registry.dart` and `syncHandlersProvider`.

### Backend contract (to build later)
- `GET /sync/{entity}?since=<cursor>` → `{items, next_cursor, has_more}`
- `POST /sync/{entity}` → `{op, id, data}` (last-write-wins by `updatedAt`)
- `GET /me/entitlements` → `{plan, features[], cycle, expiresAt}`

Admin panel (roles/permissions, plans, billing) is a separate project.
