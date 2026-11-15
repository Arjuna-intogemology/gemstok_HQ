# 5 · Store, ads and website keys

What they switch on:
- **Money** + **Downloads** → App Store (iPhone downloads, updates, in-app purchases, money after Apple's cut, reviews),
  Google Play (installs, uninstalls, active devices, reviews), AdMob (earnings, impressions, clicks).
- **Websites** → visitors and page views per site (Cloudflare).

Where they go: HQ → Settings → **Other services** → that row → **Add**. Each is read-only.
Empty box when replacing = keep what's saved. HQ shows only "set / not set".

Easiest first: Cloudflare (one token), then App Store, Google Play, AdMob.

---

## Cloudflare (5 min)

1. dash.cloudflare.com → top right avatar → **My Profile** → **API Tokens** → **Create Token**.
2. Template **Read analytics and logs** → **Use template**.
3. Zone Resources: **Include · All zones** → Continue → **Create Token**. Copy it.
4. HQ → Other services → Cloudflare → Add → paste → Save. Row turns green "Working".

## App Store Connect (10 min)

1. appstoreconnect.apple.com → **Users and Access** → **Integrations** → **App Store Connect API**
   → **Team Keys** → **+** (first time: request access, it's instant).
2. Name `Gemstok HQ`, Access **Sales** → Generate.
3. Copy the **Issuer ID** (above the list) and the **Key ID** (in the row).
4. **Download API Key** — the `.p8` file downloads **only once**. Open it in TextEdit, copy all of it
   (including the `-----BEGIN PRIVATE KEY-----` and `END` lines).
   Then move the .p8 file somewhere safe (or delete it once HQ shows "Working"). Never into a repo.
5. **Vendor number**: App Store Connect → **Payments and Financial Reports** → top left number.
6. HQ → Other services → App Store Connect → Add → fill the 4 boxes → Save.

Apple posts each day's sales about a day later, so "yesterday" may still be 0 in the morning.

## Google Play (20 min, the longest)

Part A — a reading account in Google Cloud:
1. console.cloud.google.com → pick the project that your apps use → **APIs & Services → Library** →
   enable **Google Play Android Developer API**.
2. **IAM & Admin → Service Accounts → Create service account** → name `gemstok-hq-reader` →
   skip the roles → Done.
3. Open it → **Keys → Add key → Create new key → JSON** → a file downloads.
   Copy its e-mail address (ends in `iam.gserviceaccount.com`).

Part B — let it read Play reports:
4. play.google.com/console → **Users and permissions → Invite new users** → paste that e-mail.
5. Account permissions: tick **only** "View app information and download bulk reports (read-only)".
   Apps: ManiKVault and Gem Broker → Invite.

Part C — the bucket address:
6. Play Console → **Download reports → Statistics** → **Copy Cloud Storage URI**
   (looks like `gs://pubsite_prod_rev_…/stats/…`; HQ only needs the bucket part, pasting the whole thing is fine).

Part D — into HQ:
7. HQ → Other services → Google Play → Add:
   - Service account JSON: open the JSON file in TextEdit, copy all of it.
   - Reports bucket: the `gs://…` address.
   - Package names: leave empty (= `com.gemstok.manikvault, com.gemstok.gembroker`).
8. Save. Then move the JSON file out of Downloads to somewhere safe.

A new invite can take up to a day before Google lets it read the reports. "403" until then is normal.

## AdMob (15 min)

AdMob doesn't allow reading accounts, so HQ signs in **as you**, once, with read-only access.

1. console.cloud.google.com (same project) → APIs & Services → Library → enable **AdMob API**.
2. **OAuth consent screen** → External → app name `Gemstok HQ` → your e-mail → save.
   Under **Test users** add your AdMob Google e-mail.
3. **Credentials → Create credentials → OAuth client ID** → type **Desktop app** → name `Gemstok HQ`
   → Create. Copy **Client ID** and **Client secret**.
4. **Publisher ID**: apps.admob.com → Settings → Account information → `pub-…`.
5. HQ → Other services → AdMob → Add → the 3 boxes → Save.
6. Press **Sign in with Google**. Your browser opens → pick your AdMob account → allow
   "See your AdMob data" → the page says "Done". Back in HQ the row turns green.

If Google warns "app isn't verified": that's your own app in testing — Continue.
Test-mode sign-ins can expire after 7 days; if AdMob goes red, press Sign in with Google again
(or publish the consent screen to keep it).
