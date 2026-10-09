#if canImport(SwiftUI)
import SwiftUI

/// The LetsBot chat screen for SwiftUI.
///
/// ```swift
/// .fullScreenCover(isPresented: $showChat) { LetsBotChatView() }
/// ```
///
/// The chat is edge-to-edge: it ignores the safe area (the page paints its header colour under the status bar and
/// pads its composer above the home indicator and the keyboard itself).
///
/// When the user taps the chat's close button the view calls `onClose`; when `onClose` is `nil` it dismisses the
/// enclosing sheet / navigation destination through the environment.
@available(iOS 14.0, *)
public struct LetsBotChatView: View {
    private let onClose: (() -> Void)?

    /// - Parameter onClose: Called when the chat asks to close. `nil` = dismiss via `presentationMode`.
    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    public var body: some View {
        LetsBotChatRepresentable(onClose: onClose)
            .ignoresSafeArea()
    }
}

@available(iOS 14.0, *)
struct LetsBotChatRepresentable: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    let onClose: (() -> Void)?

    func makeUIViewController(context: Context) -> LetsBotChatViewController {
        let controller = LetsBotChatViewController()
        controller.onClose = closeAction
        return controller
    }

    func updateUIViewController(_ controller: LetsBotChatViewController, context: Context) {
        controller.onClose = closeAction
    }

    private var closeAction: () -> Void {
        if let onClose { return onClose }
        let presentationMode = self.presentationMode
        return { presentationMode.wrappedValue.dismiss() }
    }
}
#endif
