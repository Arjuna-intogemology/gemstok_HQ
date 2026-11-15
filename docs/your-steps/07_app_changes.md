# 7 · App changes (in the next app builds)

These are code changes in the apps, so they ride along with your next ManiKVault / Gem Broker /
Quvlet builds. Claude can write each one when you say "do app change 1" (etc.) in that app's chat —
you build, test and publish. The database side for 1–5 is already live.

Same plan as the Claude doc "App changes for Gemstok HQ — plan".

---

Seven small app and website changes make HQ's numbers exact: which app people join in, which campaign brought them, and who is really active. Plan only — nothing here is built yet. The database side for the first three already exists.

## The changes at a glance

| # | Change | Apps / sites | Database side | Effort | What HQ gains |
| --- | --- | --- | --- | --- | --- |
| 1 | Count an app open at start-up, not only in Browse / Market | ManiKVault, Gem Broker | none | 15 min | "Active" includes Vault-only users |
| 2 | Record the sign-up app once, for new accounts | ManiKVault, Gem Broker, Quvlet | `record_signup()` — live | 1 h | Exact sign-ups per app; no more "guessed" |
| 3 | Pass the campaign tag from the Play install referrer | ManiKVault, Gem Broker (Android) | `member_signup.from_tag` — live | 2 h | Sign-ups per campaign link / QR |
| 4 | "How did you hear about us?" — one optional question | all three apps | `member_signup.heard_from` — live | 2 h | Where iPhone sign-ups come from |
| 5 | Website sign-ups call `record_signup` too | intogemology.com, account.gemstok.com | live | 1 h | Website sign-ups counted exactly |
| 6 | Market views for every listed stone, not only boosted ones | Gem Broker | new table + function (to write) | half a day | Views per stone, seller interest |
| 7 | ManiKVault Android credit buys through the newer purchase function | ManiKVault | none (function exists) | half a day | Money screen sees every store purchase |

## Each change

**1. App open at start-up.** Today `DeviceTrackingService.trackSession` is called from `lib/features/browse/browse_panel.dart` (ManiKVault) and `lib/broker/market/market_screen.dart` (Gem Broker), so a launch only counts when that tab opens. Move the call to where the signed-in home screen first shows (after sign-in in `app_bootstrap.dart`'s start-up path). Keep its once-per-session guard. Quvlet already calls it right after sign-in in `core/services/auth_service.dart`.

**2. Sign-up app.** Right after sign-in, call `supabase.rpc('record_signup', params: {'p_app': 'manikvault', 'p_app_version': '<version+build>', 'p_device_os': 'ios'|'android'})` once per install (a `shared_preferences` flag like `signup_recorded`). Old accounts get `{ok:false, reason:'not_new'}`, which the app ignores; the server only accepts accounts made in the last 48 hours, and the first call wins. Best place: next to `trackSession` in `core/services/device_tracking_service.dart`, so all three apps share one pattern. Apple / Google / Email is filled in by the server from the sign-in itself.

**3. Campaign tag (Android).** The Get page now sends Google Play `referrer=utm_source=<tag>`. Add the `play_install_referrer` package, read the referrer once on first launch, keep `utm_source` if it matches `^[a-z0-9_-]{2,40}$`, and pass it as `p_from_tag` in change 2's call. iPhones don't get a referrer; change 4 covers them.

**4. "How did you hear about us?"** One optional screen after a new account: Friend · WhatsApp · Facebook · YouTube · Gem fair / market · Agent · Search · Other. Send the code (e.g. `whatsapp`, `gem_fair`) as `p_heard_from`; never free text. A second `record_signup` call within 48 hours may add it, since the server fills empty fields only.

**5. Websites.** intogemology.com and account.gemstok.com call the same function with `p_app` = `intogemology` / `gemstok` and `p_device_os` = `web`, after a new account's first sign-in (they already use the Gemstok session).

**6. Market views for every stone.** Gem Broker already counts boosted-stone views and taps (`stone_boost_stats`, batched about every 30 s). The same batching can send every market card view to a new `stone_views (stone_id, day, views, taps)` table, through a function with the same limits (no self-views, at most 50 per stone per batch). Database side to write, test and run first; then the app.

**7. ManiKVault Android credit buys.** `lib/features/profile/wallet_tab.dart` calls the older `process-credit-purchase` (Android only, trusts the member id it's sent, no `store_purchases` row). Move it to the same flow as Gem Broker's `gembroker-credit-purchase` (`lib/broker/credits/credit_store.dart`): one purchase = one row, never credited twice, and HQ's Money screen sees it.

## Order to ship them

Bundle 1–3 into the next ManiKVault and Gem Broker builds: they share one file and give HQ exact sign-ups, active users and Android campaign numbers. Then 4 and 5, then 6 and 7.

- [ ] 1 + 2 + 3 — next ManiKVault and Gem Broker builds (Quvlet: 2 only, at its launch)
- [ ] 4 — "How did you hear about us?" in all three apps
- [ ] 5 — intogemology.com and account.gemstok.com
- [ ] 6 — market views (database first, then Gem Broker)
- [ ] 7 — ManiKVault Android credit buys

Open question: should change 4 also show on Android, where the referrer already gives the tag? Asking everyone keeps the numbers comparable.
