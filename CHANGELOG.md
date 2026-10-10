# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.2.1] - 2026-10-10

### Changed
- Minimum iOS version is now 15.0 (current Xcode no longer builds for iOS 13 and 14).

## [0.2.0] - 2026-10-09

### Changed
- Edge-to-edge chat screen: the `WKWebView` now fills the whole view (no safe-area constraints,
  `contentInsetAdjustmentBehavior = .never`). The chat page paints its header colour under the status bar / notch and
  pads its composer above the home indicator itself.
- `LetsBot.present(from:)` presents the chat full screen (was a page sheet). `LetsBotChatView` (SwiftUI) ignores the
  safe area; the example uses `.fullScreenCover`.
- `X-LB-SDK` is now `ios/0.2.0`.

### Added
- Handles the page's `chrome` event: the status-bar style follows the chat header (`preferredStatusBarStyle`, light
  icons on a dark header) and the view / WebView background follows the page background, so no white flashes show on
  open, close, rotation or keyboard animations. UIKit restores the presenting screen's status-bar style on close.
- The last chrome colours are cached per app and theme (in `UserDefaults`, colours only) and used before the page
  paints next time; without them a neutral colour (your brand colour for the header, if set) is used.
- Safe-area insets are passed to the page in `boot({insets})` and through `LetsBotHost.setInsets` when they change.

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
- Privacy manifest (`PrivacyInfo.xcprivacy`), Swift Package Manager and CocoaPods support (including CocoaPods
  straight from the GitHub tag: `pod 'LetsBotChat', :git => 'https://github.com/Lets-Bot/letsbot-chat-ios.git', :tag => '0.1.0'`),
  example app.

[0.2.0]: https://github.com/Lets-Bot/letsbot-chat-ios/releases/tag/0.2.0
[0.1.0]: https://github.com/Lets-Bot/letsbot-chat-ios/releases/tag/0.1.0
