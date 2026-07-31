import UIKit
import WebKit

class ViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = true
        webView.configuration.userContentController.add(self, name: "controller")
        webView.loadFileURL(Bundle.main.url(forResource: "Main", withExtension: "html")!, allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("show('ios')")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "load-settings":
            sendSettings()
        case "save-settings":
            saveSettings(body)
        case "delete-key":
            SettingsStore.delete()
            sendResult(ok: true, message: "The saved API key was deleted.")
        case "forget-everything":
            do {
                try AnswerStore.clear()
                sendResult(ok: true, message: "All saved answers were deleted. Your AI settings were kept.")
            } catch {
                sendResult(ok: false, message: "Ume could not delete all saved answers.")
            }
        default:
            break
        }
    }

    private func saveSettings(_ body: [String: Any]) {
        let provider = body["provider"] as? String ?? "openai"
        let model = body["model"] as? String ?? ""
        let suppliedKey = body["apiKey"] as? String ?? ""
        let key = suppliedKey.isEmpty ? SettingsStore.load()?.apiKey ?? "" : suppliedKey
        guard ["openai", "anthropic"].contains(provider), !model.isEmpty, !key.isEmpty else {
            sendResult(ok: false, message: "Enter a supported provider, model, and API key.")
            return
        }
        do {
            try SettingsStore.save(AISettings(provider: provider, model: model, apiKey: key))
            sendResult(ok: true, message: "Settings saved securely in Apple Keychain.")
        } catch {
            sendResult(ok: false, message: error.localizedDescription)
        }
    }

    private func settingsPayload() -> [String: Any] {
        let settings = SettingsStore.load()
        return [
            "provider": ["openai", "anthropic"].contains(settings?.provider ?? "") ? settings!.provider : "openai",
            "model": settings?.model ?? "",
            "hasKey": !(settings?.apiKey.isEmpty ?? true),
            "answers": (try? AnswerStore.load()) ?? []
        ]
    }

    private func sendSettings() {
        sendJavaScript(function: "receiveSettings", payload: settingsPayload())
    }

    private func sendResult(ok: Bool, message: String) {
        sendJavaScript(function: "receiveResult", payload: ["ok": ok, "message": message, "settings": settingsPayload()])
    }

    private func sendJavaScript(function: String, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("\(function)(\(json))")
    }
}
