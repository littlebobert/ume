import Foundation
import Security
import CryptoKit

let extensionBundleIdentifier = "com.justin.ume.Extension"
private let keychainService = "com.justin.ume.ai-settings"
private let answerKeyService = "com.justin.ume.answer-encryption"
#if os(macOS)
private let appGroupIdentifier = "XDWKSAH7W3.group.com.justin.ume.shared"
#else
private let appGroupIdentifier = "group.com.justin.ume.shared"
#endif

struct AISettings: Codable {
    var provider: String
    var model: String
    var apiKey: String
}

enum StoreError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

private func sharedKeychainAccessGroup() -> String? {
    Bundle.main.object(forInfoDictionaryKey: "UmeKeychainAccessGroup") as? String
}

private func keychainQuery(service: String) -> [String: Any] {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: "default"
    ]
    if let accessGroup = sharedKeychainAccessGroup() {
        query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
}

enum OnboardingStore {
    private static let completionKey = "onboarding-completed"

    static var isComplete: Bool {
        get {
            guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
                return SettingsStore.load()?.apiKey.isEmpty == false
            }
            if defaults.object(forKey: completionKey) == nil,
               SettingsStore.load()?.apiKey.isEmpty == false {
                defaults.set(true, forKey: completionKey)
            }
            return defaults.bool(forKey: completionKey)
        }
        set {
            UserDefaults(suiteName: appGroupIdentifier)?.set(newValue, forKey: completionKey)
        }
    }
}

enum SettingsStore {
    static func load() -> AISettings? {
        var query = keychainQuery(service: keychainService)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AISettings.self, from: data)
    }

    static func save(_ settings: AISettings) throws {
        let data = try JSONEncoder().encode(settings)
        let query = keychainQuery(service: keychainService)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var inserted = query
            attributes.forEach { inserted[$0.key] = $0.value }
            let addStatus = SecItemAdd(inserted as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw StoreError.message("Apple Keychain could not save these settings.")
            }
        } else if status != errSecSuccess {
            throw StoreError.message("Apple Keychain could not save these settings.")
        }
    }

    static func delete() {
        SecItemDelete(keychainQuery(service: keychainService) as CFDictionary)
    }
}

enum AIDebugLogStore {
    private static let enabledKey = "ai-debug-logging-enabled"
    private static let hideSensitiveKey = "ai-debug-log-hide-sensitive"
    private static let lastErrorKey = "ai-debug-log-last-error"
    private static let lastAttemptKey = "ai-debug-log-last-attempt"
    private static let maximumBytes = 512_000

    static var isEnabled: Bool {
        get { UserDefaults(suiteName: appGroupIdentifier)?.bool(forKey: enabledKey) ?? false }
        set { UserDefaults(suiteName: appGroupIdentifier)?.set(newValue, forKey: enabledKey) }
    }

    static var hidesSensitiveInfo: Bool {
        get {
            let defaults = UserDefaults(suiteName: appGroupIdentifier)
            return defaults?.object(forKey: hideSensitiveKey) as? Bool ?? true
        }
        set { UserDefaults(suiteName: appGroupIdentifier)?.set(newValue, forKey: hideSensitiveKey) }
    }

    private static func fileURL() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw StoreError.message("Ume could not access its shared data container.")
        }
        return container.appendingPathComponent("ai-debug.log", isDirectory: false)
    }

    static var lastError: String? {
        UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: lastErrorKey)
    }

    static var lastAttempt: Date? {
        UserDefaults(suiteName: appGroupIdentifier)?.object(forKey: lastAttemptKey) as? Date
    }

    static func append(_ event: String, details: String) {
        guard isEnabled else { return }
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.set(Date(), forKey: lastAttemptKey)
        do {
            let url = try fileURL()
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let entry = "[\(timestamp)] \(event)\n\(details)\n\n"
            var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            existing.append(entry)
            if existing.utf8.count > maximumBytes {
                let suffix = existing.utf8.suffix(maximumBytes)
                existing = String(decoding: suffix, as: UTF8.self)
                if let firstNewline = existing.firstIndex(of: "\n") {
                    existing.removeSubrange(...firstNewline)
                }
            }
            try existing.write(to: url, atomically: true, encoding: .utf8)
            defaults?.removeObject(forKey: lastErrorKey)
        } catch {
            defaults?.set(error.localizedDescription, forKey: lastErrorKey)
        }
    }

    static func read() -> String {
        guard let url = try? fileURL() else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func clear() throws {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.removeObject(forKey: lastErrorKey)
        defaults?.removeObject(forKey: lastAttemptKey)
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

enum AnswerStore {
    private static let maximumCount = 2_000

    private static func fileURL() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw StoreError.message("Ume could not access its shared data container.")
        }
        return container.appendingPathComponent("answers.encrypted", isDirectory: false)
    }

    private static func encryptionKey() throws -> SymmetricKey {
        var query = keychainQuery(service: answerKeyService)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            return SymmetricKey(data: data)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        var inserted = keychainQuery(service: answerKeyService)
        inserted[kSecValueData as String] = data
        inserted[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(inserted as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return try encryptionKey()
        }
        guard status == errSecSuccess else {
            throw StoreError.message("Apple Keychain could not protect saved answers.")
        }
        return key
    }

    private static func decrypt(from url: URL) throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let data = try AES.GCM.open(box, using: encryptionKey())
        guard let answers = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw StoreError.message("Saved answers could not be read.")
        }
        return answers
    }

    private static func normalized(_ answers: [[String: Any]]) -> ([[String: Any]], Bool) {
        var changed = false
        let result = answers.map { answer -> [String: Any] in
            var migrated = answer
            if migrated["answerID"] as? String == nil {
                migrated["answerID"] = UUID().uuidString
                changed = true
            }
            if (migrated["answerType"] as? String) == "countrycode" {
                let code = (migrated["value"] as? String ?? "").filter(\.isNumber)
                migrated["countryCode"] = code.isEmpty ? nil : code
                migrated["answerType"] = "phone"
                migrated["value"] = ""
                changed = true
            }
            return migrated
        }
        return (result, changed)
    }

    static func load() throws -> [[String: Any]] {
        let url = try fileURL()
        var coordinatedError: NSError?
        var result: Result<[[String: Any]], Error> = .success([])
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatedError) { coordinatedURL in
            result = Result { try decrypt(from: coordinatedURL) }
        }
        if let coordinatedError { throw coordinatedError }
        let answers = try result.get()
        let (migrated, changed) = normalized(answers)
        if changed { try save(migrated) }
        return migrated
    }

    static func save(_ answers: [[String: Any]]) throws {
        let (answers, _) = normalized(answers)
        guard answers.count <= maximumCount, JSONSerialization.isValidJSONObject(answers) else {
            throw StoreError.message("The saved answer data was invalid or too large.")
        }
        let data = try JSONSerialization.data(withJSONObject: answers, options: [.sortedKeys])
        let sealed = try AES.GCM.seal(data, using: encryptionKey())
        guard let combined = sealed.combined else {
            throw StoreError.message("Saved answers could not be encrypted.")
        }
        let url = try fileURL()
        var coordinatedError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatedError) { coordinatedURL in
            do {
#if os(iOS)
                try combined.write(to: coordinatedURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
#else
                try combined.write(to: coordinatedURL, options: .atomic)
#endif
            } catch {
                writeError = error
            }
        }
        if let coordinatedError { throw coordinatedError }
        if let writeError { throw writeError }
    }

    static func add(userLabel: String, value: String, answerType: String? = nil) throws {
        let label = userLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !value.isEmpty else {
            throw StoreError.message("Enter both a label and a value.")
        }
        var answer: [String: Any] = [
            "answerID": UUID().uuidString,
            "userLabel": label,
            "accessibleName": label,
            "label": label,
            "kind": "text",
            "inputType": "text",
            "value": value
        ]
        if let type = answerType?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty {
            answer["answerType"] = type
        }
        var answers = try load()
        answers.append(answer)
        try save(answers)
    }

    static func update(id: String, userLabel: String, value: Any) throws {
        var answers = try load()
        guard let index = answers.firstIndex(where: { $0["answerID"] as? String == id }) else {
            throw StoreError.message("That saved answer no longer exists.")
        }
        if userLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            answers[index].removeValue(forKey: "userLabel")
        } else {
            answers[index]["userLabel"] = userLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        answers[index]["value"] = value
        try save(answers)
    }

    static func delete(id: String) throws {
        let answers = try load().filter { $0["answerID"] as? String != id }
        try save(answers)
    }

    static func clear() throws {
        try save([])
    }
}
