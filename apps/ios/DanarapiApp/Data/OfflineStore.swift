import Foundation
import SwiftData

@Model
final class CachedSnapshotRecord {
    @Attribute(.unique) var ownerID: String
    var payload: Data
    var updatedAt: Date
    var schemaVersion: Int = 1

    init(ownerID: String, payload: Data, updatedAt: Date = .now) {
        self.ownerID = ownerID
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class OutboxRecord {
    @Attribute(.unique) var mutationID: String
    var ownerID: String
    var operation: String
    var payload: Data
    var baseVersion: Int?
    var createdAt: Date
    var status: String
    var lastErrorCode: String?
    var retryCount: Int = 0
    var nextRetryAt: Date?

    init(mutationID: String = UUID().uuidString, ownerID: String, operation: String, payload: Data, baseVersion: Int?, createdAt: Date = .now, status: String = "pending") {
        self.mutationID = mutationID
        self.ownerID = ownerID
        self.operation = operation
        self.payload = payload
        self.baseVersion = baseVersion
        self.createdAt = createdAt
        self.status = status
    }
}

@MainActor
final class OfflineStore {
    let container: ModelContainer
    private let context: ModelContext
    private let storeURL: URL?
    let isPersistent: Bool

    init(inMemory: Bool = false) throws {
        let schema = Schema([CachedSnapshotRecord.self, OutboxRecord.self])
        let configuration = ModelConfiguration("DanarapiProtected", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        isPersistent = !inMemory
        storeURL = inMemory ? nil : configuration.url
        if !inMemory {
            let directory = configuration.url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        }
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
        if !inMemory { try protectStoreFiles() }
    }

    func cache(_ snapshot: DashboardSnapshot, ownerID: String) throws {
        let data = try JSONEncoder.danarapi.encode(snapshot)
        let descriptor = FetchDescriptor<CachedSnapshotRecord>(predicate: #Predicate { $0.ownerID == ownerID })
        if let existing = try context.fetch(descriptor).first {
            existing.payload = data
            existing.updatedAt = .now
        } else {
            context.insert(CachedSnapshotRecord(ownerID: ownerID, payload: data))
        }
        try context.save()
        try protectStoreFiles()
    }

    func cachedSnapshot(ownerID: String) throws -> DashboardSnapshot? {
        let descriptor = FetchDescriptor<CachedSnapshotRecord>(predicate: #Predicate { $0.ownerID == ownerID })
        guard let record = try context.fetch(descriptor).first else { return nil }
        guard record.schemaVersion == 1 else { throw AppError.validation("Versi cache tidak didukung. Hubungkan perangkat untuk memuat ulang.") }
        return try JSONDecoder.danarapi.decode(DashboardSnapshot.self, from: record.payload)
    }

    @discardableResult
    func enqueue<T: Encodable>(ownerID: String, operation: String, payload: T, baseVersion: Int?) throws -> String {
        let record = OutboxRecord(ownerID: ownerID, operation: operation, payload: try JSONEncoder.danarapi.encode(payload), baseVersion: baseVersion)
        context.insert(record)
        try context.save()
        try protectStoreFiles()
        return record.mutationID
    }

    func pending(ownerID: String, forceRetry: Bool = false) throws -> [OutboxRecord] {
        let descriptor = FetchDescriptor<OutboxRecord>(
            predicate: #Predicate { $0.ownerID == ownerID && ($0.status == "pending" || $0.status == "failed") },
            sortBy: [SortDescriptor(\OutboxRecord.createdAt)]
        )
        return try context.fetch(descriptor).filter {
            $0.status == "pending" || forceRetry || ($0.nextRetryAt.map { $0 <= Date.now } ?? false)
        }
    }

    func markSynced(_ record: OutboxRecord) throws {
        context.delete(record)
        try context.save()
        try protectStoreFiles()
    }

    func markFailed(_ record: OutboxRecord, code: String) throws {
        record.status = code == "CONFLICT_VERSION" ? "conflict" : "failed"
        record.lastErrorCode = code
        record.retryCount += 1
        record.nextRetryAt = ["NETWORK", "INTERNAL", "QUOTA_EXCEEDED"].contains(code)
            ? Date.now.addingTimeInterval(min(300, pow(2, Double(min(record.retryCount, 9))))) : nil
        try context.save()
        try protectStoreFiles()
    }

    func count(ownerID: String) throws -> Int {
        let descriptor = FetchDescriptor<OutboxRecord>(predicate: #Predicate { $0.ownerID == ownerID && $0.status != "synced" })
        return try context.fetchCount(descriptor)
    }

    func clear(ownerID: String) throws {
        let cache = try context.fetch(FetchDescriptor<CachedSnapshotRecord>(predicate: #Predicate { $0.ownerID == ownerID }))
        let outbox = try context.fetch(FetchDescriptor<OutboxRecord>(predicate: #Predicate { $0.ownerID == ownerID }))
        cache.forEach(context.delete)
        outbox.forEach(context.delete)
        try context.save()
        try protectStoreFiles()
    }

    func allChanges(ownerID: String) throws -> [OutboxRecord] {
        try context.fetch(FetchDescriptor<OutboxRecord>(predicate: #Predicate { $0.ownerID == ownerID }, sortBy: [SortDescriptor(\OutboxRecord.createdAt)]))
    }

    func discard(mutationID: String, ownerID: String) throws {
        let records = try context.fetch(FetchDescriptor<OutboxRecord>(predicate: #Predicate { $0.ownerID == ownerID && $0.mutationID == mutationID }))
        records.forEach(context.delete)
        try context.save()
        try protectStoreFiles()
    }

    func saveConflictAsNew(mutationID: String, ownerID: String) throws {
        guard let record = try allChanges(ownerID: ownerID).first(where: { $0.mutationID == mutationID }),
              record.status == "conflict", record.operation == "update_transaction" else {
            throw AppError.validation("Hanya konflik perubahan pengeluaran dapat disimpan sebagai baru.")
        }
        var draft = try JSONDecoder.danarapi.decode(TransactionDraft.self, from: record.payload)
        guard draft.kind == .expense else { throw AppError.validation("Simpan sebagai baru hanya tersedia untuk pengeluaran.") }
        draft.id = nil
        draft.expectedVersion = nil
        let payload = try JSONEncoder.danarapi.encode(draft)
        record.mutationID = UUID().uuidString
        record.operation = "create_transaction"
        record.payload = payload
        record.baseVersion = nil
        record.status = "pending"
        record.lastErrorCode = nil
        record.retryCount = 0
        record.nextRetryAt = nil
        try context.save()
        try protectStoreFiles()
    }

    func overlay(_ serverSnapshot: DashboardSnapshot, ownerID: String) throws -> DashboardSnapshot {
        var snapshot = serverSnapshot
        for record in try allChanges(ownerID: ownerID) {
            switch record.operation {
            case "create_transaction", "update_transaction":
                let draft = try JSONDecoder.danarapi.decode(TransactionDraft.self, from: record.payload)
                let id = draft.id ?? "local-\(record.mutationID)"
                let item = FinanceTransaction(id: id, kind: draft.kind, amount: draft.amount, accountID: draft.accountID, categoryID: draft.categoryID, occurredAt: draft.occurredAt, merchant: draft.merchant, note: draft.note, source: draft.source, pendingSync: true, deleted: false, version: draft.expectedVersion ?? 1, goalID: draft.goalID)
                snapshot.transactions.removeAll { $0.id == id }
                snapshot.transactions.insert(item, at: 0)
            case "create_transfer", "update_transfer":
                let draft = try JSONDecoder.danarapi.decode(TransferDraft.self, from: record.payload)
                let id = draft.id ?? "local-\(record.mutationID)"
                let item = TransferRecord(id: id, fromAccountID: draft.fromAccountID, toAccountID: draft.toAccountID, amount: draft.amount, occurredAt: draft.occurredAt, note: draft.note, pendingSync: true, deleted: false, version: draft.expectedVersion ?? 1)
                snapshot.transfers.removeAll { $0.id == id }
                snapshot.transfers.insert(item, at: 0)
            case "delete_transaction":
                let value = try JSONDecoder.danarapi.decode(VersionedID.self, from: record.payload)
                snapshot.transactions.removeAll { $0.id == value.id }
            case "delete_transfer":
                let value = try JSONDecoder.danarapi.decode(VersionedID.self, from: record.payload)
                snapshot.transfers.removeAll { $0.id == value.id }
            default: throw AppError.validation("Operasi outbox tidak didukung.")
            }
        }
        return snapshot
    }

    private func protectStoreFiles() throws {
        let manager = FileManager.default
        guard let storeURL else { return }
        let support = storeURL.deletingLastPathComponent()
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let enumerator = manager.enumerator(at: support, includingPropertiesForKeys: Array(keys))
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: keys)
            guard url.path.hasPrefix(storeURL.path), values?.isRegularFile == true else { continue }
            try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            var resource = URLResourceValues()
            resource.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(resource)
        }
    }
}

extension JSONEncoder {
    static var danarapi: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var danarapi: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Tanggal harus RFC 3339.")
        }
        return decoder
    }
}
