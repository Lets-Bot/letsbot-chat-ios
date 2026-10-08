import WebKit

/// Forwards script messages to a weakly-held handler.
///
/// `WKUserContentController` retains its message handlers strongly; registering the view controller directly would
/// create a cycle (controller → web view → configuration → content controller → controller).
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
