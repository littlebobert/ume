import WebKit
import Security
import CryptoKit

#if os(iOS)
import UIKit
typealias PlatformViewController = UIViewController
#elseif os(macOS)
import Cocoa
import SafariServices
typealias PlatformViewController = NSViewController
#endif

let extensionBundleIdentifier = "com.justin.ume.Extension"
private let keychainService = "com.justin.ume.ai-settings"
private let answerKeyService = "com.justin.ume.answer-encryption"
#if os(macOS)
private let appGroupIdentifier = "XDWKSAH7W3.group.com.justin.ume.shared"
#else
private let appGroupIdentifier = "group.com.justin.ume.shared"
#endif
private func sharedKeychainAccessGroup() -> String? {
    Bundle.main.object(forInfoDictionaryKey: "UmeKeychainAccessGroup") as? String
}

private struct AISettings: Codable {
    var provider: String
    var model: String
    var apiKey: String
}

private enum AnswerStore {
    private static func keychainQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: answerKeyService,
            kSecAttrAccount as String: "default"
        ]
        if let accessGroup = sharedKeychainAccessGroup() { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    private static func encryptionKey() throws -> SymmetricKey {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            throw NSError(domain: "UmeAnswers", code: 1)
        }
        return SymmetricKey(data: data)
    }

    private static func fileURL() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw NSError(domain: "UmeAnswers", code: 2)
        }
        return container.appendingPathComponent("answers.encrypted", isDirectory: false)
    }

    static func load() throws -> [[String: Any]] {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let data = try AES.GCM.open(box, using: encryptionKey())
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }

    static func delete() throws {
        let url = try fileURL()
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        SecItemDelete(keychainQuery() as CFDictionary)
    }
}

private enum SettingsStore {
    static func load() -> AISettings? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "default",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let accessGroup = sharedKeychainAccessGroup() { query[kSecAttrAccessGroup as String] = accessGroup }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        query.removeAll()
        return try? JSONDecoder().decode(AISettings.self, from: data)
    }

    static func save(_ settings: AISettings) throws {
        let data = try JSONEncoder().encode(settings)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "default"
        ]
        if let accessGroup = sharedKeychainAccessGroup() { query[kSecAttrAccessGroup as String] = accessGroup }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var inserted = query
            attributes.forEach { inserted[$0.key] = $0.value }
            let addStatus = SecItemAdd(inserted as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func delete() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "default"
        ]
        if let accessGroup = sharedKeychainAccessGroup() { query[kSecAttrAccessGroup as String] = accessGroup }
        SecItemDelete(query as CFDictionary)
    }
}

class ViewController: PlatformViewController, WKNavigationDelegate, WKScriptMessageHandler {
    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.navigationDelegate = self
#if os(iOS)
        webView.scrollView.isScrollEnabled = true
#endif
        webView.configuration.userContentController.add(self, name: "controller")
        webView.loadFileURL(Bundle.main.url(forResource: "Main", withExtension: "html")!, allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
#if os(iOS)
        webView.evaluateJavaScript("show('ios')")
#elseif os(macOS)
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { state, _ in
            DispatchQueue.main.async {
                webView.evaluateJavaScript("show('mac', \(state?.isEnabled ?? false), true)")
            }
        }
#endif
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
            forgetEverything()
#if os(macOS)
        case "open-preferences":
            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { _ in }
#endif
        default:
            break
        }
    }

    private func saveSettings(_ body: [String: Any]) {
        let provider = body["provider"] as? String ?? "openai"
        let model = body["model"] as? String ?? ""
        let suppliedKey = body["apiKey"] as? String ?? ""
        let existingKey = SettingsStore.load()?.apiKey ?? ""
        let key = suppliedKey.isEmpty ? existingKey : suppliedKey

        guard ["openai", "anthropic"].contains(provider) else {
            sendResult(ok: false, message: "Choose a supported provider.")
            return
        }
        if model.isEmpty || key.isEmpty {
            sendResult(ok: false, message: "Enter both a model and API key.")
            return
        }
        do {
            try SettingsStore.save(AISettings(provider: provider, model: model, apiKey: key))
            sendResult(ok: true, message: "Settings saved securely in Apple Keychain.")
        } catch {
            sendResult(ok: false, message: "Keychain could not save these settings.")
        }
    }

    private func settingsPayload() -> [String: Any] {
        let settings = SettingsStore.load()
        let answers = (try? AnswerStore.load()) ?? []
        return [
            "provider": ["openai", "anthropic"].contains(settings?.provider ?? "") ? settings!.provider : "openai",
            "model": settings?.model ?? "",
            "hasKey": !(settings?.apiKey.isEmpty ?? true),
            "answers": answers
        ]
    }

    private func forgetEverything() {
        do {
            try AnswerStore.delete()
            SettingsStore.delete()
            sendResult(ok: true, message: "All saved answers and AI settings were deleted.")
        } catch {
            sendResult(ok: false, message: "Ume could not delete all saved data.")
        }
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
