# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-08

### Added
- `LetsBot.configure(appKey:baseURL:locale:theme:color:)`.
- Verified identity: `LetsBot.identify(userId:identityToken:name:email:phone:)` (async and completion variants) and
  `LetsBot.logout()`. Identifying a different user on the same device logs the previous one out first.
- Hosted chat screen: `LetsBot.present(from:)`, `LetsBot.hide()`, `LetsBotChatViewController` (UIKit) and
  `LetsBotChatView` (SwiftUI, iOS 14+), in a locked-down `WKWebView` (only the LetsBot chat URL loads inside; other
  web links open in the system browser; the JavaScript bridge only accepts messages from the LetsBot origin).
- Push: `setPushToken(_ deviceToken: Data)` (APNs, sandbox auto-detected), `setPushToken(fcmToken:)`,
  `isLetsBotNotification(_:)`, `handleNotification(_:)` (cold start supported).
- Unread badge: `LetsBot.unreadCount`, `observeUnreadCount(_:)`, `unreadCountPublisher` (Combine) and
  `LetsBot.unreadCountDidChangeNotification`; refreshed on configure, on foreground and when the chat closes.
- `setContext(_:)`, `setLocale(_:)`, `setTheme(_:)`.
- `LetsBotDelegate` (open, close, message, unread, failure) and typed `LetsBotError` codes.
- Visitor token stored in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- Privacy manifest (`PrivacyInfo.xcprivacy`), Swift Package Manager and CocoaPods support, example app.

[0.1.0]: https://github.com/Lets-Bot/letsbot-chat-ios/releases/tag/0.1.0
