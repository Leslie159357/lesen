import SwiftUI
import WebKit

/// Owns the WKWebView that renders the book, and bridges tap events back to Swift.
final class WebReader: NSObject, ObservableObject, WKScriptMessageHandler {
    let webView: WKWebView

    @Published var isReady = false
    @Published var tappedWord = ""
    @Published var tappedSentence = ""

    override init() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(self, name: "ob")
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        if let url = Bundle.main.url(forResource: "reader", withExtension: "html", subdirectory: "Web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
        case "word":
            tappedWord = body["word"] as? String ?? ""
            tappedSentence = body["sentence"] as? String ?? ""
        case "log":
            print("[reader] \(body["msg"] as? String ?? "")")
        default:
            break
        }
    }

    func open(_ payload: BookPayload) {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return }
        evaluate("OB.open(\(json))")
    }

    func highlight(chapter: String, id: String) {
        guard let c = jsString(chapter), let i = jsString(id) else { return }
        evaluate("OB.highlight(\(c), \(i))")
    }

    func clearHighlight() {
        evaluate("OB.clearHighlight()")
    }

    func goToChapter(_ index: Int) {
        evaluate("OB.gotoChapter(\(index))")
    }

    func setFontScale(_ scale: Double) {
        evaluate("OB.setFontScale(\(scale))")
    }

    private func evaluate(_ script: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    /// JSON-quotes a string so it can be embedded in a JS call.
    private func jsString(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct ReaderWebView: UIViewRepresentable {
    let reader: WebReader

    func makeUIView(context: Context) -> WKWebView { reader.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
