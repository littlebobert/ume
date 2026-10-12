import Foundation
import Security
import CryptoKit

let extensionBundleIdentifier = "\(Bundle.main.bundleIdentifier ?? "com.justin.henry.ume").extension"
private let keychainService = "com.justin.ume.ai-settings"
private let answerKeyService = "com.justin.ume.answer-encryption"
private let syncKeyService = "com.justin.ume.answer-encryption.sync"
let appGroupIdentifier = Bundle.main.object(forInfoDictionaryKey: "UmeAppGroupIdentifier") as? String
    ?? "group.com.justin.ume.shared"

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

private func keychainQuery(service: String, usesDataProtection: Bool = true) -> [String: Any] {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: "default"
    ]
    if let accessGroup = sharedKeychainAccessGroup() {
        query[kSecAttrAccessGroup as String] = accessGroup
    }
#if os(macOS)
    if usesDataProtection {
        query[kSecUseDataProtectionKeychain as String] = true
    }
#endif
    return query
}

private func migratedKeychainData(service: String, accessible: CFString) throws -> Data? {
    var protectedQuery = keychainQuery(service: service)
    protectedQuery[kSecReturnData as String] = true
    protectedQuery[kSecMatchLimit as String] = kSecMatchLimitOne
    var protectedItem: CFTypeRef?
    let protectedStatus = SecItemCopyMatching(protectedQuery as CFDictionary, &protectedItem)
    if protectedStatus == errSecSuccess {
        return protectedItem as? Data
    }
    guard protectedStatus == errSecItemNotFound else {
        throw StoreError.message("Apple Keychain could not read Ume's protected data.")
    }

#if os(macOS)
    var legacyQuery = keychainQuery(service: service, usesDataProtection: false)
    legacyQuery[kSecReturnData as String] = true
    legacyQuery[kSecMatchLimit as String] = kSecMatchLimitOne
    legacyQuery[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    var legacyItem: CFTypeRef?
    let legacyStatus = SecItemCopyMatching(legacyQuery as CFDictionary, &legacyItem)
    if legacyStatus == errSecSuccess, let data = legacyItem as? Data {
        var inserted = keychainQuery(service: service)
        inserted[kSecValueData as String] = data
        inserted[kSecAttrAccessible as String] = accessible
        let addStatus = SecItemAdd(inserted as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw StoreError.message("Apple Keychain could not migrate Ume's protected data.")
        }

        legacyQuery[kSecReturnData as String] = nil
        legacyQuery[kSecMatchLimit as String] = nil
        SecItemDelete(legacyQuery as CFDictionary)
        return data
    }
    if legacyStatus == errSecInteractionNotAllowed || legacyStatus == errSecAuthFailed || legacyStatus == errSecUserCanceled {
        throw StoreError.message("Ume found protected data from an older build that macOS no longer recognizes. Remove the old Ume keychain items and reopen Ume.")
    }
    guard legacyStatus == errSecItemNotFound else {
        throw StoreError.message("Apple Keychain could not read Ume's older protected data.")
    }
#endif

    return nil
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
        guard let data = try? migratedKeychainData(
            service: keychainService,
            accessible: kSecAttrAccessibleAfterFirstUnlock
        ) else { return nil }
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
            let entry = "[\(timestamp)] \(event)\n\(Self.compactedDetails(details))\n\n"
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

    private static func compactedDetails(_ details: String) -> String {
        guard let data = details.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let compacted = try? JSONSerialization.data(withJSONObject: compactOptions(object), options: [.sortedKeys]),
              let string = String(data: compacted, encoding: .utf8) else { return details }
        return string
    }

    private static func compactOptions(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, child) in dict {
                if key == "options", let options = child as? [Any], options.count > 8 {
                    result[key] = Array(options.prefix(6)) + ["…+\(options.count - 6) more"]
                } else {
                    result[key] = compactOptions(child)
                }
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { compactOptions($0) }
        }
        return value
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

enum SupportDiagnostics {
    private static let key = "support-diagnostics"
    private static let limit = 8_000

    static func record(_ event: String) {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var existing = defaults?.string(forKey: key) ?? ""
        existing += "[" + timestamp + "] " + event + "\n"
        if existing.utf8.count > limit {
            existing = String(decoding: existing.utf8.suffix(limit), as: UTF8.self)
        }
        defaults?.set(existing, forKey: key)
    }

    static func read() -> String {
        UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: key) ?? ""
    }

    static func bugReportBody(version: String, platform: String) -> String {
        let answersStatus: String
        do {
            let answers = try AnswerStore.load()
            answersStatus = "readable, \(answers.count) saved"
        } catch {
            answersStatus = "error: \(error.localizedDescription)"
        }
        let diagnostics = read()
        let logLimit = 12_000
        var aiLog = AIDebugLogStore.read()
        var truncationNote: String?
        if aiLog.count > logLimit {
            aiLog = String(aiLog.suffix(logLimit))
            truncationNote = "The AI debug log was truncated to the most recent \(logLimit) characters. Use View Log… in Settings → AI Provider for the complete file."
        }
        let aiError = AIDebugLogStore.lastError
        return [
            "Hi Justin,",
            "",
            "I'm reporting a bug in Ume.",
            "Ume version: \(version)",
            "Platform: \(platform)",
            "Saved answers: \(answersStatus)",
            "",
            "--- Diagnostics ---",
            diagnostics.isEmpty ? "No app diagnostics yet." : diagnostics,
            "",
            "--- AI Debug Log ---",
            truncationNote,
            aiError.map { "Last AI log error: \($0)" },
            aiLog.isEmpty ? "No AI debug log. Enable logging in Settings → AI Provider to capture fill requests." : aiLog
        ].compactMap { $0 }.joined(separator: "\n")
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

    // MARK: Encryption keys
    //
    // Two keys can exist. The legacy key is device-only and predates sync. The
    // sync key lives in iCloud Keychain so every device can read shared records.
    // Once a sync key exists it is always the current key; the legacy key is kept
    // only to read older local files and records this device uploaded before.

    private static func syncKeyQuery() -> [String: Any] {
        var query = keychainQuery(service: syncKeyService)
        query[kSecAttrSynchronizable as String] = true
        return query
    }

    private static func syncKey() -> SymmetricKey? {
        var query = syncKeyQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    private static func storeSyncKey(_ key: SymmetricKey) -> SymmetricKey {
        var inserted = syncKeyQuery()
        inserted[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        inserted[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(inserted as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = syncKey() {
            // Another device stored the shared key first. Use theirs.
            return existing
        }
        if status != errSecSuccess {
            SupportDiagnostics.record("Could not store the iCloud answer key (status \(status)).")
        }
        return syncKey() ?? key
    }

    private static func legacyKey(createIfMissing: Bool) throws -> SymmetricKey? {
        if let data = try migratedKeychainData(
            service: answerKeyService,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ) {
            if data.count == 32 {
                return SymmetricKey(data: data)
            }
            SupportDiagnostics.record("Replaced invalid answer encryption key (\(data.count) bytes).")
            SecItemDelete(keychainQuery(service: answerKeyService) as CFDictionary)
#if os(macOS)
            SecItemDelete(keychainQuery(service: answerKeyService, usesDataProtection: false) as CFDictionary)
#endif
        }
        guard createIfMissing else { return nil }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        var inserted = keychainQuery(service: answerKeyService)
        inserted[kSecValueData as String] = data
        inserted[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(inserted as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return try legacyKey(createIfMissing: true)
        }
        guard status == errSecSuccess else {
            throw StoreError.message("Apple Keychain could not protect saved answers.")
        }
        return key
    }

    private static func encryptionKey() throws -> SymmetricKey {
        if let key = syncKey() { return key }
        if CloudSync.isEnabled {
            // Promote this device's key so other devices can decrypt what it uploads.
            if let legacy = try legacyKey(createIfMissing: false) { return storeSyncKey(legacy) }
            return storeSyncKey(SymmetricKey(size: .bits256))
        }
        guard let key = try legacyKey(createIfMissing: true) else {
            throw StoreError.message("Apple Keychain could not protect saved answers.")
        }
        return key
    }

    private static func keyID(_ key: SymmetricKey) -> String {
        let digest = SHA256.hash(data: key.withUnsafeBytes { Data($0) })
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static var currentKeyID: String? {
        (try? encryptionKey()).map(keyID)
    }

    /// Decrypts the local file with the current key, falling back to the legacy
    /// device key after a sync key arrived from another device.
    private static func decrypt(from url: URL) throws -> (answers: [[String: Any]], usedLegacyKey: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], false) }
        let contents = try Data(contentsOf: url)
        guard !contents.isEmpty else { return ([], false) }
        let box = try AES.GCM.SealedBox(combined: contents)
        let current = try encryptionKey()
        var candidates: [(SymmetricKey, Bool)] = [(current, false)]
        if let legacy = try legacyKey(createIfMissing: false), keyID(legacy) != keyID(current) {
            candidates.append((legacy, true))
        }
        for (key, isLegacy) in candidates {
            guard let data = try? AES.GCM.open(box, using: key) else { continue }
            guard let answers = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw StoreError.message("Saved answers could not be read.")
            }
            return (answers, isLegacy)
        }
        SupportDiagnostics.record("Discarded unreadable answers file (\(contents.count) bytes).")
        try FileManager.default.removeItem(at: url)
        return ([], false)
    }

    // MARK: Sync support

    static let didChangeLocally = Notification.Name("UmeAnswerStoreDidChangeLocally")

    enum SyncedPayload {
        case current([String: Any])
        case legacy([String: Any])
        case unreadable
    }

    /// Answers as stored, without triggering migrations or saves. Used by the sync engine.
    static func loadForSync() throws -> [[String: Any]] {
        try decryptCoordinated().answers
    }

    static func sealForSync(_ answer: [String: Any]) throws -> (payload: Data, keyID: String) {
        let key = try encryptionKey()
        let data = try JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw StoreError.message("A saved answer could not be encrypted for iCloud.")
        }
        return (combined, keyID(key))
    }

    static func openSynced(payload: Data, keyID recordKeyID: String) throws -> SyncedPayload {
        let current = try encryptionKey()
        var candidates: [(SymmetricKey, Bool)] = [(current, false)]
        if let legacy = try legacyKey(createIfMissing: false), keyID(legacy) != keyID(current) {
            candidates.append((legacy, true))
        }
        let ordered = candidates.sorted { lhs, _ in keyID(lhs.0) == recordKeyID }
        guard let box = try? AES.GCM.SealedBox(combined: payload) else { return .unreadable }
        for (key, isLegacy) in ordered {
            guard let data = try? AES.GCM.open(box, using: key),
                  let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            return isLegacy ? .legacy(answer) : .current(answer)
        }
        return .unreadable
    }

    static func markAllPendingUpload() {
        let ids = ((try? loadForSync()) ?? []).compactMap { $0["answerID"] as? String }
        SyncState.update { state in
            state.pendingUploads.formUnion(ids)
            state.localKeyID = currentKeyID
        }
    }

    /// The answer without sync bookkeeping, serialized for change detection.
    private static func comparable(_ answer: [String: Any]) -> Data? {
        var copy = answer
        copy.removeValue(forKey: "modifiedAt")
        return try? JSONSerialization.data(withJSONObject: copy, options: [.sortedKeys])
    }

    private static func isStorable(_ answer: [String: Any]) -> Bool {
        guard answer["answerID"] is String else { return false }
        guard let type = answer["answerType"] as? String, aggregateTypes.contains(type) else { return true }
        guard let raw = answer["value"] as? [String: Any] else { return false }
        return (try? (type == "address" ? validatedAddress(raw) : validatedContact(raw))) != nil
    }

    /// Merge answers fetched from iCloud. Local answers that are newer and still
    /// waiting to upload win; everything else takes the remote version. Returns
    /// true when the local file changed.
    static func applyRemote(changed: [[String: Any]], deletedIDs: [String]) throws -> Bool {
        var answers = try decryptCoordinated().answers
        var changedAny = false
        var state = SyncState.load()
        for remote in changed {
            guard let id = remote["answerID"] as? String else { continue }
            guard isStorable(remote) else {
                SupportDiagnostics.record("Skipped an iCloud answer that failed validation.")
                continue
            }
            let remoteTime = remote["modifiedAt"] as? Double ?? 0
            if let index = answers.firstIndex(where: { $0["answerID"] as? String == id }) {
                let localTime = answers[index]["modifiedAt"] as? Double ?? 0
                if state.pendingUploads.contains(id) && localTime >= remoteTime { continue }
                if comparable(answers[index]) != comparable(remote) {
                    answers[index] = remote
                    changedAny = true
                } else if answers[index]["modifiedAt"] as? Double != remoteTime {
                    answers[index]["modifiedAt"] = remoteTime
                    changedAny = true
                }
            } else if !state.pendingDeletes.contains(id) {
                answers.append(remote)
                changedAny = true
            }
            state.pendingUploads.remove(id)
        }
        for id in deletedIDs {
            if let index = answers.firstIndex(where: { $0["answerID"] as? String == id }) {
                answers.remove(at: index)
                changedAny = true
            }
            state.pendingUploads.remove(id)
            state.pendingDeletes.remove(id)
        }
        let pendingUploads = state.pendingUploads
        let pendingDeletes = state.pendingDeletes
        SyncState.update { current in
            current.pendingUploads = pendingUploads
            current.pendingDeletes = pendingDeletes
        }
        if changedAny { try save(answers, markingChanges: false) }
        return changedAny
    }

    private static func decryptCoordinated() throws -> (answers: [[String: Any]], usedLegacyKey: Bool) {
        let url = try fileURL()
        var coordinatedError: NSError?
        var result: Result<(answers: [[String: Any]], usedLegacyKey: Bool), Error> = .success(([], false))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatedError) { coordinatedURL in
            result = Result { try decrypt(from: coordinatedURL) }
        }
        if let coordinatedError { throw coordinatedError }
        return try result.get()
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
        let (answers, usedLegacyKey) = try decryptCoordinated()
        let (migrated, changed) = normalized(answers)
        if changed {
            try save(migrated)
        } else if usedLegacyKey {
            // Re-encrypt with the shared key now that one exists.
            try save(migrated, markingChanges: false)
        }
        if CloudSync.isEnabled, let keyID = currentKeyID, SyncState.load().localKeyID != keyID {
            // First run with sync, or the shared key changed: everything here must be (re)uploaded.
            markAllPendingUpload()
        }
        return migrated
    }

    private static func validatedAddress(_ raw: [String: Any]) throws -> [String: Any] {
        let limits = [
            "addressLine1": 240,
            "addressLine2": 240,
            "locality": 120,
            "administrativeArea": 120,
            "postalCode": 32,
            "countryCode": 2,
            "countryName": 120
        ]
        var address: [String: Any] = ["version": 1]
        for (key, limit) in limits {
            let value = (raw[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count <= limit else { throw StoreError.message("The saved address was too long.") }
            if !value.isEmpty { address[key] = value }
        }
        let line1 = address["addressLine1"] as? String ?? ""
        let countryCode = (address["countryCode"] as? String ?? "").uppercased()
        guard !line1.isEmpty else { throw StoreError.message("Enter a street address.") }
        guard countryCode.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil else {
            throw StoreError.message("Choose a country or region.")
        }
        address["countryCode"] = countryCode
        return address
    }

    static let contactCategories = ["doctor", "emergencyContact"]
    static let aggregateTypes = ["address", "contact"]

    private static func validatedContact(_ raw: [String: Any]) throws -> [String: Any] {
        let limits = [
            "name": 160,
            "role": 120,
            "phone": 64,
            "fax": 64,
            "email": 254,
            "organization": 200,
            "address": 400
        ]
        var contact: [String: Any] = ["version": 1]
        for (key, limit) in limits {
            let value = (raw[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count <= limit else { throw StoreError.message("The saved contact was too long.") }
            if !value.isEmpty { contact[key] = value }
        }
        guard contact["name"] != nil else { throw StoreError.message("Enter the contact's name.") }
        let category = (raw["category"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard contactCategories.contains(category) else { throw StoreError.message("Choose a contact kind.") }
        contact["category"] = category
        return contact
    }

    /// Persist answers. With `markingChanges`, answers that differ from the stored
    /// copy get a fresh modification time and are queued for iCloud upload, and
    /// removed answers are queued for deletion. Sync applies remote changes with
    /// `markingChanges: false` so they are not echoed back.
    static func save(_ answers: [[String: Any]], markingChanges: Bool = true) throws {
        var (answers, _) = normalized(answers)
        if markingChanges {
            let previous = (try? decryptCoordinated().answers) ?? []
            let previousByID = Dictionary(previous.compactMap { answer in (answer["answerID"] as? String).map { ($0, answer) } }, uniquingKeysWith: { $1 })
            let now = Date().timeIntervalSince1970
            var uploads: [String] = []
            var seen = Set<String>()
            for index in answers.indices {
                guard let id = answers[index]["answerID"] as? String else { continue }
                seen.insert(id)
                if let prior = previousByID[id], comparable(prior) == comparable(answers[index]) {
                    answers[index]["modifiedAt"] = prior["modifiedAt"] ?? now
                } else {
                    answers[index]["modifiedAt"] = now
                    uploads.append(id)
                }
            }
            let deletes = previousByID.keys.filter { !seen.contains($0) }
            if !uploads.isEmpty || !deletes.isEmpty {
                SyncState.update { state in
                    uploads.forEach { state.pendingUploads.insert($0); state.pendingDeletes.remove($0) }
                    deletes.forEach { state.pendingDeletes.insert($0); state.pendingUploads.remove($0) }
                }
            }
        }
        for index in answers.indices {
            guard let type = answers[index]["answerType"] as? String, aggregateTypes.contains(type) else { continue }
            guard let raw = answers[index]["value"] as? [String: Any] else {
                throw StoreError.message(type == "address" ? "The saved address was invalid." : "The saved contact was invalid.")
            }
            answers[index]["value"] = type == "address" ? try validatedAddress(raw) : try validatedContact(raw)
            answers[index]["kind"] = "aggregate"
            answers[index]["inputType"] = ""
        }
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
        if markingChanges {
            NotificationCenter.default.post(name: didChangeLocally, object: nil)
        }
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

    static func addAddress(userLabel: String, value: [String: Any]) throws {
        let label = userLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw StoreError.message("Enter an address label.") }
        let address = try validatedAddress(value)
        var answers = try load()
        answers.append([
            "answerID": UUID().uuidString,
            "answerType": "address",
            "userLabel": label,
            "accessibleName": label,
            "label": label,
            "kind": "aggregate",
            "inputType": "",
            "value": address
        ])
        try save(answers)
    }

    static func updateAddress(id: String, userLabel: String, value: [String: Any]) throws {
        let label = userLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw StoreError.message("Enter an address label.") }
        let address = try validatedAddress(value)
        var answers = try load()
        guard let index = answers.firstIndex(where: { $0["answerID"] as? String == id }) else {
            throw StoreError.message("That saved address no longer exists.")
        }
        answers[index]["answerType"] = "address"
        answers[index]["userLabel"] = label
        answers[index]["accessibleName"] = label
        answers[index]["label"] = label
        answers[index]["kind"] = "aggregate"
        answers[index]["inputType"] = ""
        answers[index]["value"] = address
        try save(answers)
    }

    static func addContact(userLabel: String, value: [String: Any]) throws {
        let contact = try validatedContact(value)
        let label = resolvedContactLabel(userLabel, contact: contact)
        var answers = try load()
        answers.append([
            "answerID": UUID().uuidString,
            "answerType": "contact",
            "userLabel": label,
            "accessibleName": label,
            "label": label,
            "kind": "aggregate",
            "inputType": "",
            "value": contact
        ])
        try save(answers)
    }

    static func updateContact(id: String, userLabel: String, value: [String: Any]) throws {
        let contact = try validatedContact(value)
        let label = resolvedContactLabel(userLabel, contact: contact)
        var answers = try load()
        guard let index = answers.firstIndex(where: { $0["answerID"] as? String == id }) else {
            throw StoreError.message("That saved contact no longer exists.")
        }
        answers[index]["answerType"] = "contact"
        answers[index]["userLabel"] = label
        answers[index]["accessibleName"] = label
        answers[index]["label"] = label
        answers[index]["kind"] = "aggregate"
        answers[index]["inputType"] = ""
        answers[index]["value"] = contact
        answers[index].removeValue(forKey: "countryCode")
        try save(answers)
    }

    /// A contact's label defaults to its name so the table stays readable without extra typing.
    private static func resolvedContactLabel(_ userLabel: String, contact: [String: Any]) -> String {
        let label = userLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? (contact["name"] as? String ?? "") : label
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
