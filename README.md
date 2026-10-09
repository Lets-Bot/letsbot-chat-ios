# LetsBot Chat for iOS

[![CI](https://github.com/Lets-Bot/letsbot-chat-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/Lets-Bot/letsbot-chat-ios/actions/workflows/ci.yml)
![iOS 13+](https://img.shields.io/badge/iOS-13%2B-blue)
![SPM + CocoaPods](https://img.shields.io/badge/SPM%20%7C%20CocoaPods-supported-brightgreen)
![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)

Add a support chat to your iOS app. Conversations are answered by the same LetsBot AI assistant and human team that
already answer your business on WhatsApp and on your website, and everything lands in the LetsBot inbox (web panel +
LetsBot iOS/Android apps).

- Ready-made chat screen for **UIKit** and **SwiftUI** (text, buttons, cards, images/PDF, voice notes, RTL, dark mode,
  Arabic / English / Spanish / Portuguese).
- **Verified identity** so a logged-in user keeps one conversation across devices and reinstalls.
- **Push notifications** (APNs or Firebase Cloud Messaging) when the app is closed.
- **Unread badge**, screen **context**, delegate callbacks and typed errors.
- Zero third-party dependencies. Privacy manifest included. No tracking.

Docs: <https://letsbot.net/developers/in-app-chat>

---

## Requirements

- iOS 13.0+ (`LetsBotChatView` for SwiftUI: iOS 14.0+)
- Swift 5.9+ / Xcode 15+
- A LetsBot **App Key** (LetsBot panel → Channels → In-App Chat) and your app's bundle ID registered there
  (Platforms). The App Key is public and safe to ship in the app.

## Installation

Always pin an exact version.

### Swift Package Manager

Xcode → File → Add Package Dependencies… → `https://github.com/Lets-Bot/letsbot-chat-ios` → Dependency rule
**Exact Version** `0.2.0` → add product **LetsBotChat** to your app target.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/Lets-Bot/letsbot-chat-ios", exact: "0.2.0"),
// …
.target(name: "MyApp", dependencies: [.product(name: "LetsBotChat", package: "letsbot-chat-ios")]),
```

### CocoaPods

```ruby
pod 'LetsBotChat', '0.2.0'
```

### CocoaPods directly from GitHub

No CocoaPods trunk needed: install the tagged release straight from the repository.

```ruby
# Podfile
platform :ios, '13.0'
use_frameworks!

target 'MyApp' do
  pod 'LetsBotChat', :git => 'https://github.com/Lets-Bot/letsbot-chat-ios.git', :tag => '0.2.0'
end
```

Then run `pod install`. (Swift Package Manager above always installs straight from GitHub.)

### Info.plist

The chat lets users send photos, files and voice notes. Add these keys with user-facing text in every language your
app supports (iOS asks for permission only when the user actually uses the feature):

| Key | Why | Example text |
|---|---|---|
| `NSCameraUsageDescription` | Take a photo to send in the chat | "Take a photo to send to support." |
| `NSPhotoLibraryUsageDescription` | Pick a photo to send | "Choose photos to send to support." |
| `NSMicrophoneUsageDescription` | Record voice notes | "Record voice notes for support." |

Do **not** add App Tracking Transparency keys: the SDK does not track.

## Quick start

### 1. Configure once at startup

```swift
import LetsBotChat

// UIKit: application(_:didFinishLaunchingWithOptions:) · SwiftUI: your App's init()
LetsBot.configure(
    appKey: "YOUR_APP_KEY",
    locale: "ar",            // the app's current language (ar, en, es, pt; others fall back to English). nil = automatic
    theme: .auto,            // .auto follows light/dark mode, or .light / .dark
    color: nil               // optional brand colour; nil uses the colour set in the LetsBot panel
)
```

When the user switches language: `LetsBot.setLocale("en")`. Arabic is rendered right-to-left.

### 2. Open the chat

UIKit:

```swift
LetsBot.present(from: self)   // full screen; LetsBot.hide() closes it
```

or push / embed it yourself:

```swift
navigationController?.pushViewController(LetsBotChatViewController(), animated: true)
```

SwiftUI (iOS 14+):

```swift
.fullScreenCover(isPresented: $showChat) {
    LetsBotChatView()          // or LetsBotChatView(onClose: { showChat = false })
}
```

The chat screen is **edge-to-edge**: the chat header colour fills the area under the status bar / notch, the
composer stays above the home indicator and the keyboard, and the status-bar icons follow the header (white icons on
a dark header). UIKit restores your screen's own status-bar style when the chat closes.

- `LetsBotChatView` already ignores the safe area — don't add padding or a background around it.
- Pushing `LetsBotChatViewController` on a navigation stack keeps your navigation bar; the chat then starts below
  it. Hide the bar (`setNavigationBarHidden(true, animated:)`) for the full-screen look.
- Embedding it as a child view controller: return it from your container's `childForStatusBarStyle` so the status
  bar follows the chat header.
- SwiftUI decides the status-bar style itself (it follows the colour scheme), so with `LetsBotChatView` the icons
  may not match a dark header in light mode. Call `LetsBot.present(from:)` with your top view controller if you need
  the exact match.

Tell the team and the AI assistant what the user is looking at (optional, recommended):

```swift
LetsBot.setContext(["screen": "order_details", "order_id": "1234"])
```

### 3. Unread badge

```swift
// Closure (keep the token; the observer is removed when it is released or cancelled)
badgeObservation = LetsBot.observeUnreadCount { count in
    supportButton.badgeValue = count > 0 ? "\(count)" : nil
}

// Combine
LetsBot.unreadCountPublisher.sink { count in … }.store(in: &cancellables)

// NotificationCenter
NotificationCenter.default.addObserver(forName: LetsBot.unreadCountDidChangeNotification, object: nil, queue: .main) {
    let count = $0.userInfo?[LetsBot.unreadCountUserInfoKey] as? Int ?? 0
}

// Current value
LetsBot.unreadCount
```

The count refreshes on configure, when the app returns to the foreground, when a LetsBot notification arrives and
when the chat closes. It is `0` while the chat is open.

### 4. Delegate (optional)

```swift
final class SupportCoordinator: LetsBotDelegate {
    func letsBotDidOpen() {}
    func letsBotDidClose() {}
    func letsBotDidReceiveMessage(_ text: String) {}
    func letsBotUnreadCountDidChange(_ count: Int) {}
    func letsBotDidFail(_ error: LetsBotError) { print("LetsBot:", error.code) }
}
LetsBot.delegate = coordinator   // held weakly; every method is optional; called on the main thread
```

## Identity (logged-in users)

Goal: a logged-in user keeps one conversation across devices and reinstalls, and your team sees who they are.

1. **Your backend** returns a short-lived identity token for the *current* logged-in user: a JWT, **HS256**, signed
   with the app's **Identity Secret** (LetsBot panel → In-App Chat → Keys), claims `sub` (stable user id), `iat`,
   `exp` (24 h recommended, 7 days max), optional `name`, `email`, `phone`. Node: `createIdentityToken` from
   `@letsbot/sdk`. **Never put the Identity Secret in the app.**
2. **The app**, right after login and on every app start while logged in:

   ```swift
   do {
       try await LetsBot.identify(
           userId: user.id,
           identityToken: tokenFromYourBackend,
           name: user.name, email: user.email, phone: user.phone
       )
   } catch LetsBotError.identityExpired {
       // fetch a fresh token from your backend and call identify again
   }
   ```

   Completion-handler variant: `LetsBot.identify(userId:identityToken:…, completion: { result in … })`.
3. **On logout**, call `LetsBot.logout()` **before** clearing your own session, so the next person on this device does
   not see the previous user's conversation (`await LetsBot.logout()` or `LetsBot.logout { … }`).

Guests can chat anonymously; when they log in later, `identify` links them. If a different user is identified on the
same device without `logout()`, the SDK logs the previous user out first.

## Push notifications

LetsBot sends a push when the team or the AI assistant replies while the app is closed. Upload your push credentials
in LetsBot panel → Channels → In-App Chat → Notifications (APNs `.p8` key + Key ID + Team ID, or the Firebase
service-account JSON) and press «Send test notification».

Use your app's existing push setup — do not add a second provider.

**APNs (native):**

```swift
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    LetsBot.setPushToken(deviceToken)  // sandbox vs production is detected automatically
}
```

The APNs environment is read from `aps-environment` in the app's provisioning profile (development → sandbox),
falling back to sandbox for simulator / `DEBUG` builds and production otherwise (App Store / TestFlight). Override
with `LetsBot.setPushToken(deviceToken, sandbox: false)` if needed.

**Firebase Cloud Messaging:**

```swift
func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    if let fcmToken { LetsBot.setPushToken(fcmToken: fcmToken) }
}
```

**Handling notifications** (foreground, background tap and cold start):

```swift
func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    if LetsBot.isLetsBotNotification(userInfo) {
        LetsBot.handleNotification(userInfo)   // opens the chat
    } else {
        // your existing handling
    }
    completionHandler()
}
```

The push token is registered with LetsBot as soon as the user has a chat session (after opening the chat or
`identify`) and re-registered automatically after `logout()` or a language change.

## Security & privacy

- The visitor token is stored in the **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synced).
  The SDK never logs tokens, identity tokens, personal data or message text.
- The chat web view only loads the LetsBot chat URL. Any other http(s) link opens in the system browser; other schemes
  are blocked. The JavaScript bridge (`letsbot` message handler) only accepts messages from the LetsBot origin's main
  frame, and the handler is registered through a weak proxy (no retain cycle).
- Requests carry `X-LB-App-Id` (your bundle ID), `X-LB-Platform: ios` and `X-LB-SDK: ios/0.2.0`. No cookies.
- The package ships a privacy manifest (`PrivacyInfo.xcprivacy`): no tracking, no tracking domains, no required-reason
  APIs. Declared collected data (linked to the user, app functionality only): user ID, device ID (push token), name,
  e-mail, phone number, customer support messages, photos/videos, audio (voice notes), other user content. Reflect
  these in your App Store privacy answers.
- The «Powered by LetsBot» credit is part of the hosted chat screen and is required.

## Troubleshooting

`LetsBotError.code` gives the stable code below (also delivered to `letsBotDidFail(_:)`).

| Code | Meaning | Fix |
|---|---|---|
| `not_configured` | `configure(appKey:)` was not called or the key is empty | Call `LetsBot.configure` at app start |
| `not_found` | Unknown App Key, app disabled/deleted, or In-App Chat unavailable for the workspace | Copy the App Key again from the panel; check the app is enabled |
| `app_not_registered` | This bundle ID / platform isn't registered | Panel → In-App Chat → Platforms → add the bundle ID |
| `invalid_visitor` | Chat session expired | Handled automatically (a new session is created) |
| `identity_invalid` | Identity token bad signature / malformed / no secret configured | Sign with HS256 and the app's Identity Secret; `sub`, `iat`, `exp` required |
| `identity_expired` | Identity token `exp` passed | Fetch a new token from your backend and call `identify` again |
| `blocked` | The user or their IP was blocked by your team | Unblock from the LetsBot inbox |
| `invalid`, `too_long`, `invalid_contact`, `consent_required`, `file_too_big`, `file_type` | Validation | Shown to the user in the chat screen |
| `slow_down`, `busy` | Rate limit / workspace chat budget | Retry later (`retryAfter` seconds when provided) |
| `network_error` | No connection, DNS, TLS or timeout | The chat screen offers "Try again" |
| `invalid_response` | Unexpected server response | Check `baseURL`; contact support if it persists |

Other tips:

- **Chat shows "Couldn't load the chat"**: check connectivity and the errors above (the delegate receives the code).
- **No push in development**: APNs sandbox tokens only work with the sandbox APNs environment — make sure the
  development build is signed with a development profile, and that the `.p8` key is uploaded.
- **No push at all**: confirm `setPushToken` is called, credentials are uploaded, and the user opened the chat or was
  identified at least once (a session is needed to register the device).
- **Wrong language / direction**: pass the app's current language to `configure` and call `setLocale` on change.

## Example app

`Example/LetsBotChatExample.xcodeproj` — a SwiftUI app showing configure, identify, logout, the chat sheet, the unread
badge and push registration. Set your App Key in `ExampleConfig` (or the `LETSBOT_APP_KEY` / `LETSBOT_BASE_URL`
environment variables of the scheme) and run it.

## Development

```sh
# Build (UIKit/WebKit: build for the iOS Simulator, not with `swift build` on macOS)
xcodebuild -scheme LetsBotChat -destination 'generic/platform=iOS Simulator' build

# Unit tests (network is mocked with URLProtocol)
xcodebuild test -scheme LetsBotChat -destination 'platform=iOS Simulator,name=iPhone 16'

# Example app + hosted tests (real Keychain)
cd Example && xcodebuild test -project LetsBotChatExample.xcodeproj -scheme LetsBotChatExample \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Optional end-to-end check of the chat screen + JS bridge against a local mock of the API
python3 Scripts/mock_server.py 8765 &
cd Example && TEST_RUNNER_LETSBOT_E2E_BASE_URL=http://127.0.0.1:8765 xcodebuild test \
  -project LetsBotChatExample.xcodeproj -scheme LetsBotChatExample \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LetsBotChatExampleTests/ChatScreenE2ETests

pod lib lint LetsBotChat.podspec --allow-warnings
```

> Xcode 27 only builds iOS 15.0+ deployment targets. `pod lib lint` therefore fails there with
> "deployment target … 13.0 … supported range is 15.0" — lint a temporary copy with `s.ios.deployment_target = '15.0'`
> to validate the sources, or lint with Xcode 16 (as CI does). SPM consumers are unaffected.

## Support

- Docs: <https://letsbot.net/developers/in-app-chat>
- Issues: <https://github.com/Lets-Bot/letsbot-chat-ios/issues>
- Email: support@letsbot.net

## License

MIT © 2026 LetsBot. See [LICENSE](LICENSE).
