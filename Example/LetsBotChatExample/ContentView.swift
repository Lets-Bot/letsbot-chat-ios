import Combine
import LetsBotChat
import SwiftUI
import UserNotifications

/// Keeps the unread badge in sync through the Combine publisher.
final class ChatBadge: ObservableObject {
    @Published private(set) var unread = 0
    private var cancellable: AnyCancellable?

    init() {
        cancellable = LetsBot.unreadCountPublisher.sink { [weak self] in self?.unread = $0 }
    }
}

struct ContentView: View {
    @StateObject private var badge = ChatBadge()
    @State private var showChat = false
    @State private var userId = ""
    @State private var identityToken = ""
    @State private var status = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Support")) {
                    Button {
                        // 3. Context tells the team / AI what the user is looking at.
                        LetsBot.setContext(["screen": "help"])
                        showChat = true
                    } label: {
                        HStack {
                            Label("Chat with us", systemImage: "bubble.left.and.bubble.right")
                            Spacer()
                            if badge.unread > 0 {
                                Text("\(badge.unread)")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.red))
                                    .accessibilityLabel("\(badge.unread) unread")
                            }
                        }
                    }
                }

                Section(header: Text("Identity (logged-in users)"),
                        footer: Text("Get the identity token from YOUR backend (JWT HS256 signed with the Identity Secret). Never put the secret in the app.")) {
                    TextField("User ID", text: $userId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Identity token (JWT)", text: $identityToken)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("Identify") { identify() }
                        .disabled(userId.isEmpty || identityToken.isEmpty)
                    Button("Log out", role: .destructive) {
                        Task {
                            await LetsBot.logout()
                            status = "Logged out"
                        }
                    }
                }

                Section(header: Text("Push notifications")) {
                    Button("Enable notifications") { requestPush() }
                }

                if !status.isEmpty {
                    Section { Text(status).font(.footnote).foregroundColor(.secondary) }
                }
            }
            .navigationTitle("LetsBot Example")
        }
        .sheet(isPresented: $showChat) {
            LetsBotChatView()
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // 2. Identify after login and on every start while logged in.
    private func identify() {
        Task {
            do {
                try await LetsBot.identify(userId: userId, identityToken: identityToken)
                status = "Identified"
            } catch let error as LetsBotError {
                status = "identify failed: \(error.code)"
            } catch {
                status = "identify failed"
            }
        }
    }

    private func requestPush() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                status = granted ? "Notifications allowed" : "Notifications denied"
                if granted { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }
}
