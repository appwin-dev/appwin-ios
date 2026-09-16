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

## Support

Bugs and questions: the issues of this repository. Anything tied to your
account, your billing or your data goes through the support widget in your
Appwin dashboard.

## Licence

Proprietary, see [LICENSE](./LICENSE). This source is public for auditability
and for debugging on the studio's side, not for reuse.
