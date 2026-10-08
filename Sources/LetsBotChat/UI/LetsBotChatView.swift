#if canImport(SwiftUI)
import SwiftUI

/// The LetsBot chat screen for SwiftUI.
///
/// ```swift
/// .sheet(isPresented: $showChat) { LetsBotChatView() }
/// ```
///
/// When the user taps the chat's close button the view calls `onClose`; when `onClose` is `nil` it dismisses the
/// enclosing sheet / navigation destination through the environment.
@available(iOS 14.0, *)
public struct LetsBotChatView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    private let onClose: (() -> Void)?

    /// - Parameter onClose: Called when the chat asks to close. `nil` = dismiss via `presentationMode`.
    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    public func makeUIViewController(context: Context) -> LetsBotChatViewController {
        let controller = LetsBotChatViewController()
        controller.onClose = closeAction
        return controller
    }

    public func updateUIViewController(_ controller: LetsBotChatViewController, context: Context) {
        controller.onClose = closeAction
    }

    private var closeAction: () -> Void {
        if let onClose { return onClose }
        let presentationMode = self.presentationMode
        return { presentationMode.wrappedValue.dismiss() }
    }
}
#endif
