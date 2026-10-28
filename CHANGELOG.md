# Changelog - Appwin SDK for iOS

Versions follow [semantic versioning](https://semver.org).

Each Appwin artefact versions independently: a fix here does not move the Android,
Flutter or React Native SDK. All four numbers live in one place, `version.json`
in the monorepo, and the release script derives every manifest and every
cross-artefact pin from it.

## 1.0.1

- Realtime: no more crash in `RealtimeSocket.sendPing` when the connection drops or reconnects while a ping waits for its answer (switching between 4G and Wi-Fi, going to the background). URLSession could answer the same ping twice, and the second answer stopped the app.

## 1.0.0

**Stable release.** The public API is stable from now on and follows semantic versioning: no breaking change before 2.0.0. The symbols deprecated during 0.x keep compiling and working through 1.x.

- Builds with Xcode 26.0 (Swift 6.2): the image viewers of Support and Community no longer fail with `ambiguous use of operator '/'` (the drag fade mixed `CGFloat` and `Double`; Xcode 16 and recent Xcode 26 releases picked one silently).
- Community: a post's detail refreshes in place, without going back to the feed, and the bell updates after a moderation action.

## 0.16.0

**`AppwinCore.track` and consent per purpose.** One call for every product.

- `AppwinCore.track("purchase", props: ["value": 9.99])` is public and is the one way to describe what happened: it reaches Analytics, journeys and the ad networks, according to consent. `AppwinAnalytics.track` and `AppwinNotifications.trackEvent` still work, deprecated, and go through the same stream.
- `AppwinCore.setConsent(.denied, for: .marketing)`: three purposes, `analytics`, `marketing` and `advertising`, granted by default. Without a purpose, `setConsent(state)` sets the three. `.unknown` keeps events on the device until the answer. If no purpose is granted, nothing is sent and the local queue is emptied. Every event is sent once, with the purposes granted at that moment.
- `ConsentState` (`granted`, `denied`, `unknown`) replaces `AnalyticsConsent`, which stays as a deprecated alias. A consent refused in 0.15.0 stays refused on the three purposes.
- `advertising` is a purpose of the event stream only. It is separate from `AppwinAttribution.setAdvertisingConsent`, which stays the only switch for the IDFA / GAID and the ad networks (unchanged).
- A refusal through `AppwinCore.setConsent` also purges the recorded session replay.
- Automatic events, sent by Core without the studio: `app_install`, `app_update`, `app_open`, `app_background`, `session_start` / `session_end`, `screen_view`, `install_referrer` (Android, once), `push_opt_in` and `push_opened`. `app_open`, `app_background`, `push_opt_in` and `push_opened` are reserved names: `track` ignores them with a log.
- `configure` starts the event pipeline and the lifecycle whichever products are installed: an app with only Notifications or Support now gets sessions and automatic events. There is one lifecycle observer, in Core.
- An app that had none of the old install flags (Notifications or Support only, upgraded) and whose device was already known emits `app_update`, not `app_install`. An app that already had Analytics or Attribution emits no `app_install` again.
- `push_opt_in` is now sent once per install, on iOS and Android. A device that was already opted in before the upgrade does not re-send it: journeys on `push_opt_in` won't fire for existing users. A grant through the studio's own permission prompt on an already-known device is not counted.
- `AppwinNotifications.start()` keeps its role (ask for push permission, install the delegate, show in-app messages) but no longer observes the lifecycle nor sends `session_start`. `trackEvent(.appOpen)`, `.appBackground`, `.sessionStart` and `.pushOptIn` now send nothing. `syncOnAppOpen` is deprecated and only fetches.
- No more request to `/api/sdk/notifications/v1/events` from this SDK: events go to `/api/sdk/v1/events`.

**Two things to tell your studios**

- A journey triggered on `session_start` now starts when the customer comes back after 30 minutes away, not on every process launch. Notifications no longer sends its own `session_start` at `start()`: sessions are real ones (30 minutes of inactivity or 24 hours of age), owned by Core.
- A custom `eventName` that does not match `^[a-z][a-z0-9_]{0,63}$` (for example `OnboardingFinished` or `level-complete`) is no longer sent by `trackEvent`: it is dropped, with a log in debug builds only. Rename the event, and the trigger of the journey that listens to it, to a `snake_case` name. Properties are now limited to 20 keys, and string values are cut at 256 characters.
- Calling both `AppwinCore.track("purchase")` and the deprecated `AppwinNotifications.trackEvent(.purchase)` counts the purchase twice: remove the old call. The SDK does not de-duplicate, each call is one event.
