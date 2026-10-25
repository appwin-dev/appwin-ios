# Appwin SDK for iOS

Support, community, push notifications, analytics and attribution for iOS apps,
rendered natively in SwiftUI.

Requires iOS 16 and Swift 6 (Xcode 16 or later).

Full guide, per-product APIs and dashboard setup:
https://appwin.io/docs/sdk/installation

## Install

In Xcode, `File > Add Package Dependencies`, then this repository's URL. Or in a
`Package.swift`:

```swift
.package(url: "https://github.com/appwin-dev/appwin-ios.git", from: "1.0.0")
```

then, in your target:

```swift
.target(name: "MyApp", dependencies: [
  .product(name: "AppwinCore", package: "appwin-ios"),
  .product(name: "AppwinSupport", package: "appwin-ios"),
])
```

One package, several products. Add only the ones you use; `AppwinCore` is pulled
in by any of them.

With CocoaPods, one pod per product (`AppwinCore`, `AppwinSupport`,
`AppwinCommunity`, `AppwinNotifications`, `AppwinAnalytics`,
`AppwinAttribution`), each pulling in `AppwinCore` at the same version:

```ruby
pod 'AppwinSupport', '~> 1.0'
```

`AppwinTikTokEvents` is distributed through Swift Package Manager only.

## Products

| Product | Purpose |
| --- | --- |
| [`AppwinCore`](https://appwin.io/docs/products/appwin-core) | Device identity, session, networking. Required, and pulled in by the others. |
| [`AppwinSupport`](https://appwin.io/docs/products/support) | Messenger, FAQ, conversations. |
| [`AppwinCommunity`](https://appwin.io/docs/products/community) | Feed, comments, profiles. |
| [`AppwinNotifications`](https://appwin.io/docs/products/notifications) | Push token, events, in-app messages. |
| [`AppwinAnalytics`](https://appwin.io/docs/products/analytics) | Behavioural events, funnels and experiments, crash reporting, session replay. |
| [`AppwinAttribution`](https://appwin.io/docs/products/attribution) | Acquisition signals: SKAdNetwork / AdAttributionKit conversion values and IDFA. |
| [`AppwinTikTokEvents`](https://appwin.io/docs/products/attribution) | Optional TikTok App Events adapter for Attribution. The only product with a third-party dependency (TikTok Business SDK). |

Attribution can relay conversions to ad networks through an optional adapter:
add the `AppwinTikTokEvents` product to your app, nothing else to call. See the
[Attribution guide](https://appwin.io/docs/products/attribution).

## Quickstart

Configure once at launch, then present or initialise the products you use:

```swift
import AppwinCore
import AppwinSupport

AppwinCore.configure(projectAppId: "your-app-id")
AppwinSupport.presentMessenger()
```

`presentMessenger()` initialises Support on demand. To gate your own entry
points (hide a tab or a button), call the product's `initialize()` and check
`isReady` on its result:

```swift
if await AppwinCommunity.initialize().isReady { showsCommunityTab = true }
```

The App ID comes from your Appwin dashboard; without a valid one the SDK stays
inert and makes no network call. Identity lives in Core
(`AppwinCore.identify(externalId:)`, `AppwinCore.updateUser(_:)`,
`AppwinCore.logout()`); the products pick up the current user by themselves.
Your own events go through `AppwinCore.track(_:props:)`. See the
[Quickstart](https://appwin.io/docs/sdk/installation).

## Push

```swift
if await AppwinNotifications.initialize().isReady {
  await AppwinNotifications.start()
}
```

With `AppwinNotifications.start()`, the SDK asks for the push permission,
installs its notification delegate and routes Appwin pushes itself;
notifications that are not Appwin's go on to the delegate your app had set. Call
`AppwinNotifications.ensurePushNotificationDelegate()` in
`application(_:didFinishLaunchingWithOptions:)` so the tap that launches the app
is not missed.

iOS hands the APNs token to your app delegate only, so forward it (a SwiftUI app
needs a `@UIApplicationDelegateAdaptor` for this):

```swift
func application(
  _ application: UIApplication,
  didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
  Task {
    await AppwinNotifications.application(
      application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}
```

An app that only uses Support or Community registers its token with
`AppwinCore.registerPushToken(_:platform:pushOptIn:)` instead.

If your app owns its push stack (Firebase Messaging, your own delegate), start
with `AppwinNotifications.start(installsNotificationDelegate: false)` and forward:

```swift
// didReceive response
if AppwinPush.handleTap(userInfo) { return }
// willPresent notification
if AppwinPush.handleForeground(userInfo) { return [] }
// didReceiveRemoteNotification
if await AppwinPush.handleMessage(userInfo) { return .newData }
```

Each returns `true` when the push was Appwin's. With Firebase Messaging, which
hands the notification text apart from `data`, pass it to
`AppwinPush.handleForeground(_:title:body:)`.

Campaign images need a Notification Service Extension: add
[`NotificationServiceExtension/NotificationService.swift`](./NotificationServiceExtension/NotificationService.swift)
to an extension target of your app. Full setup:
https://appwin.io/docs/products/notifications

## Analytics and crashes

`AppwinAnalytics.initialize()` starts the events and crash reporting together.
Uncaught Objective-C exceptions and fatal signals (Swift traps such as
`fatalError` or a force unwrap, `EXC_BAD_ACCESS`, `abort()`) are written to disk
and uploaded on the next launch, with the app version and build, OS, device
model, current screen and the last 20 screens and events (names only). Crash
handlers installed before Appwin (Crashlytics, Sentry) keep receiving every
crash. Same consent as the events.

```swift
_ = await AppwinAnalytics.initialize(
  crashReporting: true,          // false: no handler installed, nothing captured
  inAppModules: ["MyAppKit"],    // your own dynamic frameworks, if any
  sessionReplay: true            // false: this app's screen is never recorded
)

do { try await sync() } catch { AppwinAnalytics.recordError(error) }
```

Only frames from your code (the app executable and `inAppModules`) group crashes
into issues. A debugger attached to the app catches crashes before the SDK
does: test without it. Stacks of release builds stay as addresses until dSYM
symbolication ships.

Session replay, when switched on in the dashboard, records a share of the
sessions as video under the same consent. Text inputs are always masked on the
device; mark any other view with `.appwinMask()` (or `.appwinUnmask()`), on a
SwiftUI view or a `UIView`.

## Support

Bugs and questions: the issues of this repository. Anything tied to your
account, your billing or your data goes through the support widget in your
Appwin dashboard.

## Licence

Proprietary, see [LICENSE](./LICENSE). This source is public for auditability
and for debugging on the studio's side, not for reuse.
