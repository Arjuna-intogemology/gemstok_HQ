# Your steps — everything that needs Arjuna's hands

Claude can write code and SQL, but some things only you can do: run SQL, type keys, push to git,
build apps. This folder lists all of them, in a sensible order. Tick them off here as you go.

Rules that stay true everywhere:
- Never paste a key, password or token into a chat. Type it into HQ → Settings only.
- Run every SQL file yourself, in number order. Send Claude the `TEST RESULT` lines.
- Nothing is ever deleted: old files go to `_removed/<topic-date>/`.

| # | File | What | Time | Why it matters |
|---|---|---|---|---|
| 1 | [01_back_up_your_work.md](01_back_up_your_work.md) | Put `gemstok-backend` and `gemstok_hq` on GitHub (private) | 20 min | **Urgent.** Today they exist only on this Mac |
| 2 | [02_run_hq.md](02_run_hq.md) | Build and open HQ, send Claude the analyze output | 5 min | New code (stores, ads, websites) is not compiled yet |
| 3 | [03_databases.md](03_databases.md) | HQ login in each database (SQL + pooler address) | 5–10 min per database | Fills Joining, Using, Doing, Reports, Storage … |
| 4 | [04_supabase_tokens.md](04_supabase_tokens.md) | Two Supabase access tokens | 5 min | Servers screen: paused projects, functions, logs |
| 5 | [05_store_ads_website_keys.md](05_store_ads_website_keys.md) | Cloudflare, App Store, Google Play, AdMob keys | 10–20 min each | Money screen + website visits |
| 6 | [06_publish_get_page.md](06_publish_get_page.md) | Push manikvault.com so campaign clicks count | 5 min | Leads: clicks per QR / link |
| 7 | [07_app_changes.md](07_app_changes.md) | 7 small changes in the apps (next builds) | over the next builds | Exact sign-ups per app and per campaign |
| 8 | [08_security.md](08_security.md) | SSL on, 9 open functions, 2FA | spread out | Closes known gaps |

## Checklist

- [ ] 1 · `gemstok-backend` on GitHub (private), first push done
- [ ] 1 · `gemstok_hq` on GitHub (private), first push done
- [ ] 2 · HQ builds; `flutter analyze` output sent to Claude
- [ ] 3 · Databases: Gemstok extras · MKV data · Social · Chat · Gemmit · Websites · Quvlet video · TraceGems
- [ ] 4 · Supabase token 1 (Gemstok account) · token 2 (IntoGemology account)
- [ ] 5 · Cloudflare · App Store Connect · Google Play · AdMob
- [ ] 6 · manikvault.com pushed, test campaign shows 1 click
- [ ] 7 · App changes 1–3 in the next ManiKVault + Gem Broker builds
- [ ] 8 · Enforce SSL on every project · 2FA on GitHub / Supabase / Cloudflare / Google / Apple

When you're stuck on any step: send Claude the step number and what you see (a screenshot is fine,
as long as no key or password is on it).
