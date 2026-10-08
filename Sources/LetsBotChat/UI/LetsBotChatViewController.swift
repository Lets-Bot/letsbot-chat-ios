import UIKit
import WebKit

/// The LetsBot chat screen (UIKit): the hosted LetsBot conversation in a locked-down `WKWebView`.
///
/// Usually you call ``LetsBot/present(from:animated:)``. Create it yourself to push it on a navigation stack or embed
/// it as a child view controller. It closes itself when the user taps the close button of the chat; set ``onClose``
/// to handle that yourself instead.
public final class LetsBotChatViewController: UIViewController {
    /// Called when the chat asks to close. When `nil`, the controller dismisses itself (or pops, when pushed).
    public var onClose: (() -> Void)?

    private var webView: WKWebView!
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var errorView: UIView?
    private var token: String?
    private var uiURL: URL?
    private var booted = false
    private var isOpen = false
    private var loadTask: Task<Void, Never>?
    private static let handlerName = "letsbot"

    public init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use LetsBotChatViewController()")
    }

    // MARK: Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        applyInterfaceStyle()

        let contentController = WKUserContentController()
        // Weak proxy: the content controller retains its handlers, so registering `self` would leak the screen.
        contentController.add(WeakScriptMessageHandler(self), name: Self.handlerName)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.dataDetectorTypes = []
        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: guide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        start()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        LetsBot.runtime.register(self)
        if !isOpen {
            isOpen = true
            LetsBot.runtime.delegate?.letsBotDidOpen()
        }
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Covered by something we presented (photo picker, camera) ≠ closed.
        guard presentedViewController == nil else { return }
        LetsBot.runtime.unregister(self)
        if isOpen {
            isOpen = false
            LetsBot.runtime.delegate?.letsBotDidClose()
            LetsBot.refreshUnreadCount()
        }
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle,
           LetsBot.runtime.theme == .auto {
            sendTheme()
        }
    }

    // MARK: Loading

    private func start() {
        guard let engine = LetsBot.runtime.engine else {
            showError(.notConfigured)
            return
        }
        hideError()
        spinner.startAnimating()
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            do {
                let token = try await engine.ensureSession()
                await MainActor.run { self?.load(token: token, api: engine.api) }
            } catch {
                let failure = error as? LetsBotError ?? .other(code: "unknown", status: nil)
                await MainActor.run { self?.showError(failure) }
            }
        }
    }

    private func load(token: String, api: APIClient) {
        guard isViewLoaded else { return }
        self.token = token
        booted = false
        let url = makeUIURL(api: api)
        uiURL = url
        var request = URLRequest(url: url)
        request.setValue(api.device.appId, forHTTPHeaderField: "X-LB-App-Id")
        request.setValue(DeviceInfo.platform, forHTTPHeaderField: "X-LB-Platform")
        request.setValue(DeviceInfo.sdkHeader, forHTTPHeaderField: "X-LB-SDK")
        webView.load(request)
    }

    private func makeUIURL(api: APIClient) -> URL {
        let locale = currentLocale()
        view.semanticContentAttribute = LocalStrings.isRightToLeft(locale) ? .forceRightToLeft : .forceLeftToRight
        return api.url(for: .ui, query: [
            URLQueryItem(name: "l", value: locale ?? "auto"),
            URLQueryItem(name: "theme", value: resolvedTheme()),
            URLQueryItem(name: "p", value: DeviceInfo.platform),
        ])
    }

    private func currentLocale() -> String? {
        LetsBot.runtime.locale
    }

    // MARK: Native → page

    private func boot() {
        guard let token, let configuration = LetsBot.runtime.configuration, let engine = LetsBot.runtime.engine else {
            return
        }
        let appId = engine.api.device.appId
        Task { [weak self] in
            let context = await engine.context
            await MainActor.run {
                guard let self else { return }
                let payload = BridgeScript.bootPayload(
                    token: token, appId: appId, context: context, color: configuration.colorHex
                )
                self.evaluate(BridgeScript.call("boot", payload))
                self.booted = true
                self.spinner.stopAnimating()
            }
        }
    }

    func pushContext(_ context: [String: String]) {
        guard booted else { return } // sent with boot otherwise
        evaluate(BridgeScript.call("setContext", context))
    }

    func applyTheme() {
        applyInterfaceStyle()
        sendTheme()
    }

    func reloadForLocaleChange() {
        guard let engine = LetsBot.runtime.engine, let token else { return }
        load(token: token, api: engine.api)
    }

    private func sendTheme() {
        guard booted else { return }
        evaluate(BridgeScript.call("setTheme", resolvedTheme()))
    }

    private func evaluate(_ script: String?) {
        guard let script, isViewLoaded else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func resolvedTheme() -> String {
        switch LetsBot.runtime.theme {
        case .light: return "light"
        case .dark: return "dark"
        case .auto: return traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
        }
    }

    private func applyInterfaceStyle() {
        switch LetsBot.runtime.theme {
        case .light: overrideUserInterfaceStyle = .light
        case .dark: overrideUserInterfaceStyle = .dark
        case .auto: overrideUserInterfaceStyle = .unspecified
        }
    }

    // MARK: Page → native

    fileprivate func handle(_ event: BridgeEvent) {
        switch event {
        case .ready:
            boot()
        case .tokenInvalid:
            renewSessionAndBoot()
        case .close:
            requestClose()
        case let .openURL(url):
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        case let .unread(count):
            LetsBot.runtime.setUnread(count)
        case let .message(text):
            LetsBot.runtime.delegate?.letsBotDidReceiveMessage(text)
        case let .error(code):
            LetsBot.notifyFailure(LetsBotError(code: code))
        }
    }

    private func renewSessionAndBoot() {
        guard let engine = LetsBot.runtime.engine else { return }
        let stale = token
        booted = false
        Task { [weak self] in
            do {
                let fresh = try await engine.renewSession(discarding: stale)
                await MainActor.run {
                    self?.token = fresh
                    self?.boot()
                }
            } catch {
                let failure = error as? LetsBotError ?? .other(code: "unknown", status: nil)
                await MainActor.run { self?.showError(failure) }
            }
        }
    }

    private func requestClose() {
        if let onClose {
            onClose()
        } else if let nav = navigationController, nav.viewControllers.first !== self {
            nav.popViewController(animated: true)
        } else if presentingViewController != nil {
            (navigationController ?? self).dismiss(animated: true)
        }
        if LetsBot.runtime.presented === self { LetsBot.runtime.presented = nil }
    }

    // MARK: Error state

    private func showError(_ error: LetsBotError) {
        spinner.stopAnimating()
        LetsBot.notifyFailure(error)
        guard isViewLoaded, errorView == nil else { return }
        let strings = LocalStrings.strings(for: currentLocale())

        let label = UILabel()
        label.text = strings.failed
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel

        let retry = UIButton(type: .system)
        retry.setTitle(strings.retry, for: .normal)
        retry.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retry.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let close = UIButton(type: .system)
        close.setTitle(strings.close, for: .normal)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, retry, close])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -16),
        ])
        webView.isHidden = true
        errorView = stack
    }

    private func hideError() {
        errorView?.removeFromSuperview()
        errorView = nil
        webView?.isHidden = false
    }

    @objc private func retryTapped() { start() }
    @objc private func closeTapped() { requestClose() }

    // MARK: Trust

    /// Messages are accepted only from the main frame of the LetsBot origin.
    private func isTrusted(_ message: WKScriptMessage) -> Bool {
        guard message.name == Self.handlerName, message.frameInfo.isMainFrame,
              let base = LetsBot.runtime.configuration?.baseURL,
              NavigationPolicy.isSameOrigin(webView.url, base)
        else { return false }
        return Self.originMatches(message.frameInfo.securityOrigin, base: base)
    }

    static func originMatches(_ origin: WKSecurityOrigin, base: URL) -> Bool {
        var components = URLComponents()
        components.scheme = origin.protocol
        components.host = origin.host
        if origin.port != 0 { components.port = origin.port }
        return NavigationPolicy.isSameOrigin(components.url, base)
    }
}

// MARK: - WKScriptMessageHandler

extension LetsBotChatViewController: WKScriptMessageHandler {
    public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard isTrusted(message), let event = BridgeEvent.parse(message.body) else { return }
        handle(event)
    }
}

// MARK: - WKNavigationDelegate

extension LetsBotChatViewController: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let uiURL else { return decisionHandler(.cancel) }
        switch NavigationPolicy.decide(navigationAction.request.url, uiURL: uiURL) {
        case .allow:
            decisionHandler(.allow)
        case let .openExternally(url):
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if isMainFrame || navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            decisionHandler(.cancel)
        case .cancel:
            decisionHandler(.cancel)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            decisionHandler(.cancel)
            switch http.statusCode {
            case 404: showError(.notFound)
            case 403: showError(.appNotRegistered)
            default: showError(.invalidResponse(status: http.statusCode))
            }
            return
        }
        decisionHandler(.allow)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        booted = false
        if let token, let engine = LetsBot.runtime.engine { load(token: token, api: engine.api) }
    }

    private func loadFailed(_ error: Error) {
        let nsError = error as NSError
        // Cancelled navigations (our own policy decisions) are not failures.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return } // frame load interrupted
        let code = nsError.domain == NSURLErrorDomain ? nsError.code : URLError.Code.unknown.rawValue
        showError(.network(urlErrorCode: code))
    }
}

// MARK: - WKUIDelegate

extension LetsBotChatViewController: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // target=_blank / window.open → system browser, never a second web view.
        if let url = navigationAction.request.url, NavigationPolicy.isWeb(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return nil
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let strings = LocalStrings.strings(for: currentLocale())
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: strings.ok, style: .default) { _ in completionHandler() })
        presentPanel(alert, orElse: completionHandler)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let strings = LocalStrings.strings(for: currentLocale())
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: strings.cancel, style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: strings.ok, style: .default) { _ in completionHandler(true) })
        presentPanel(alert) { completionHandler(false) }
    }

    @available(iOS 15.0, *)
    public func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        // Voice notes / camera: only for the LetsBot page; iOS still shows its own permission prompt.
        guard let base = LetsBot.runtime.configuration?.baseURL, frame.isMainFrame,
              Self.originMatches(origin, base: base)
        else { return decisionHandler(.deny) }
        decisionHandler(.prompt)
    }

    private func presentPanel(_ alert: UIAlertController, orElse fallback: () -> Void) {
        guard viewIfLoaded?.window != nil, presentedViewController == nil else { return fallback() }
        present(alert, animated: true)
    }
}
