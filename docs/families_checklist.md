# Google Play Families policy: checklist for Siren Squad

> The target audience **includes children** (owner, spec v2 §8), so the Families policy applies to
> the whole app. Each item below says where the build meets it, or what the owner still has to do.
> Re-read the live policy before each submission:
> <https://support.google.com/googleplay/android-developer/answer/9893335>.
> **[owner]** marks the steps only the owner can do.

## Audience and age screen

- [x] **Neutral age screen** (`src/ui/age_screen.gd`): a birth-year wheel with numbers only, no
      "are you a kid" wording. It starts blank, with no pre-picked adult year. It is shown once,
      before any ad or analytics SDK starts (`Game.audience_ready`).
- [x] **Unknown age = child.** Until the wheel is answered, `Game.is_child()` is true and neither
      SDK starts.
- [x] **Child rule** (`src/core/audience.gd`): under 13; under 18 when the region, locale or India
      time zone (UTC+5:30) points to India (DPDP Act). Tests: `tests/test_audience.gd`.
- [x] The answer is stored only on the device (save `birth_year`, `is_child`). It survives
      "reset progress", so the age question cannot be retried for a different answer.
- [ ] **[owner]** Play Console → **App content → Target audience and content**: pick the under-13
      age groups and the older ones. Answer the "appeal to children" questions honestly.

## Ads (AdMob)

- [x] **A Families self-certified ads SDK:** Google AdMob (Google Mobile Ads SDK 24.9.0) is on
      Google's self-certified list. **No mediation networks** are enabled (`android_export.cfg` is
      generated without a `[Mediation]` section).
- [x] **Child requests** (`Ads.request_config(true)`, fixed in code; config cannot loosen it):
      `tag_for_child_directed_treatment = TRUE`, `tag_for_under_age_of_consent = TRUE`, max ad
      content rating **G**, non-personalised only (`PersonalizationState.DISABLED`), first-party
      ID off, no UMP form. Set through `MobileAds.setRequestConfiguration` **before**
      `initialize()` and before any ad loads. Test: `test_child_request_config`.
- [x] **No advertising ID from children:** with the child-directed tag, GMA SDK 20.6.0 and later
      does not send the AAID. Firebase, which could also read it, never starts for a child.
- [x] **Adults in a mixed-audience app:** max rating **PG** (`config/ads.json` adult_tags; code
      clamps anything above PG back to PG), UMP consent first in GDPR regions. Test:
      `test_adult_request_config`.
- [x] **Ad format rules:** no ads during gameplay. Interstitials only between levels, with
      frequency caps (`economy.json` ads.interstitial), never right after a rewarded ad, always
      closable. Rewarded ads are opt-in from an ad-icon button. No ad hides a game control.
- [x] **No deceptive ads:** no fake close buttons, no ads disguised as game content, no forced ad
      loops (spec v1 §0). The placeholder that stands in when AdMob has no ad shows a countdown and
      a close X.
- [ ] **[owner]** AdMob → **Blocking controls → Content → Maximum ad content rating: PG** (a
      second lock; `docs/owner_ads_setup.md` step 1.4).
- [ ] **[owner]** AdMob → app settings: if AdMob asks whether the app is child-directed, answer
      "mixed audience / tag per request". Do **not** mark the whole app child-directed, or adults'
      ads would lose consent-based personalisation. That is allowed, but it is your choice.
- [ ] **[owner]** Play Console → **App content → Ads**: "Yes, contains ads". **Advertising ID**:
      Yes (AdMob declares the `AD_ID` permission; allowed because the audience is mixed, not
      children only).

## Analytics (Firebase)

- [x] **Never started for a child:** `Analytics.provider_for(is_child=true) == "local"`
      (`test_firebase_not_started_for_child`). The manifest also removes Firebase's auto-start
      provider (`FirebaseInitProvider`, `addons/siren_privacy`), so nothing runs until
      `Analytics.start_sdk()` calls it for an adult.
- [x] **Off by default in the manifest** (godotx_firebase `privacy_safe_defaults`):
      `firebase_analytics_collection_enabled=false` and every Google consent default denied. For an
      adult the game then grants only `analytics_storage`. `ad_storage`, `ad_user_data` and
      `ad_personalization` stay denied.
- [x] **No ad ID or Android ID in Firebase:** `google_analytics_adid_collection_enabled=false` and
      `google_analytics_ssaid_collection_enabled=false` for everyone.
- [x] Children's taps and events stay in the local log on the phone (`user://events.log`).
- [x] No Crashlytics, no Cloud Messaging (export preset: both off).
- [ ] **[owner]** GA4 property: Google signals **off**, data retention **2 months**, ads
      personalisation **off** (`docs/owner_ads_setup.md` step 2.4).

## Content and the store listing

- [x] Content stays at **cartoon violence**: enemies fall and fade, with no blood. Weapons are
      stylised, with no real brand or model names (spec v2 Global Constraints).
- [x] No chat, no user-generated content, no accounts, no location, camera or microphone use, no
      links out of the app except the ads themselves.
- [x] No real-money purchases (v2 has ads only). Rewarded ads give game items only.
- [ ] **[owner]** **IARC content rating** questionnaire: answer for cartoon/fantasy violence. Expect
      roughly PEGI 7 / ESRB Everyone 10+. If the rating comes out higher than the youngest target
      age group allows, adjust the target age groups.
- [ ] **[owner]** Store listing: no "for kids" claims you cannot back up. Screenshots show real
      gameplay (no ad-style fake gameplay; parent CLAUDE.md fairness promise).
- [ ] **[owner]** Host `docs/PRIVACY.md` (fill in the contact email and date) and link it in the
      listing **and** in the game. The Settings panel's credits page is the place for the link when
      the URL exists.
- [ ] **[owner]** **Data safety** form: copy `docs/play_data_safety.md`.
- [ ] **[owner]** Families policy declaration: tick the "Families policy requirements" box only
      after every item above is checked.

## Before each release (repeat)

- [ ] `git check-ignore google-services.json android/build/google-services.json` prints both paths.
- [ ] `config/ads.json` `is_real` matches the build: test IDs for testers, real IDs only for the
      Play release.
- [ ] On a phone answered as a child: the game's local log (`user://events.log`) has
      `ad_sdk {"child": true}`, and `adb logcat | findstr FirebaseApp` shows no
      `FirebaseApp initialization successful` line. On a phone answered as an adult: Firebase
      initialises, and the EEA consent form shows when tested through an EEA VPN.
- [ ] No new SDK was added without updating this list, `docs/PRIVACY.md` and
      `docs/play_data_safety.md`.
