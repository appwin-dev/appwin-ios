# Appwin SDK for iOS

Support, community, push notifications, analytics and attribution for iOS apps,
rendered natively in SwiftUI.

Requires iOS 16 and Swift 6.

Full guide, per-product APIs and dashboard setup:
https://appwin.io/docs/sdk/installation

## Install

In Xcode, `File > Add Package Dependencies`, then this repository's URL. Or in a
`Package.swift`:

```swift
.package(url: "https://github.com/appwin-dev/appwin-ios.git", from: "0.9.0")
```

One package, several products. Add only the ones you use; `AppwinCore` is pulled
in by any of them.

## Products

| Product | Purpose |
| --- | --- |
| [`AppwinCore`](https://appwin.io/docs/products/appwin-core) | Device identity, session, networking. Required, and pulled in by the others. |
| [`AppwinSupport`](https://appwin.io/docs/products/support) | Messenger, FAQ, conversations. |
| [`AppwinCommunity`](https://appwin.io/docs/products/community) | Feed, comments, profiles. |
| [`AppwinNotifications`](https://appwin.io/docs/products/notifications) | Push token, events, in-app messages. |
| [`AppwinAnalytics`](https://appwin.io/docs/products/analytics) | Behavioural events, funnels and experiments. |
| [`AppwinAttribution`](https://appwin.io/docs/products/attribution) | Acquisition signals: SKAdNetwork / AdAttributionKit conversion values and IDFA. |

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

The App ID comes from your Appwin dashboard; without a valid one the SDK stays
inert and makes no network call. Identity lives in Core (`AppwinCore.identify`);
the products pick up the current user by themselves. See the
[Quickstart](https://appwin.io/docs/sdk/installation).

## Push

With `AppwinNotifications.start()`, the SDK installs its notification delegate
and routes Appwin pushes itself; notifications that are not Appwin's go on to the
delegate your app had set. Call `AppwinNotifications.ensurePushNotificationDelegate()`
in `application(_:didFinishLaunchingWithOptions:)` so the tap that launches the
app is not missed.

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

Each returns `true` when the push was Appwin's. Full setup:
https://appwin.io/docs/products/notifications

## Support

Bugs and questions: the issues of this repository. Anything tied to your
account, your billing or your data goes through the support widget in your
Appwin dashboard.

## Licence

Proprietary, see [LICENSE](./LICENSE). This source is public for auditability
and for debugging on the studio's side, not for reuse.
