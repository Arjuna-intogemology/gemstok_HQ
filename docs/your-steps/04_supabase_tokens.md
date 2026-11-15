# 4 · Supabase access tokens (Servers screen)

What they switch on: HQ → **Servers** shows each project as Active / **PAUSED**, its edge functions,
calls and errors, and the last 24 h of logs.

Your projects sit in **two Supabase accounts**, so there are two slots:
- **Account 1** — the Gemstok account
- **Account 2** — the IntoGemology account

For each account:
1. Sign in to supabase.com with that account.
2. Open supabase.com/dashboard/account/tokens (or: avatar top right → Access Tokens) → **Generate new token**.
3. Name it `Gemstok HQ`. Copy it (starts with `sbp_`).
4. HQ → Settings → **Supabase access tokens** → that slot → **Add** → paste → Save to Keychain.
5. The row shows "sees N projects: …" in green.

Good to know:
- A token like this *could* change projects. HQ's code can only send **read** (GET) requests to
  5 fixed addresses, so it never does. Don't use the token anywhere else.
- To cancel it any time: same page in Supabase → delete the token. HQ then shows the slot as failing.
