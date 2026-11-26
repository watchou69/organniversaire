import SwiftUI
import WebKit
import ContactsUI
import UIKit

/// Vue web de l'espace organisateur + pont JavaScript « OAApp » vers les fonctions de l'iPhone
/// (contacts, partage, notifications, vibration).
struct WebView: UIViewRepresentable {
    @ObservedObject var model: WebModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Évite que le contrôleur de scripts retienne le modèle (fuite mémoire).
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

final class WebModel: NSObject, ObservableObject {
    @Published var loading = false
    @Published var progress: Double = 0
    @Published var offline = false
    @Published var firstLoadDone = false

    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []
    private var contactsRequestId: Int?

    /// Pont injecté dans chaque page (avant ses propres scripts).
    static let bridgeJS = """
    (function () {
      if (window.OAApp) return;
      var callbacks = {}, seq = 0;
      function call(cmd, data) {
        return new Promise(function (resolve, reject) {
          var id = ++seq;
          callbacks[id] = { resolve: resolve, reject: reject };
          window.webkit.messageHandlers.oaApp.postMessage({ id: id, cmd: cmd, data: data || {} });
        });
      }
      window.OAApp = {
        isApp: true,
        pickContacts: function () { return call('contacts'); },
        share: function (d) { return call('share', d || {}); },
        requestPush: function () { return call('push'); },
        haptic: function () { return call('haptic'); },
        _done: function (id, ok, data) {
          var c = callbacks[id]; if (!c) return; delete callbacks[id];
          if (ok) c.resolve(data); else c.reject(data);
        },
        _registerPush: function (token, env) {
          try { if (sessionStorage.getItem('oa_push') === token) return; } catch (e) {}
          var f = new FormData();
          f.append('action', 'push_register'); f.append('token', token); f.append('env', env);
          fetch('/organizer/app_api.php', { method: 'POST', body: f, credentials: 'same-origin' })
            .then(function (r) { if (r.ok) { try { sessionStorage.setItem('oa_push', token); } catch (e) {} } })
            .catch(function () {});
        }
      };
      if (!navigator.share) { navigator.share = function (d) { return window.OAApp.share(d); }; }
    })();
    """

    static let viewportJS = """
    (function () {
      var m = document.querySelector('meta[name=viewport]');
      if (!m) { m = document.createElement('meta'); m.name = 'viewport'; document.head.appendChild(m); }
      m.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
    })();
    """

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()               // cookies conservés : on reste connecté
        config.allowsInlineMediaPlayback = true
        config.applicationNameForUserAgent = "Mobile/15E148 " + AppConfig.userAgentSuffix
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: WebModel.bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Plein écran : le site connaît la hauteur de la barre « home » (env(safe-area-inset-bottom)) et ne zoome pas
        controller.addUserScript(WKUserScript(source: WebModel.viewportJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        controller.add(WeakScriptHandler(self), name: "oaApp")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never   // les marges du bas sont gérées par le site
        webView.isOpaque = false
        webView.backgroundColor = UIColor(named: "LaunchBackground")
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.progress = wv.estimatedProgress }
        })
        observations.append(webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.loading = wv.isLoading }
        })
        load(AppConfig.startURL)
    }

    func load(_ url: URL) {
        offline = false
        webView.load(URLRequest(url: url))
    }

    func reload() {
        offline = false
        if webView.url != nil { webView.reload() } else { load(AppConfig.startURL) }
    }

    @objc private func pullToRefresh(_ sender: UIRefreshControl) {
        webView.reload()
    }

    private var isOrganizerPage: Bool {
        guard let url = webView.url, url.host?.hasSuffix(AppConfig.host) == true else { return false }
        let p = url.path
        return p.contains("/organizer/") && !["login.php", "register.php", "forgot_password.php", "reset_password.php"].contains(url.lastPathComponent)
    }

    /// Transmet le jeton de notification au site (avec la session de l'utilisateur).
    func sendPushTokenIfPossible() {
        guard let token = AppState.shared.pushToken, isOrganizerPage else { return }
        webView.evaluateJavaScript("window.OAApp && OAApp._registerPush('\(token)', '\(AppConfig.pushEnv)')", completionHandler: nil)
    }

    private func reply(_ id: Int, ok: Bool, json: String) {
        webView.evaluateJavaScript("window.OAApp && OAApp._done(\(id), \(ok ? "true" : "false"), \(json))", completionHandler: nil)
    }

    private func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private func openExternally(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

// MARK: - Navigation
extension WebModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["about", "data", "blob"].contains(scheme) { return decisionHandler(.allow) }
        if scheme != "http" && scheme != "https" {
            // tel:, mailto:, sms:, whatsapp:… → application correspondante
            openExternally(url)
            return decisionHandler(.cancel)
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame && url.host?.hasSuffix(AppConfig.host) != true {
            // Autres sites (WhatsApp web, Google Maps, partenaires…) : ouverts hors de l'app
            openExternally(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        firstLoadDone = true
        offline = false
        webView.scrollView.refreshControl?.endRefreshing()
        // Première visite de l'espace organisateur après connexion : on propose les notifications
        if isOrganizerPage && !UserDefaults.standard.bool(forKey: "pushAsked") {
            UserDefaults.standard.set(true, forKey: "pushAsked")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { AppDelegate.requestPushPermission() }
        }
        sendPushTokenIfPossible()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    private func handle(_ error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return }   // navigation annulée par la règle ci-dessus
        let offlineCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                            NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed]
        if e.domain == NSURLErrorDomain && offlineCodes.contains(e.code) { offline = true }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - Fenêtres, alertes et confirmations JavaScript
extension WebModel: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Liens target="_blank" : dans l'app pour le site, à l'extérieur pour le reste
        if let url = navigationAction.request.url {
            if url.host?.hasSuffix(AppConfig.host) == true { webView.load(URLRequest(url: url)) } else { openExternally(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        if let top = topViewController() { top.present(a, animated: true) } else { completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        if let top = topViewController() { top.present(a, animated: true) } else { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        if let top = topViewController() { top.present(a, animated: true) } else { completionHandler(nil) }
    }
}

// MARK: - Pont JavaScript → iPhone
extension WebModel: WKScriptMessageHandler {
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
        let id = (body["id"] as? Int) ?? 0
        let data = body["data"] as? [String: Any] ?? [:]
        switch cmd {
        case "contacts":
            contactsRequestId = id
            let picker = CNContactPickerViewController()
            picker.delegate = self
            topViewController()?.present(picker, animated: true)
        case "share":
            var items: [Any] = []
            let text = [data["title"] as? String, data["text"] as? String].compactMap { $0 }.joined(separator: "\n")
            if !text.isEmpty { items.append(text) }
            if let s = data["url"] as? String, let u = URL(string: s) { items.append(u) }
            if items.isEmpty { return reply(id, ok: false, json: "null") }
            let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = webView
            vc.completionWithItemsHandler = { [weak self] _, done, _, _ in self?.reply(id, ok: done, json: "null") }
            topViewController()?.present(vc, animated: true)
        case "push":
            AppDelegate.requestPushPermission { [weak self] granted in self?.reply(id, ok: true, json: granted ? "true" : "false") }
        case "haptic":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            reply(id, ok: true, json: "null")
        default:
            reply(id, ok: false, json: "null")
        }
    }
}

// MARK: - Sélecteur de contacts (aucune autorisation globale : l'utilisateur choisit qui partager)
extension WebModel: CNContactPickerDelegate {
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
        let list: [[String: String]] = contacts.map { c in
            [
                "given": c.givenName,
                "family": c.familyName,
                "email": (c.emailAddresses.first?.value as String?) ?? "",
                "phone": c.phoneNumbers.first?.value.stringValue ?? ""
            ]
        }
        let json = (try? JSONSerialization.data(withJSONObject: list)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        if let id = contactsRequestId { reply(id, ok: true, json: json) }
        contactsRequestId = nil
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        if let id = contactsRequestId { reply(id, ok: true, json: "[]") }
        contactsRequestId = nil
    }
}
