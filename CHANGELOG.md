# Changelog - Appwin SDK for iOS

Versions follow [semantic versioning](https://semver.org).

Each Appwin artefact versions independently: a fix here does not move the iOS,
Android or React Native SDK. All four numbers live in one place, `version.json`
in the monorepo, and the release script derives every manifest and every
cross-artefact pin from it.

The four products (`AppwinCore`, `AppwinSupport`, `AppwinCommunity`,
`AppwinNotifications`) ship from a single package, so they share **this**
version between them.

## 0.6.2

**The SDK now reports its version.** `/sdk/v1/auth/init` carries the real SDK
version (the constant is stamped by the release script; it used to say
`0.1.0-dev` forever, and iOS did not send it at all). The dashboard's SDK
status bar can finally show what each app actually runs.

## 0.6.1

**Availability verdict cached for an hour in release builds.** Every end-user
launch used to hit `/sdk/v1/availability`; a verdict younger than one hour now
spares the request entirely. Debug builds still revalidate on every launch, so
the toggle-relaunch-ready integration loop stays instant.

## 0.6.0

**New product: `AppwinAttribution`.** Acquisition signals as a product in
its own right - SKAdNetwork / AdAttributionKit conversion values, the
advertising identity (IDFA) under an opt-in consent, and the optional
ad-network adapters - with its own `initialize()` gated by the dashboard,
like every other product. The only thing it shares with Analytics is
Core's event pipeline, which neither product owns: whichever
`initialize()` runs first starts it.

**Breaking, if you called them on Core:** `setAdvertisingConsent` and
`requestTrackingAuthorization` moved from `AppwinCore` to the
`AppwinAttribution` façade. Both are safe to call in any order around
`initialize()` - consent is buffered, and the ATT answer is persisted by
iOS.

**Fresher matching signals.** The advertising-identity report re-sends at
most once every 24 hours even when the identifier has not changed: the
request itself carries matching signals the server captures, and those go
stale even when the IDFA does not.

`AppwinAttribution` also ships as a pod, wired like the other products.

## 0.5.1

**The pods build again.** 0.5.0 could not compile through CocoaPods at all:
`AppwinCore+Analytics.swift` declares its entry points `package`, and that
access level needs a package name the compiler is given by `-package-name`.
SwiftPM passes one on its own; CocoaPods passes nothing, so every pods-based
consumer failed on six `requires a package name` errors. The podspecs now
set it explicitly, to the same name SwiftPM uses.

SPM consumers were never affected, and there is no API change: 0.5.1 is 0.5.0
plus a build flag.

**`AppwinAnalytics` ships as a pod.** It was an SPM product only since 0.5.0,
so pods consumers could not reach analytics at all. It is also why Core's
analytics entry points are `package` rather than internal, and that access
level is what the flag above restores.

**0.3.0, 0.4.0 and 0.5.0 were never pushed to CocoaPods trunk** - it still
served 0.2.0. `pod install` therefore resolved a native SDK three minors behind
whatever Flutter served. The release script now prints the `pod trunk push`
steps alongside the Maven Central and pub.dev ones, so the trunk cannot fall
behind the git tag again.

## 0.5.0

**New product: `AppwinAnalytics`.** `track`, `screen`, `flush` and
`setConsent`, behind the same `initialize()` gate as the other products.
`configure` alone collects nothing: an app that never initialises Analytics
pays for none of it. Events are validated, batched and persisted to a rotating
JSONL store, so a flush that fails offline is retried at the next launch rather
than dropped, and the store drops its oldest entries rather than growing
without bound. Sessions carry a UUIDv7 identifier, which sorts by time without
a second timestamp field.

Consent is **opt-out** by default, the model PostHog and Firebase use: the
pipeline runs until the host app calls `setConsent(.denied)`. A studio bound to
opt-in calls it before `initialize()`.

**SKAdNetwork and AdAttributionKit conversion values** (ADR-0038). Appwin is
the single manager of the conversion value - no other network SDK may call the
update APIs, and two managers overwrite each other. It registers the install,
then raises the value when an event named by the server schema is tracked; the
value only ever goes up, so it encodes the best milestone the install reached.
The schema is cached on device, and a built-in default covers the first launch,
which is the one SKAdNetwork cares most about. No consent gate: this is an
OS-level aggregate on Apple's own privacy rail, and nothing leaves the device.

**In-app banners.** `AppwinCore` hosts a shared banner surface, and Support
raises one when an agent replies while the customer sits on another screen.
That case was silent until now: the server skips the push when the customer
holds a live realtime connection, assuming something in-app takes over, and
nothing did. Tapping the banner opens the thread through the new
`AppwinSupport.presentConversation(id:)`.

`AppwinNotifications.handleRemoteNotification(_:)` and
`ensurePushNotificationDelegate()` are now public. The Flutter and React Native
bridges need to register the notification delegate around Firebase Messaging,
which claims it for itself; without a public seam they could not.

A silent push now acts as a doorbell, so an in-app message reaches a session
already in progress instead of waiting for the next launch.

**Fewer sockets.** Notifications no longer holds a realtime connection: it
fetches on open and refetches after a delay. Support opens its socket lazily,
only once a conversation exists. Both were paid for on every launch by every
app, for an event most sessions never see.

The Community feed and its post cards follow the Figma designs: spacing,
elevation and palette.

## 0.4.0

Le messenger est présenté en **page sheet** et non plus en plein écran : même
rendu que le bottom sheet Android et que les maquettes, panneau arrondi
au-dessus de l'app hôte.

**Correctif.** Les bulles sortantes du fil s'affichaient en quasi-noir et
ignoraient la couleur configurée par le studio. Elles suivent maintenant
l'accent distant, les entrantes passent en blanc, et le fil adopte le fond du
sheet plutôt qu'une barre de navigation blanche.

Métriques d'accueil recalées sur les maquettes : rayon du sheet, avatar et
titre d'en-tête, tailles de texte et d'icône, lignes en padding plutôt qu'en
hauteur fixe.

## 0.3.0

**Breaking.** `registerPushToken` moved from Support to the foundation: it is
now `AppwinCore.registerPushToken(...)`. The token is shared by Support, Community and Notifications, so it
belongs to the socle rather than to one product; it still posts to the Support
route, so registering it needs no Notifications entitlement. A product whose
`initialize()` runs without a registered token logs a warning - recommended for
Support and Community, required for Notifications - rather than refusing to
start.

`initialize()` answered `.unknown` on a first launch of an app that was
online. `configure` returns before the bearer exists - deliberately, so an
offline app starts as fast as any other - and `/sdk/v1/availability` is
bearer-only. Called straight after `configure`, which is what the integration
sequence tells you to do, the request went out without a token, took a 401,
found no cached verdict, and reported no verdict at all. Products stayed
closed until the next launch.

`availability()` now awaits the session first. It is idempotent and shared
between concurrent callers, so the three products initialising at startup still
cost one round trip.

The `.unknown` message no longer says "offline". A 404 from an API older than
the SDK lands in the same place, and telling a developer their online app is
offline sends them looking in the wrong direction; it now names both causes.

## 0.2.0

**Breaking.** Each product now has an `initialize()` that asks the server
whether it may open, and it must be called before presenting that product.
`AppwinCore.configure(projectAppId:)` is unchanged and still the first call.

`AppwinSupport.initialize(appId:)` and `AppwinCommunity.initialize(appId:)`,
which only delegated to `configure`, are gone. Call `AppwinCore.configure`
directly, then the product's `initialize()`.

`initialize()` returns an `AppwinInitResult` rather than throwing: not being
entitled is a normal outcome of a normal launch. Gate your own UI on it, since
the SDK does not own your navigation. Presentation entry points refuse rather
than opening on an empty screen, and log loudly in debug, quietly in release.

The verdict is cached on disk and used as an offline fallback.

## 0.1.1

The four podspecs are publishable to the CocoaPods registry: their source is
the tagged repository instead of a local path, and each product pins
`AppwinCore` at its own version rather than accepting any. No code change.

SPM is unaffected: this version and 0.1.0 carry the same sources.

## 0.1.0

First release.
