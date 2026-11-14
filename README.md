# Gemstok HQ

**Your to-do steps (keys, SQL, deploys, app changes):** `docs/your-steps/00_START_HERE.md`


Private macOS app — one place to see the whole Gemstok business. Reads only.
Plan: `PLAN-step1.md`. DB changes live in `gemstok-backend` (each project's `CHANGES.md`).

## Security in one look
- Opens only with **Touch ID**. Locks again on Mac sleep / screen lock / switch user, after **5 min** idle, or "Lock now".
- Connection details live **only in the macOS Keychain** (this Mac only, not iCloud). Settings shows "set / not set"; **Show** reveals a password only after a fresh Touch ID, for 30 s (a copied password is cleared from the clipboard when it hides).
- HQ always connects as **`hq_reader.<ref>`** through the Supabase **session pooler** (port 5432), SSL on.
  After connecting it asks the database who it is: anything other than `hq_reader` + read-only → disconnect.
- No keys in this folder, ever.

## First run (on the Mac)
1. Add the macOS project files (doesn't touch the files already here):
   ```
   cd ~/Development/Gemstok/gemstok_hq
   flutter create --platforms=macos --org com.gemstok --project-name gemstok_hq .
   ```
2. Get packages and check the code:
   ```
   flutter pub get
   flutter analyze
   flutter test
   ```
3. Nothing to set in Xcode. (HQ uses the normal login Keychain; it does not need a Team or "Keychain Sharing".)
4. Optional: SSL certificate — see `assets/certs/README.md`.
5. Run: `flutter run -d macos`

You should see: lock screen → Touch ID → **Settings** with every project "Key: not set".
Connections stay red until `hq_reader` is created in each project (next SQL step).

## Folders
```
lib/main.dart                     app + lock gate + idle tracking; Keep alive runs app-wide
lib/app_theme.dart                colours, Jost, light theme (+ the clay colour for ASK)
lib/lock/                         Touch ID lock — asks by itself only when HQ is in front
lib/settings/key_store.dart       the only code that touches the Keychain (one item for everything)
lib/settings/settings_screen      DB logins (hq_reader per project + the hq_operator actions login): Add / Replace / Show / Check
lib/settings/tokens_section       Supabase access tokens (2 accounts), used read-only
lib/db/projects.dart              the 8 Supabase projects + the actions login
lib/db/hq_db.dart                 connections + the role guard (hq_reader must be read-only)
lib/db/queries.dart               EVERY SQL query HQ runs, in one file
lib/db/hq_data.dart               the cache: loads once, refreshes every 5 min, wiped on lock
lib/screens/                      Today · Joining · Using · Doing · People · Reports · Servers · Money · Storage
lib/ideas/                        Ideas notebook (ideas/ideas.json, not in git)
lib/leads/                        campaign links + print QR (leads/campaigns.json, leads/qr/*.png)
lib/servers/                      Supabase Management API — GET only, 5 allowed addresses
lib/services/                     App Store Connect, Google Play, AdMob, Cloudflare — read-only, 6 allowed hosts (web.dart)
lib/actions/                      the only code that CHANGES data: maintenance switches, action log
lib/keepalive/                    real reads so free projects don't pause; countdown per project
lib/ask/                          ASK: questions + number snapshots for the Claude chat (ask/, not in git)
lib/widgets/                      number card, charts, tables, the screen frame
macos/Runner/MainFlutterWindow.swift   sleep / screen lock → lock HQ
```

## Where HQ keeps things on this Mac
- Keychain: one item "gemstok_hq" (DB passwords, Supabase tokens)
- `~/Library/Application Support/gemstok_hq/keep_alive.json` — last real read per project (no keys)
- `~/Library/Application Support/gemstok_hq/actions.log` — every change HQ made (no keys)
- `gemstok_hq/ask/`, `gemstok_hq/ideas/` — not in git · `gemstok_hq/leads/campaigns.json` — not in git (can hold people's names) · `leads/qr/` — fine in git

## Database setup
See the doc "Gemstok HQ — database setup steps" and each project's CHANGES.md in gemstok-backend.
# gemstok_HQ
