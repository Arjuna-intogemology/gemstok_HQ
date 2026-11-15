# 3 · Databases — HQ's read-only login in each one

**Full guide:** `gemstok-backend/projects/all-projects/hq_setup/HQ_SETUP_STEPS.md`
(also in the Claude doc "Gemstok HQ — database setup steps").

In short, for each database folder in `hq_setup/` (`1_gemstok` … `8_tracegems`):

1. Supabase → that database → **SQL Editor**.
2. Run the files **in number order** (`01`, `02`, `03` …).
   - `_check` → compare with the guide.
   - `_change` → for `hq_reader` / `app_config_operator`, put a NEW password on the one line ending
     `◀◀ YOUR PASSWORD` first; close the tab without saving afterwards.
   - `_test` → a red error is normal; copy the `TEST RESULT` line for Claude.
3. After the `hq_reader` files: Supabase → **Connect** → **Session pooler** → copy the address ending in
   `pooler.supabase.com` → HQ → Settings → that database → **Add** → address + password → **Check**.
4. Cron files: if the check's first value is `false`, skip them.

Order: Gemstok extras → ManiKVault data → Social → Chat → Gemmit → Websites → Quvlet video → TraceGems.

| Database | Status |
|---|---|
| Gemstok — login + member_signup | ✅ done |
| Gemstok — report details · app switches · cron | ☐ |
| ManiKVault data | ☐ |
| Social | ☐ |
| Chat | ☐ |
| Gemmit | ☐ |
| Websites (+ campaign counter) | ☐ |
| Quvlet video | ☐ |
| TraceGems | ☐ |
