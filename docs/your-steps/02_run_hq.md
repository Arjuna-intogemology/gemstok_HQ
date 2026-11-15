# 2 · Build and open HQ

```
cd ~/Development/Gemstok/gemstok_hq
flutter pub get
flutter analyze
flutter run -d macos
```

- **Send Claude everything `flutter analyze` prints.** The new store / ads / website code hasn't been
  compiled yet, so a few small fixes are likely. Red errors in the run log too (copy the first 30 lines).
- The warning "plugins do not support Swift Package Manager" is from flutter_secure_storage. Ignore it.
- "Failed to foreground app" is harmless: click HQ in the Dock.

## What to expect when it opens

- **Touch ID** asks by itself when HQ is the app in front. It locks again after 5 minutes idle, sleep,
  or screen lock. "Lock now" is at the bottom of the sidebar.
- **Keychain prompt** ("gemstok_hq wants to use … in your keychain"): type your **Mac login password**
  and press **Always Allow**. HQ keeps everything in one Keychain item, so it asks at most once per build.
- Screens without a database connection show "not connected yet". That's normal until step 3.

## After a code change from Claude

- Usually `r` (hot reload) in the terminal is enough.
- New package, new asset, or strange errors → `q`, then `flutter run -d macos` again.
- Still odd → `flutter clean && flutter pub get && flutter run -d macos`.
