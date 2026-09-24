# Appwin SDK for iOS

Support messenger, community feed, push notifications and in-app messages for
iOS apps, rendered natively in SwiftUI.

Requires iOS 16 and Swift 6. No third-party dependencies.

## Install

Xcode, `File > Add Package Dependencies`, then this repository's URL. Or in a
`Package.swift`:

```swift
.package(url: "https://github.com/appwin-dev/appwin-ios.git", from: "0.1.0")
```

One package, four products. Add only the ones you use; `AppwinCore` comes with
any of them.

| Product | What it gives you |
| --- | --- |
| `AppwinCore` | Device identity, session, networking. Required, and pulled in by the others. |
| `AppwinSupport` | Messenger, FAQ, conversations. |
| `AppwinCommunity` | Feed, comments, profiles. |
| `AppwinNotifications` | Push token, events, in-app messages. |

## Use

Configure once, at launch, whatever the number of products:

```swift
import AppwinCore
import AppwinSupport

AppwinCore.configure(appId: "your-app-id")
AppwinSupport.presentMessenger()
```

The App ID comes from your Appwin dashboard. Without a valid one the SDK stays
inert: it makes no network call.

## Identify your user

```swift
// At sign-in: links this device, and its anonymous history, to your user.
try await AppwinCore.identify(
  externalId: user.id,
  attributes: AppwinUserAttributes(email: user.email, name: user.name)
)

// Whenever a attribute changes.
try await AppwinCore.updateUser(AppwinUserAttributes(plan: "pro"))

// At sign-out: back to an anonymous session.
await AppwinCore.logout()
```

Call `identify` once, when your user signs in: the SDK stores the id and keeps
it across launches, so there is nothing to call again on the next start.
Omitted attribute fields are left as they are server-side. Identity lives in Core
only: Support, Community and Notifications pick up the current user by
themselves and expose no login function.

## Push

With `AppwinNotifications.start()`, the SDK installs its notification delegate
and routes Appwin pushes itself; notifications that are not Appwin's go on to
the delegate your app had set. Call `AppwinNotifications.ensurePushNotificationDelegate()`
in `application(_:didFinishLaunchingWithOptions:)` so the tap that launches the
app is not missed.

If your app owns its push stack (Firebase Messaging, your own delegate), start
with `AppwinNotifications.start(installsNotificationDelegate: false)` and
forward:

```swift
// didReceive response
if AppwinPush.handleTap(userInfo) { return }
// willPresent notification
if AppwinPush.handleForeground(userInfo) { return [] }
// didReceiveRemoteNotification
if await AppwinPush.handleMessage(userInfo) { return .newData }
```

Each returns `true` when the push was Appwin's. `handleTap` is safe at launch,
before any product is initialized.

## Support

Bugs and questions: the issues of this repository. Anything tied to your
account, your billing or your data goes through the support widget in your
Appwin dashboard.

## Licence

Proprietary, see [LICENSE](./LICENSE). This source is public for auditability
and for debugging on the studio's side, not for reuse.
