# Owner checklist: real ads and analytics (about 10 minutes)

The game already runs AdMob and Firebase with **Google's test IDs** (spec v2 §8). This list switches
them to your own accounts. Nothing here is secret except `google-services.json`, which must never be
committed (the repo is public).

**Before you start:** the package ID is `com.iiakshat.sirensquad`. It is permanent after the first
Play upload, so use exactly this everywhere below.

## 1. AdMob (5 minutes)

1. Open <https://admob.google.com> → **Apps** → **Add app** → Android → "Is the app listed on a
   supported app store?" **No** (for now) → name **Siren Squad**.
2. Copy the **App ID** (`ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY`).
3. **Ad units** → add two:
   - **Rewarded** (name it `rewarded`): copy its ID (`ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN`).
   - **Interstitial** (name it `interstitial`): copy its ID.
4. **Blocking controls** → **Content** → **Maximum ad content rating**: **PG**. The game also asks
   for G on every child's request and caps adults at PG, so this is a second lock.
5. **Privacy & messaging** → **European regulations (GDPR)** → create a message for Siren Squad and
   **publish** it. Without a published message the consent form cannot show in the EEA/UK.
6. Leave mediation off. Only AdMob is in the build, and it is on Google's Families self-certified list.

## 2. Firebase (4 minutes)

1. Open <https://console.firebase.google.com> → **Add project** → "Siren Squad" → keep Google
   Analytics **on** → pick or create an Analytics account.
2. **Add app** → Android → package `com.iiakshat.sirensquad` → nickname "Siren Squad" → skip SHA-1
   → **Download google-services.json**.
3. Put the file in the **project root**: `Troop/google-services.json` (next to `project.godot`).
   - The build copies it into `android/build/` (the plan's location) on every export, so a
     reinstalled build template never loses it. You may also drop it straight into
     `android/build/`; that works too, but a template reinstall can wipe it there.
   - Check that git ignores it: `git check-ignore google-services.json android/build/google-services.json`
     must print both paths. **Never** `git add -f` it.
4. Recommended Analytics settings (Firebase → Project settings → Integrations → Google Analytics →
   open the GA4 property → Admin):
   - **Data collection**: Google signals **off**.
   - **Data retention**: **2 months**.
   - **Ads personalization**: turn it off for all regions.
   These match what `docs/PRIVACY.md` and `docs/play_data_safety.md` say.

## 3. Paste the IDs (1 minute)

Edit `config/ads.json`:

```json
"is_real": true,
"android": {
  "test": { ...leave Google's test IDs as they are... },
  "real": {
    "app_id": "ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY",
    "rewarded": "ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN",
    "interstitial": "ca-app-pub-XXXXXXXXXXXXXXXX/MMMMMMMMMM"
  }
}
```

- The app ID goes into the Android manifest automatically: the `addons/siren_privacy` editor plugin
  writes it into `addons/AdmobPlugin/android_export.cfg` (generated, git-ignored) when the editor or
  an export starts.
- **Testing real IDs on your own phone:** never tap your own real ads (AdMob can suspend the
  account). Run the game once with a USB cable and `adb logcat | findstr "test device"`; AdMob prints
  a hashed device ID. Put it in `"test_device_hashed_ids": ["..."]` and your phone gets test ads
  even with real IDs. Or keep `"is_real": false` until the store release.
- To force the old placeholder popup everywhere, set `"provider": "placeholder"`.

## 4. Build

`build_apk.bat` (one-time: `python -I tools/setup_android.py`, which now also installs a JDK 17,
Android platform 36, build-tools 36.1.0 and the Gradle build template). The first Gradle build
downloads Gradle and the Android libraries (a few hundred MB, then cached in `%USERPROFILE%\.gradle`).

## 5. Play Console (when you create the store listing)

- **App content → Target audience:** include the under-13 age groups and the older ones (a mixed
  audience). The Families policy then applies: work through `docs/families_checklist.md`.
- **Ads:** "Yes, my app contains ads".
- **Data safety:** copy the answers from `docs/play_data_safety.md`.
- **Privacy policy:** host `docs/PRIVACY.md` (for example with GitHub Pages on the public repo),
  fill in the contact email and date first, and paste the URL in the store listing.
- **app-ads.txt:** AdMob shows a one-line `app-ads.txt` for your developer website. Put it at the
  root of the website you list in Play (GitHub Pages works). Ads serve without it, but fill is
  lower.

## What happens in the game

- First launch: a neutral birth-year wheel (numbers only). Nothing starts before it is answered.
- **Child** (under 13; under 18 when the phone's locale or clock says India): AdMob with the
  child-directed and under-age tags, max rating G, non-personalised ads, no advertising ID, no
  consent form. Firebase is **never started**; events stay in the local log on the phone.
- **Adult:** in the EEA/UK/Switzerland the Google consent form shows first; then normal AdMob ads
  (max PG). Firebase Analytics starts with ad-ID and SSAID collection off and ad storage /
  personalisation consent denied.
- No network, or no ad ready yet: rewarded buttons fall back to the placeholder popup (the reward
  still works); an interstitial is simply skipped.

## When something does not work

| Symptom | Check |
|---|---|
| Firebase console shows no users | `google-services.json` is in the project root, its package is `com.iiakshat.sirensquad`, and you answered the age wheel as an adult. Debug view: `adb shell setprop debug.firebase.analytics.app com.iiakshat.sirensquad`. |
| Real ads never show | New AdMob apps can take hours; check AdMob → Apps for "limited ad serving"; app-ads.txt. The placeholder stands in meanwhile. |
| Build says "Missing android_source.zip" | Run `python -I tools/setup_android.py`. |
| First build stops while downloading Gradle or libraries | Slow connection: run `build_apk.bat` again. The Gradle download resumes where it stopped, and finished libraries stay cached. |
| Build fails in Gradle after a Godot upgrade | `python -I tools/android_template.py --force` reinstalls the template for the new version. |
