import LetsBotChat
import SwiftUI
import UIKit
import UserNotifications

/// Replace with your App Key from LetsBot panel → Channels → In-App Chat.
/// For local development you can also set the `LETSBOT_APP_KEY` / `LETSBOT_BASE_URL` scheme environment variables.
enum ExampleConfig {
    static var appKey: String {
        ProcessInfo.processInfo.environment["LETSBOT_APP_KEY"] ?? "YOUR_APP_KEY"
    }

    static var baseURL: URL {
        ProcessInfo.processInfo.environment["LETSBOT_BASE_URL"].flatMap(URL.init(string:))
            ?? URL(string: "https://letsbot.net")!
    }
}

@main
struct LetsBotChatExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // 1. Configure once, as early as possible.
        LetsBot.configure(
            appKey: ExampleConfig.appKey,
            baseURL: ExampleConfig.baseURL,
            locale: Locale.preferredLanguages.first.map { String($0.prefix(2)) },
            theme: .auto
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // 4. Push: hand the APNs token to LetsBot (use `setPushToken(fcmToken:)` if your app uses Firebase).
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        LetsBot.setPushToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error.localizedDescription)")
    }

    // Foreground notification: let the app show it; LetsBot ones refresh the badge.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if LetsBot.isLetsBotNotification(notification.request.content.userInfo) {
            LetsBot.refreshUnreadCount()
        }
        completionHandler([.banner, .sound])
    }

    // Tap (background or cold start): open the chat for LetsBot notifications, leave others to the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if LetsBot.isLetsBotNotification(userInfo) {
            LetsBot.handleNotification(userInfo)
        }
        completionHandler()
    }
}
