# Play Console: Data safety answers

> For **App content → Data safety**. Matches the build as of spec v2 (2026-11-12): AdMob
> (`play-services-ads` 24.9.0 via the Godot AdMob plugin) for everyone, Google Analytics for
> Firebase for older players only, a local save and a local event log. Google's own disclosure
> pages for its SDKs are the source for the SDK rows; re-check them before submitting:
> AdMob <https://developers.google.com/admob/android/privacy/play-data-disclosure>,
> Firebase <https://firebase.google.com/docs/android/play-data-disclosure>.
>
> Play asks about data that **leaves the device**. The save file, the birth year and the local
> event log never leave the phone, so they are not "collected".

## Overview questions

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** (through the AdMob and Firebase SDKs) |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (both SDKs use TLS) |
| Do you provide a way for users to request that their data is deleted? | **Yes**, by email (the contact in `docs/PRIVACY.md`) |
| Account creation | **No accounts** |
| Has your app been independently security reviewed (MASA)? | No |
| Is this app for children? / Target audience | Mixed: includes under-13 groups (see `docs/families_checklist.md`) |

## Data types

"Collected" means it leaves the device. "Shared" means it goes to a third party for that party's own
use. AdMob uses ad data partly for Google's own purposes (fraud prevention, ad measurement), so the
ad rows are marked **shared** to be safe. Firebase is a service provider working for us, so its rows
are collected but not shared.

| Category → type | Collected | Shared | Required or optional | Purposes | Source |
|---|---|---|---|---|---|
| **Location → Approximate location** (from the IP address) | Yes | Yes | Required (cannot be turned off in the app) | Advertising or marketing; Analytics; Fraud prevention, security and compliance | AdMob (everyone); Firebase (older players) |
| **App activity → App interactions** (levels, taps per 10 s, ad buttons, ad views and clicks) | Yes | Yes | Required | Analytics; Advertising or marketing; Fraud prevention | Firebase (older players); AdMob (everyone, ad interactions) |
| **App info and performance → Diagnostics** (app launch time, hang rate, energy use) | Yes | Yes | Required | Analytics; Fraud prevention | AdMob |
| **Device or other IDs** (Android advertising ID and app set ID for older players' ads; Firebase app-instance ID) | Yes | Yes | Required | Advertising or marketing; Analytics; Fraud prevention | AdMob (older players: ad ID; everyone: app set ID); Firebase (older players: app-instance ID) |

**Not collected:** personal info (name, email, user IDs, address, phone, race, political or
religious beliefs, sexual orientation, other info), financial info, health and fitness, messages,
photos and videos, audio files, files and docs, calendar, contacts, web browsing, precise location,
crash logs, other app performance data, installed apps, in-app search history.

**The birth year** is used only on the device to choose the ad and analytics settings. It is never
sent anywhere, so it is not declared.

## Notes for the form

- **Children's data:** for a younger player (under 13, or under 18 in India) the game marks every
  ad request as child-directed and under the age of consent, asks for max rating G and
  non-personalised ads, and never starts Firebase. Google's SDK then does not send the advertising
  ID (GMA SDK 20.6.0 or later). The form has no separate column for this. The policy page and the
  Families declarations describe it.
- **Advertising ID permission:** the AdMob SDK declares `com.google.android.gms.permission.AD_ID`.
  That is allowed for a mixed-audience app (not for one that targets **only** children). In
  **App content → Advertising ID**, answer **Yes**, purposes **Advertising or marketing** and
  **Analytics**.
- **Consent:** older players in the EEA/UK/Switzerland see Google's UMP consent form before the
  first ad request. The AdMob GDPR message must be published in AdMob (see
  `docs/owner_ads_setup.md`).
- If you later add Crashlytics, cloud saves, in-app purchases, mediation networks or accounts,
  this form **must** be updated before that build ships.
