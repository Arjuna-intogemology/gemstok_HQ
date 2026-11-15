# 6 · Publish the manikvault.com Get page (campaign clicks)

What it switches on: HQ → Leads → **Clicks** per campaign link / QR.

The Get page (`manikvault.com/get/`) was updated: when someone opens a campaign link
(`…/get/?from=<tag>`) it counts one visit per phone per day (no personal data) and passes the tag
on to Google Play.

**Do first:** the Websites database steps in `hq_setup/6_websites` (files 01–06, the campaign counter).
Publishing before that is harmless — the page just counts nothing yet.

1. Look at the change (only one file):
   ```
   cd ~/Development/Gemstok/manikvault.com
   git status --short          # shows: M get/index.html
   git diff get/index.html
   ```
2. Push it — Cloudflare Pages republishes in about 20 seconds:
   ```
   git add get/index.html
   git commit -m "Get page: count campaign visits, pass tag to Google Play"
   git push
   ```
   (If Cloudflare Pages builds from a different branch than `main`, push or merge to that branch.)
3. Test: HQ → Leads → create campaign `test-1` → open its link on your phone →
   wait a minute → **Refresh** in HQ → "Clicks: 1". Then **Pause** that campaign.
