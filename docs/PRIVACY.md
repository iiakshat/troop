# Siren Squad: Privacy Policy

<!-- Maintainers: this file is the public policy (linked from the game's Settings and the Play Console). Keep it in step with docs/privacy/index.html and docs/play_data_safety.md whenever an SDK or setting changes. -->

**Last updated:** 13 November 2026
**Developer:** axnex (Gurugram, India). **Contact:** jakshat569@gmail.com

Siren Squad is an offline arcade game. You need no account, and we never ask for your name, email,
phone number, contacts, photos or precise location. The game plays fully offline. When the phone is
online, two Google services may run, as described below.

## 1. The age question

On first launch the game asks for a **birth year** (a number wheel). The year stays **on your phone
only**, in the game's save file. We never send it anywhere. The game uses it to decide which rules
below apply:

- **Younger players:** under 13, or under 18 when the phone's region, language setting or time zone
  points to India (India's Digital Personal Data Protection Act, 2023).
- **Older players:** everyone else.

Until the question is answered, the game treats the player as a younger player and starts no
online service at all.

## 2. What stays on your phone

- Your progress, coins, settings and birth year (the save file).
- A small local log of game events (levels played, ads watched, taps per level) that helps us debug.
  It never leaves the phone by itself, and the game deletes old entries as it grows.
- To choose its graphics quality, the game reads the phone's memory size and graphics chip name. It
  uses them on the phone only and never stores or sends them.

Uninstalling the game, or clearing its data in Android settings, deletes all of this.

## 3. Ads (Google AdMob)

The game shows ads through **Google AdMob**. Rewarded ads only play when you tap an ad button for a
bonus. Short interstitial ads may appear between levels, never during play, and can always be
closed. There are no ads in the middle of a level.

**For younger players**, every ad request is marked as directed at children
(`tag_for_child_directed_treatment`) and as under the age of consent. With these settings:

- the ads are **not personalised** (no interest-based ads, no remarketing)
- the maximum ad content rating is **G**
- Google's SDK does **not** send the Android advertising ID
- no consent form is shown, because no personalisation happens

**For older players**, AdMob may use the advertising ID, the IP address (to estimate a rough
location), and how you interact with the ads, to serve and measure ads and to prevent fraud. In
the EEA, the UK and Switzerland, Google's consent form asks you first, and you can choose
non-personalised ads. The maximum ad content rating is PG for everyone.

Google's own policy explains how Google uses this data:
<https://policies.google.com/technologies/partner-sites>. You can reset or delete your advertising
ID in Android **Settings → Privacy → Ads**.

## 4. Analytics (Google Analytics for Firebase), older players only

**For younger players, Firebase is never started.** No analytics data leaves the phone.

**For older players**, the game sends anonymous gameplay events to Google Analytics for Firebase so
we can see where the game is too hard or too easy. Examples: a level started or ended, stars won,
how many times per 10 seconds the hero was tapped, an ad button shown or watched, a building
upgraded. Firebase also records basic device information (model, Android version, language, rough
location from the IP address) and a random app-instance ID that resets when you reinstall the game.

We have turned **off** in the app:

- advertising-ID collection by Firebase
- Android ID (SSAID) collection by Firebase
- the use of analytics data for ads (ad storage, ad user data and ad personalisation are denied)

We do not use Firebase Crashlytics, Cloud Messaging, or any other Firebase product.

## 5. Sharing and selling

We do not sell personal data. We do not share it with anyone except Google, which runs AdMob and
Firebase as described above. We never combine it with data from other apps or sources.

## 6. Security and retention

Google's SDKs send data over encrypted connections (TLS). Firebase Analytics keeps event data for
the retention period set in our Google Analytics property (2 months). The local save and log stay
on your phone until you uninstall the game or clear its data.

## 7. Your choices and rights

- **Stop the analytics:** clear the game's data in Android settings. On the next launch, answer the
  age question again. A younger player's answer keeps Firebase off.
- **Ads:** reset or delete your advertising ID in Android settings; in the EEA/UK, change your ad
  consent from the consent form.
- **Questions, access or deletion:** email jakshat569@gmail.com. Because we never collect your name or
  email, tell us roughly when you played. We will delete what we can identify within 30 days.

If you are a parent and believe your child's data reached us, email us and we will delete it.

## 8. Changes

If this policy changes, we update this page and the "Last updated" date. Material changes will also
be noted in the app's store listing.
