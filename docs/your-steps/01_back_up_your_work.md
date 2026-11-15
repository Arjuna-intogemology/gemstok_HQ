# 1 · Back up your work to GitHub (urgent)

Today, 14 Nov 2026:
- `gemstok-backend` is a git repo with **no remote** and about **135 changed files not committed**.
  All the SQL, edge functions and TODO-VIP live only on this Mac.
- `gemstok_hq` is **not a git repo at all**.

If the Mac is lost or breaks, both are gone. Do this before anything else.

## A · gemstok-backend

1. GitHub → **New repository** → name `gemstok-backend` → **Private** → don't add a README → Create.
2. Terminal:
   ```
   cd ~/Development/Gemstok/gemstok-backend
   git grep -nIE "service_role|sb_secret_|eyJhbGciOi|BEGIN PRIVATE KEY|sbp_"
   ```
   It must show **nothing real** (comments that only name these words are fine).
   If it shows a real key → stop and tell Claude which file (not the key).
3. Check nothing secret is about to be added:
   ```
   git status --short | grep -iE "\.env|secret|dump|\.p8|\.json$"
   ```
   Anything listed → ask Claude before adding it.
4. Save and push:
   ```
   git add -A
   git commit -m "HQ: readers, report details, app config, campaign visits, cron, hq_setup"
   git remote add origin https://github.com/<your-account>/gemstok-backend.git
   git push -u origin main
   ```

## B · gemstok_hq

1. GitHub → New repository → `gemstok_hq` → **Private** → no README → Create.
2. Terminal:
   ```
   cd ~/Development/Gemstok/gemstok_hq
   git init -b main
   git status --short
   ```
   Check the list: `ask/`, `ideas/`, `build/` and `leads/campaigns.json` must **not** be there (they're in `.gitignore`:
   your questions, business snapshots, users' ideas and people's campaign links stay on the Mac).
3. ```
   git add -A
   git commit -m "Gemstok HQ — first commit"
   git remote add origin https://github.com/<your-account>/gemstok_hq.git
   git push -u origin main
   ```

## C · Then

- Turn on **2FA** on GitHub (Settings → Password and authentication) — these repos hold the whole backend.
- From now on: commit + push after each working session. Claude never pushes; you do.
