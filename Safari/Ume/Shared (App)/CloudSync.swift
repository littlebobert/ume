import CloudKit
import Foundation

/// Persistent bookkeeping for iCloud sync, stored unencrypted in the app group
/// container. It holds only identifiers, timestamps, and the CloudKit change
/// token, never answer content.
struct SyncState: Codable {
    var changeToken: Data?
    var zoneReady = false
    var pendingUploads: Set<String> = []
    var pendingDeletes: Set<String> = []
    var lastPullAt: Double?
    var lastPushAt: Double?
    var lastError: String?
    var localKeyID: String?
    var unreadableCount = 0

    private static let lock = NSLock()

    private static func fileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("sync-state.json", isDirectory: false)
    }

    static func load() -> SyncState {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }

    private static func read() -> SyncState {
        guard let url = fileURL(), FileManager.default.fileExists(atPath: url.path) else { return SyncState() }
        var result = SyncState()
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { coordinatedURL in
            if let data = try? Data(contentsOf: coordinatedURL), let decoded = try? JSONDecoder().decode(SyncState.self, from: data) {
                result = decoded
            }
        }
        return result
    }

    private static func write(_ state: SyncState) {
        guard let url = fileURL(), let data = try? JSONEncoder().encode(state) else { return }
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: nil) { coordinatedURL in
            try? data.write(to: coordinatedURL, options: .atomic)
        }
    }

    /// Read-modify-write under a process-wide lock so the extension's save path and
    /// the sync engine do not clobber each other's pending lists.
    static func update(_ body: (inout SyncState) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var state = read()
        body(&state)
        write(state)
    }

    static func reset() {
        update { $0 = SyncState() }
    }
}

/// Syncs saved answers through the user's private CloudKit database.
///
/// Each answer is one record whose payload is the AES-GCM sealed JSON of the
/// answer, encrypted with the key shared through iCloud Keychain. Apple never
/// sees plaintext. Conflicts resolve per answer by last modification time.
final class CloudSync {
    static let shared = CloudSync()
    static let containerIdentifier = "iCloud.com.justin.henry.ume"
    static let didApplyRemoteChanges = Notification.Name("UmeCloudSyncDidApplyRemoteChanges")
    static let didFinishSync = Notification.Name("UmeCloudSyncDidFinishSync")
    private static let enabledKey = "icloud-sync-enabled"
    private static let recordType = "Answer"
    private static let batchSize = 200

    enum Reason: String {
        case launch, activate, localChange, extensionRead, extensionWrite, manual, timer
    }

    static var isEnabled: Bool {
        get {
            let defaults = UserDefaults(suiteName: appGroupIdentifier)
            return defaults?.object(forKey: enabledKey) as? Bool ?? true
        }
        set {
            UserDefaults(suiteName: appGroupIdentifier)?.set(newValue, forKey: enabledKey)
            if newValue {
                // Everything local should reach the other devices once sync resumes.
                AnswerStore.markAllPendingUpload()
                SyncState.update { $0.lastError = nil }
            }
        }
    }

    private let zoneID = CKRecordZone.ID(zoneName: "UmeAnswers", ownerName: CKCurrentUserDefaultName)
    private let lock = NSLock()
    private var inFlight: Task<Bool, Error>?
    private var accountStatusCache: (status: CKAccountStatus, at: Date)?

    private var database: CKDatabase {
        CKContainer(identifier: Self.containerIdentifier).privateCloudDatabase
    }

    // MARK: - Entry points

    /// Fire-and-forget sync for app lifecycle hooks.
    func syncInBackground(reason: Reason) {
        Task { _ = try? await sync(reason: reason) }
    }

    /// Sync but give up waiting after `timeout`. The sync itself keeps running so
    /// its results land on the next read; the caller just stops blocking on it.
    func sync(reason: Reason, timeout: TimeInterval, pullMinimumInterval: TimeInterval = 0) async -> Bool {
        let work = Task { try await self.sync(reason: reason, pullMinimumInterval: pullMinimumInterval) }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { (try? await work.value) ?? false }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// Pull remote changes, apply them locally, then push pending local changes.
    /// Returns true when remote changes were applied. Concurrent calls share one run.
    @discardableResult
    func sync(reason: Reason, pullMinimumInterval: TimeInterval = 0) async throws -> Bool {
        guard Self.isEnabled else { return false }
        if pullMinimumInterval > 0 {
            let state = SyncState.load()
            let recent = state.lastPullAt.map { Date().timeIntervalSince1970 - $0 < pullMinimumInterval } ?? false
            if recent && state.pendingUploads.isEmpty && state.pendingDeletes.isEmpty { return false }
        }

        return try await inFlightOrStart(reason: reason).value
    }

    /// Returns the running sync task, or starts one. Synchronous so the lock is
    /// never held across a suspension point.
    private func inFlightOrStart(reason: Reason) -> Task<Bool, Error> {
        lock.lock()
        defer { lock.unlock() }
        if let running = inFlight { return running }
        let task = Task<Bool, Error> {
            defer { self.finishInFlight() }
            return try await self.performSync(reason: reason)
        }
        inFlight = task
        return task
    }

    private func finishInFlight() {
        lock.lock()
        inFlight = nil
        lock.unlock()
    }

    func accountStatus() async -> CKAccountStatus {
        if let cached = accountStatusCache, Date().timeIntervalSince(cached.at) < 60 { return cached.status }
        let status = (try? await CKContainer(identifier: Self.containerIdentifier).accountStatus()) ?? .couldNotDetermine
        accountStatusCache = (status, Date())
        return status
    }

    func statusDescription() async -> String {
        guard Self.isEnabled else { return "Sync is off. Saved answers stay on this device." }
        switch await accountStatus() {
        case .available:
            break
        case .noAccount:
            return "Sign in to iCloud on this device to sync saved answers."
        case .restricted:
            return "iCloud is restricted on this device, so answers stay here."
        default:
            return "iCloud is unavailable right now. Umete will retry."
        }
        let state = SyncState.load()
        if let error = state.lastError, !error.isEmpty { return "Sync problem: \(error)" }
        guard let last = state.lastPullAt else { return "Waiting for the first sync." }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        var text = "Last synced \(formatter.localizedString(for: Date(timeIntervalSince1970: last), relativeTo: Date()))."
        if !state.pendingUploads.isEmpty || !state.pendingDeletes.isEmpty {
            text += " Changes on this device are waiting to upload."
        }
        if state.unreadableCount > 0 {
            text += " \(state.unreadableCount) answer\(state.unreadableCount == 1 ? "" : "s") from another device can't be read until that device syncs again."
        }
        return text
    }

    // MARK: - Sync pipeline

    private func performSync(reason: Reason) async throws -> Bool {
        guard await accountStatus() == .available else { return false }
        var appliedRemote = false
        do {
            try await ensureZone()
            appliedRemote = try await pull()
            try await push()
            SyncState.update { $0.lastError = nil }
        } catch {
            let message = Self.describe(error)
            SyncState.update { $0.lastError = message }
            SupportDiagnostics.record("iCloud sync (\(reason.rawValue)) failed: \(message)")
            NotificationCenter.default.post(name: Self.didFinishSync, object: nil)
            throw error
        }
        NotificationCenter.default.post(name: Self.didFinishSync, object: nil)
        if appliedRemote {
            NotificationCenter.default.post(name: Self.didApplyRemoteChanges, object: nil)
        }
        return appliedRemote
    }

    private func ensureZone() async throws {
        guard !SyncState.load().zoneReady else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        SyncState.update { $0.zoneReady = true }
    }

    private func pull() async throws -> Bool {
        var token = SyncState.load().changeToken.flatMap(Self.decodeToken)
        var changed: [[String: Any]] = []
        var deleted: [String] = []
        var unreadable = 0
        var needsReupload: [String] = []
        var moreComing = true
        while moreComing {
            let page: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, Error>],
                       deletions: [CKDatabase.RecordZoneChange.Deletion],
                       changeToken: CKServerChangeToken,
                       moreComing: Bool)
            do {
                page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            } catch let error as CKError where error.code == .changeTokenExpired {
                SyncState.update { $0.changeToken = nil }
                token = nil
                continue
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                SyncState.update { state in
                    state.zoneReady = false
                    state.changeToken = nil
                }
                AnswerStore.markAllPendingUpload()
                try await ensureZone()
                token = nil
                continue
            }
            for (_, result) in page.modificationResultsByID {
                guard case .success(let modification) = result else { continue }
                let record = modification.record
                guard let payload = record["payload"] as? Data else { continue }
                let keyID = record["keyID"] as? String ?? ""
                switch try AnswerStore.openSynced(payload: payload, keyID: keyID) {
                case .current(let answer):
                    changed.append(answer)
                case .legacy(let answer):
                    // Readable only with this device's old key: adopt it, then re-upload under the shared key.
                    changed.append(answer)
                    if let id = answer["answerID"] as? String { needsReupload.append(id) }
                case .unreadable:
                    unreadable += 1
                }
            }
            deleted.append(contentsOf: page.deletions.map { $0.recordID.recordName })
            token = page.changeToken
            moreComing = page.moreComing
        }

        let applied = try AnswerStore.applyRemote(changed: changed, deletedIDs: deleted)
        let encodedToken = token.flatMap(Self.encodeToken)
        SyncState.update { state in
            state.changeToken = encodedToken
            state.lastPullAt = Date().timeIntervalSince1970
            state.unreadableCount = unreadable
            state.pendingUploads.formUnion(needsReupload)
        }
        return applied
    }

    private func push() async throws {
        let state = SyncState.load()
        guard !state.pendingUploads.isEmpty || !state.pendingDeletes.isEmpty else { return }
        let answers = try AnswerStore.loadForSync()
        let byID = Dictionary(answers.compactMap { answer in (answer["answerID"] as? String).map { ($0, answer) } }, uniquingKeysWith: { $1 })

        var records: [CKRecord] = []
        var orphaned: [String] = []
        for id in state.pendingUploads {
            guard let answer = byID[id] else {
                orphaned.append(id)
                continue
            }
            let sealed = try AnswerStore.sealForSync(answer)
            let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: id, zoneID: zoneID))
            record["payload"] = sealed.payload as CKRecordValue
            record["keyID"] = sealed.keyID as CKRecordValue
            record["modifiedAt"] = (answer["modifiedAt"] as? Double ?? Date().timeIntervalSince1970) as CKRecordValue
            records.append(record)
        }
        if !orphaned.isEmpty {
            SyncState.update { state in orphaned.forEach { state.pendingUploads.remove($0) } }
        }
        let deletions = state.pendingDeletes.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }

        var index = 0
        var deleteIndex = 0
        while index < records.count || deleteIndex < deletions.count {
            let saving = Array(records[index..<min(index + Self.batchSize, records.count)])
            let deleting = Array(deletions[deleteIndex..<min(deleteIndex + Self.batchSize, deletions.count)])
            index += saving.count
            deleteIndex += deleting.count
            let results = try await database.modifyRecords(saving: saving, deleting: deleting, savePolicy: .allKeys, atomically: false)
            var uploaded: [String] = []
            var removed: [String] = []
            var firstError: Error?
            for (recordID, result) in results.saveResults {
                switch result {
                case .success: uploaded.append(recordID.recordName)
                case .failure(let error): firstError = firstError ?? error
                }
            }
            for (recordID, result) in results.deleteResults {
                switch result {
                case .success: removed.append(recordID.recordName)
                case .failure(let error as CKError) where error.code == .unknownItem: removed.append(recordID.recordName)
                case .failure(let error): firstError = firstError ?? error
                }
            }
            SyncState.update { state in
                uploaded.forEach { state.pendingUploads.remove($0) }
                removed.forEach { state.pendingDeletes.remove($0) }
                state.lastPushAt = Date().timeIntervalSince1970
            }
            if let firstError { throw firstError }
        }
    }

    // MARK: - Helpers

    private static func encodeToken(_ token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func decodeToken(_ data: Data) -> CKServerChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private static func describe(_ error: Error) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure: return "You appear to be offline."
            case .notAuthenticated: return "Sign in to iCloud to sync."
            case .quotaExceeded: return "Your iCloud storage is full."
            case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud is busy. Umete will retry."
            default: break
            }
        }
        return error.localizedDescription
    }
}
