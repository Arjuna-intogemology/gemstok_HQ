# Gemstok HQ — Step 1 plan (SHELL + PEOPLE) · 2026-11-12 · NOT BUILT YET

Private macOS app (Flutter desktop). Reads only. Nothing here is built until Arjuna says OK.

## 1. App shape
- `~/Development/Gemstok/gemstok_hq` — Flutter, macOS only.
- Packages: `local_auth` (Touch ID) · `flutter_secure_storage` (Keychain) · `postgres` v3 (SSL on) · `fl_chart` (small charts).
  Jost font bundled inside the app (no Google Fonts download at runtime).
- State: plain `ChangeNotifier`s, no big framework — easy to read.
- Folders: `lib/lock/` · `lib/settings/` · `lib/db/` (one connection per project + query files) · `lib/screens/` · `lib/widgets/` (number card, small chart, "source + loaded at" line).
- macOS: network-client entitlement; Keychain items stored "this device only".

## 2. Security in Step 1
- **Lock:** Touch ID on open (no password fallback inside HQ; macOS asks for the Mac password if Touch ID fails). Locks again on Mac sleep / screen lock (small Swift hook) and after 5 min with no mouse/keys.
- **Keys:** one Keychain item per project = the hq_reader pooler connection string. Settings shows only `Gemstok · set` / `not set` + **Replace** / **Remove**. A typed key is never shown again, never logged.
- **Role guard:** after connecting, HQ runs `select current_user`. If it isn't `hq_reader`, HQ disconnects and shows red "wrong role — use hq_reader". So a postgres/service string pasted by mistake is refused.
- Connection: Supavisor **session** mode (port 5432, user `hq_reader.<ref>`) — transaction mode breaks the prepared statements the postgres package uses.
- Every query has a 15 s timeout; the role itself is read-only (see DB changes).

## 3. Screens
Sidebar (later sections shown grey): **Today · Joining · Using · Doing · People** | Servers · Money · Websites · Storage | **Settings**.
Every number card: big number, small chart where useful, footer `Gemstok DB · login_history · loaded 10:42`. Refresh button per screen.

1. **Lock** — Gemstok mark, "Unlock with Touch ID".
2. **Settings** — rows per project: name · ref · key set/not set · Replace/Remove · Check → 🟢 `hq_reader · 84 ms` / 🔴 reason. Projects in Step 1: Gemstok, MKV data, Social, Chat, Gemmit. (Quvlet video, TraceGems, Websites listed as "later".)
3. **Today** — 4 cards: sign-ups · active people · stones listed · credits bought — each "today / last 7 days".
4. **Joining** — sign-ups per day/week (toggle), split by app and by sign-in type (Apple/Google/Email).
5. **Using + staying** — active 1/7/30 days per app; week-1 return table (join week → % who came back days 1–7).
6. **Doing** — stones listed · market views · boosts · credits bought/spent · chats started · Gemmit posts/circles · follows · reports. Range: 7/30/90 days.
7. **People** — search box `GSM-000123` (digits also work) → name · username · joined · apps used · last seen (app, device, version) · tier · stone count. Never name of chat partners, chat text, costs, phone.

## 4. Where each number comes from (to confirm with 0_check)
| Number | Source | Watch out |
|---|---|---|
| Sign-ups | Gemstok `members.created_at` | — |
| Sign-up by app | `member_signup.app` (exact) — else first `login_history.app` (labelled **guessed**) | `member_signup` SQL written 2026-11-13; apps fill it once their update ships (TODO-VIP). Website sign-ups with no row show "website / no app yet". |
| Sign-in type | `member_signup.signin_type`, older members `auth.identities.provider` | May need a counts-only function (decided by 0_check part 5). |
| Active people | Gemstok `login_history` | One row per app launch, written only when ManiKVault's **Browse** tab or Gem Broker's **Market** opens. People who stay in the Vault are not counted. App fix → PLAN later, don't build. |
| Week-1 return | login_history 1–7 days after join day | — |
| Stones listed | MKV `stones` where layer = market | Vault stones live on phones in v1 (cloud vault off) → HQ can't count them. |
| Market views | MKV — table to be found by 0_check | May not exist yet. |
| Boosts | Gemstok `boost_purchases` + MKV boost table | — |
| Credits bought / spent | Gemstok `credit_transactions` (purchase / deduct, by `metadata.app`) + `store_purchases` | — |
| Chats started | Chat `conversations` (id, created_at only) | Never messages. |
| Posts / circles / reports | Gemmit tables (from 0_check) | — |
| Follows | Social `follows` (created_at) | — |
| Reports | Gemstok `trader_reports` (counts, no details) + MKV `stone_reports` | — |
| Person lookup | `members` (chosen columns incl. name, username), `login_history`, MKV market stone count | No phone, costs, chat. |

## 5. DB changes (per project — SQL written only after 0_check comes back)
For each of Gemstok, MKV data, Social, Chat, Gemmit — files `sql/2026-11-12_hq_reader/` → `1_check` · `2_change` · `3_test` · `undo`, logged in that project's CHANGES.md:
1. `create role hq_reader login` — `nosuperuser nocreatedb nocreaterole noinherit`, `connection limit 3`,
   `default_transaction_read_only = on`, `statement_timeout = 15s`. Password typed by Arjuna into the file
   in the Editor (placeholder in the file) — then close the tab without saving the snippet.
2. `grant usage on schema public` + **column-level** `grant select (col, col…)` on the chosen tables only.
   Excluded: phone, phone_hash, deletion_pin, tax_number, business_reg_doc_url, fcm_token, cost_price, cost_currency, message tables, notes, recovery tables, push tokens.
3. Because hq_reader doesn't skip RLS: one extra rule per chosen table: `for select to hq_reader using (true)`. Only affects hq_reader; app users unchanged.
4. Gemstok only, if needed: `hq_signin_types(from, to)` — returns counts per provider, nothing else; execute for hq_reader only, revoked from public/anon/authenticated.
5. Guard: refuses to run if hq_reader already exists or a table/column isn't what 0_check showed.
6. `3_test`: as hq_reader — can read allowed columns; phone = blocked; insert = blocked; message table = blocked.
No new tables in Step 1. `hq_operator` comes in Step 2.

## 6. Order
0_check (5 projects) → Claude writes SQL → Arjuna runs 1→2→3 per project → Arjuna types each connection string into HQ Settings → build screens.

## 7. Gemstok — columns hq_reader gets (from the live column list, 2026-11-13)
| Table | Allowed columns | Left out |
|---|---|---|
| members | id, gemstok_id, name, username, tier, verified, country, created_at, last_seen_app, last_seen_at, last_seen_device, last_app_version, login_count, founding_member, subscription_status, private_vault_plan, is_student, is_miner, is_agent, is_gem_lab, is_cutter, is_consumer, is_deleted, deleted_at | source (always "oauth"), founding_member_expiry, email, phone, phone_hash, telegram, town, business_name, tax_number, business_reg_doc_url, photo_url, initials, fcm_token, deletion_pin, trust_score, vouch, subscription dates, username dates |
| login_history | id, member_id, app, device_os, app_version, country_code, created_at | gemstok_id (not needed) |
| credit_wallets | member_id, balance, updated_at | id |
| credit_transactions | id, member_id, type, amount, description, metadata, created_at | service_id, bundle_id, balance_after |
| store_purchases | id, member_id, store, app, product_id, credits, environment, created_at | store_txn_id |
| boost_purchases | all 8 | — |
| member_perks | all 3 | — |
| trader_reports | id, reason, source, status, created_at, reviewed_at | reporter_id, reported_id, details, admin_note, conversation_id |
| deleted_accounts | member_id, deleted_at, restored_at | everything else (email, name, PIN hash = recovery data) |
| member_signup (after it's run) | all | — |

## 8. What the backend already tells us (read 2026-11-13) — other projects
| Project | Tables HQ counts | Never touched | Gaps |
|---|---|---|---|
| MKV data `qauisvfoxgotbasxkeus` | stones (layer, business_status, listed_at, boost_until, created_at — no cost/private fields) · stone_reports (reason, status, app, created_at) · stone_boosts · stone_boost_stats (views/taps — boosted stones only) | cost_price, cost_currency, private note, where bought, GPS, fintrack_*, performa_*, mkv_reservations | No general "market views" table — only boosted-stone views. Vault stones live on phones (v1). No dump in backend → hq_reader 1_check confirms columns. |
| Social `mrgjjeyarzksiawkaxvw` | follows (count) · profiles (follower_count) | — | follows has no created_at in the README → "follows per day" may not be possible; 1_check confirms. |
| Chat `hnutebcsskpvechxbmxo` | conversations (id, created_at / last_message_at only) | messages, message_attachments, last_message_preview, device_push_tokens, chat_profiles | conversation created_at to confirm in 1_check. |
| Gemmit `yicrrarvefhrvgzdfzlh` (dump: `dumps/gemmit/schema.sql`) | posts (id, circle_id, post_type, flair, created_at) · circles (id, category, is_paid, member_count, post_count, created_at) · circle_memberships (joined_at) · comments (id, created_at) · post_reports (reason, created_at) | post title/body/media, comment body, report details, video_comments text | — |
| Quvlet video / TraceGems / Websites | Step 1: not used | — | — |
Note: `dumps/gemmit/inspect.txt` is really the **Websites** project (blogs tables) — mislabelled. Gemstok + MKV dumps failed (psql not connected), so their files hold only an error.
