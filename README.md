# Hostel Management (Flutter, Android + iPhone)

Offline-first hostel management app + local API server. Dark/light theme, subscription-gated
modules, delta sync, per-user API keys controlled by an admin per hostel.

```
lib/        Flutter app (Android + iOS)
server/     API server (Node 22, zero npm dependencies, SQLite)  -> docs/API.md
scripts/    Windows setup + daily dev scripts
```

## Windows setup (everything on D:\)
1. Install Git on D: and clone the repo:
   ```powershell
   winget install Git.Git --location D:\dev\Git
   # open a NEW PowerShell
   git clone https://github.com/sanaderali/hostel-management.git D:\hostel-management
   cd D:\hostel-management
   git checkout claude/youthful-hamilton-aqw0gz
   ```
2. One-time setup (downloads Flutter, Node, JDK 17, Android SDK + an emulator into `D:\dev`):
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
   ```
3. Every day (new PowerShell): `scripts\dev.ps1` starts the API server and runs the app on the emulator.
   Real Android phone (USB debugging on, same Wi-Fi): `scripts\dev.ps1 -HostIp <your PC IP>`.

Demo logins (created in the dev database): owner `owner@demo.local` / `owner12345`,
super admin `admin@hostel.local` / `admin12345`.

The emulator needs virtualization (enable "Virtual Machine Platform"/"Windows Hypervisor Platform"
and BIOS virtualization). UI-only demo without the server: `flutter run --dart-define=USE_MOCK_BACKEND=true`.

> **iPhone:** Apple only allows iOS builds from macOS + Xcode. The same Dart code runs on iPhone;
> build it on a Mac (`flutter run`) or a cloud Mac CI (e.g. Codemagic). Not possible on Windows.

## Manual commands
```bash
cd server && npm start          # API on :8080 (dev DB in server/data/, demo data seeded)
cd server && npm test           # API tests
flutter pub get && dart run build_runner build -d
flutter analyze && flutter test
flutter test integration_test/app_test.dart -d <device>   # end-to-end against the local server
```
Android emulator reaches your PC as `10.0.2.2` (default). Other: `--dart-define=API_BASE_URL=http://<ip>:8080/api/v1`.

## Architecture (lib/)
| Path | Role |
|---|---|
| `core/database` | Drift (SQLite). Single source of truth; UI reads only the local DB → instant, works offline. |
| `core/sync` | `SyncEngine`: pushes the **outbox** (offline writes), then pulls only changes since a per-entity **cursor**. Runs at start, after login and when internet returns. |
| `core/entitlements` | `Plan` → `Feature` set, cached locally. `ref.watch(hasFeatureProvider(Feature.bills))`. |
| `core/auth`, `core/api` | Login/token, account API (own API keys). Sign-out wipes local data. |
| `core/modules` | `AppModule` + `registry.dart`: home cards and routes come from this list. |
| `features/*` | One folder per module (students, bills, account). |

### Add a new feature
1. Add a `Feature` (if paid) and put it in the right `Plan`s (also `server/src/app.js` `PLANS`).
2. Add table(s) in `app_database.dart`, bump `schemaVersion`, add a migration.
3. `features/<name>/`: a repository (implements `SyncHandler`) and `<name>_module.dart`.
4. Register in `core/modules/registry.dart` and `syncHandlersProvider`; add the resource to `RESOURCES` on the server.

## Known gaps (dev stage)
Token stored in SharedPreferences (move to secure storage before release) · no login rate-limit ·
server is single-node SQLite (swap for Postgres when going live) · local deletes aren't synced yet.
