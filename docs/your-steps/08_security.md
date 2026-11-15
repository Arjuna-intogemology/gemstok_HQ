# 8 · Security jobs

Known gaps, most important first. None is an emergency today (few users, nothing seen abused), but
each should be closed before bigger marketing pushes.

## A · 2FA everywhere (15 min)

Turn on two-factor sign-in for: **GitHub**, **Supabase** (both accounts), **Cloudflare**,
**Google** (Play Console / Cloud / AdMob account), **Apple ID** (App Store Connect).
These accounts can change or delete everything; a stolen password alone shouldn't be enough.

## B · Turn on "Enforce SSL" (5 min per project)

Found OFF on Gemstok (13 Nov). It makes every database login use encryption.
1. Supabase → one project → **Database → Settings → SSL Configuration** → **Enforce SSL on incoming connections** → on.
2. Test straight away: open the apps (sign in, open Browse/Market), and HQ → Settings → Check.
   HQ already uses SSL; the apps use HTTPS, so nothing should change.
3. Problem? Switch it off again and tell Claude what broke.
Do one project per day, Gemstok last (it has the most users).

## C · Open functions any database login may call — Gemstok 9, Chat 3, TraceGems 2, Quvlet video 6 (Claude writes, you run)

Found by HQ's first check (13 Nov). Some trust the caller's user id, which a direct database login
could fake. HQ's own login can't do harm with them, but the gap should close.
When you're ready, tell Claude **"start the 9 functions job"**. Claude will:
1. write a read-only SQL that lists the 9 and which apps call each one (from the app code),
2. then a guarded change that removes access only where no app needs it,
3. with a test and an undo — same pattern as the HQ folders.

## D · HQ certificate check (Claude's job, no action now)

HQ's database connection is encrypted but doesn't yet check *which* server it talks to (macOS
doesn't trust Supabase's root certificate). Claude will add "pinning" later; no step for you until then.

## E · Old gemstok.com files still public (from TODO-VIP)

5 private files were moved to `docs/website-private/` in gemstok.comPrivate (15 Oct) but not pushed.
1. Commit + push that repo.
2. Cloudflare → that Pages project → **Deployments** → delete the old deployments
   (their `*.pages.dev` links still serve those files).

The full list of open items stays in `gemstok-backend/TODO-VIP.md`.
