# SSL certificate (optional, recommended)

Put Supabase's CA certificate here as **`supabase-ca.crt`** so HQ checks it is really talking
to Supabase (not just "encrypted").

Supabase → any project → Project Settings → Database → **SSL Configuration** → Download certificate
(`prod-ca-2021.crt`) → rename to `supabase-ca.crt` → put it in this folder → restart HQ.

It is a public certificate (not a key), so it is fine in git.
If the Settings check then fails with a certificate error, move the file out and tell Claude.
