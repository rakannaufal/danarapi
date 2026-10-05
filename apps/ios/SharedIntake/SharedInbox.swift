import CryptoKit
import Darwin
import Foundation

enum SharedInboxError: LocalizedError {
    case unavailable, invalid, tooLarge, full, wrongOwner, signInRequired
    var errorDescription: String? {
        switch self {
        case .unavailable: "Penyimpanan Share tidak tersedia. Buka kunci perangkat lalu coba lagi."
        case .invalid: "Bukti tidak valid. Bagikan teks, JPEG, PNG, HEIC, atau PDF. Tautan saja belum didukung."
        case .tooLarge: "Maksimal 5 bukti per share, 5 MB per berkas, dan 64 KB teks."
        case .full: "Kotak Share penuh. Hapus salinan lokal yang tidak diperlukan di Tinjauan."
        case .wrongOwner: "Bukti ini sudah terikat ke akun lain. Masuk dengan akun tersebut untuk melanjutkan."
        case .signInRequired: "Masuk ke akun Danarapi terlebih dahulu, lalu bagikan kembali bukti ini."
        }
    }
}

struct SharedPayload: Sendable {
    let name: String
    let data: Data
    let context: String

    var mime: String? { Self.mime(data) }
    static func mime(_ data: Data) -> String? {
        let bytes = Array(data.prefix(12))
        if bytes.starts(with: [0xff, 0xd8, 0xff]) { return "image/jpeg" }
        if bytes.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) { return "image/png" }
        if bytes.starts(with: Array("%PDF-".utf8)) { return "application/pdf" }
        if bytes.count >= 12, String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp",
           ["heic", "heix", "hevc", "hevx", "mif1"].contains(String(bytes: bytes[8..<12], encoding: .ascii) ?? "") { return "image/heic" }
        if let text = String(data: data, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !text.contains("\0"), text.utf8.count <= SharedInbox.maximumTextBytes { return "text/plain" }
        return nil
    }

    static func text(_ value: String) throws -> SharedPayload {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= SharedInbox.maximumTextBytes else { throw SharedInboxError.tooLarge }
        guard text.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://\S+$"#, options: .regularExpression) == nil else { throw SharedInboxError.invalid }
        return SharedPayload(name: "Bukti teks.txt", data: Data(text.utf8), context: "")
    }
}

struct SharedInboxRecord: Codable, Identifiable, Hashable, Sendable {
    let version: Int
    let id: String
    let name: String
    let mime: String
    let byteCount: Int
    let fingerprint: String
    let context: String
    let createdAt: Date
    var ownerID: String?
    var imported: Bool
    var transferDraft: Data? = nil
    var aiProof: Data? = nil
}

struct SharedInboxAccount: Codable, Equatable, Sendable {
    let ownerID: String?
    let revision: UUID
}

// A directory rename commits a whole share. flock also serializes the app and extension.
struct SharedInbox: Sendable {
    static let groupID = "group.id.danarapi.app"
    static let maximumTextBytes = 64 * 1024
    static let maximumFileBytes = 5 * 1024 * 1024
    private let root: URL

    init(root: URL) { self.root = root }
    static func live() throws -> SharedInbox {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { throw SharedInboxError.unavailable }
        return SharedInbox(root: container.appendingPathComponent("ShareInbox", isDirectory: true))
    }

    func setActiveAccount(_ ownerID: String?) throws {
        try locked {
            if let ownerID, ownerID.isEmpty { throw SharedInboxError.invalid }
            let previous = try accountContext()
            guard previous?.ownerID != ownerID || previous == nil else { return }
            let value = SharedInboxAccount(ownerID: ownerID, revision: UUID())
            try protectedWrite(JSONEncoder().encode(value), to: root.appendingPathComponent(".account.json"))
        }
    }

    func activeAccount() throws -> SharedInboxAccount {
        try locked {
            guard let account = try accountContext(), account.ownerID != nil else { throw SharedInboxError.signInRequired }
            return account
        }
    }

    @discardableResult func save(_ payloads: [SharedPayload], ownerID: String? = nil, expectedAccount: SharedInboxAccount? = nil) throws -> [SharedInboxRecord] {
        guard !payloads.isEmpty, payloads.count <= 5 else { throw SharedInboxError.tooLarge }
        for payload in payloads {
            guard !payload.data.isEmpty, payload.data.count <= Self.maximumFileBytes,
                  payload.context.utf8.count <= Self.maximumTextBytes else { throw SharedInboxError.tooLarge }
            guard let mime = payload.mime, mime != "text/plain" || payload.data.count <= Self.maximumTextBytes else { throw SharedInboxError.invalid }
        }
        return try locked {
            if let expectedAccount {
                guard ownerID != nil, expectedAccount.ownerID == ownerID,
                      try accountContext() == expectedAccount else { throw SharedInboxError.wrongOwner }
            }
            if let ownerID, ownerID.isEmpty { throw SharedInboxError.invalid }
            let existing = try allRecords()
            let owned = existing.filter { $0.ownerID == ownerID }
            let hashes = payloads.map { Self.hash($0) }
            var knownHashes = Set(owned.map(\.fingerprint))
            var additionalBytes = 0
            var additionalCount = 0
            for (index, payload) in payloads.enumerated() where knownHashes.insert(hashes[index]).inserted {
                additionalBytes += payload.data.count; additionalCount += 1
            }
            guard owned.count + additionalCount <= 50,
                  owned.reduce(0, { $0 + $1.byteCount }) + additionalBytes <= 100 * 1024 * 1024 else { throw SharedInboxError.full }
            let batchID = UUID().uuidString.lowercased()
            let staging = root.appendingPathComponent(".staging-" + batchID, isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            defer { try? FileManager.default.removeItem(at: staging) }
            var records: [SharedInboxRecord] = []
            var newRecords: [SharedInboxRecord] = []
            for (index, payload) in payloads.enumerated() {
                if let previous = (owned + newRecords).first(where: { $0.fingerprint == hashes[index] }) {
                    records.append(previous); continue
                }
                let record = SharedInboxRecord(version: 1, id: UUID().uuidString.lowercased(), name: Self.cleanName(payload.name, mime: payload.mime!), mime: payload.mime!, byteCount: payload.data.count, fingerprint: hashes[index], context: payload.context, createdAt: .now, ownerID: ownerID, imported: false)
                try protectedWrite(payload.data, to: staging.appendingPathComponent(record.id + ".payload"))
                try protectedWrite(JSONEncoder().encode(record), to: staging.appendingPathComponent(record.id + ".json"))
                newRecords.append(record); records.append(record)
            }
            if !newRecords.isEmpty { try FileManager.default.moveItem(at: staging, to: root.appendingPathComponent(batchID, isDirectory: true)) }
            return records
        }
    }

    func records(ownerID: String? = nil) throws -> [SharedInboxRecord] {
        try locked { try allRecords().filter { $0.ownerID == ownerID }.sorted { $0.createdAt > $1.createdAt } }
    }

    func data(for id: String, ownerID: String?) throws -> Data {
        try locked {
            let (record, url) = try find(id)
            guard record.ownerID == ownerID else { throw SharedInboxError.wrongOwner }
            let file = url.deletingPathExtension().appendingPathExtension("payload")
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size == record.byteCount, size <= Self.maximumFileBytes else { throw SharedInboxError.invalid }
            let data = try Data(contentsOf: file)
            guard Self.hash(SharedPayload(name: record.name, data: data, context: record.context)) == record.fingerprint else { throw SharedInboxError.invalid }
            return data
        }
    }

    func bind(_ id: String, to ownerID: String) throws -> SharedInboxRecord {
        try locked {
            var (record, url) = try find(id)
            guard !ownerID.isEmpty, record.ownerID == ownerID else { throw SharedInboxError.wrongOwner }
            record.ownerID = ownerID
            try protectedWrite(JSONEncoder().encode(record), to: url)
            return record
        }
    }

    func markImported(_ id: String, ownerID: String) throws {
        try locked {
            var (record, url) = try find(id)
            guard record.ownerID == ownerID else { throw SharedInboxError.wrongOwner }
            record.imported = true
            try protectedWrite(JSONEncoder().encode(record), to: url)
        }
    }

    func rememberTransfer(_ id: String, ownerID: String, draft: Data) throws {
        try locked {
            var (record, url) = try find(id)
            guard record.ownerID == ownerID, record.imported, draft.count <= 4096 else { throw SharedInboxError.wrongOwner }
            if let previous = record.transferDraft, previous != draft { throw SharedInboxError.invalid }
            record.transferDraft = draft
            try protectedWrite(JSONEncoder().encode(record), to: url)
        }
    }

    func rememberAIProof(_ id: String, ownerID: String, proof: Data) throws {
        try locked {
            var (record, url) = try find(id)
            guard record.ownerID == ownerID, !record.imported else { throw SharedInboxError.wrongOwner }
            guard proof.count <= 16_384 else { throw SharedInboxError.tooLarge }
            record.aiProof = proof
            try protectedWrite(JSONEncoder().encode(record), to: url)
        }
    }

    func remove(_ id: String, ownerID: String?) throws {
        try locked {
            let (record, url) = try find(id)
            guard record.ownerID == ownerID else { throw SharedInboxError.wrongOwner }
            let payload = url.deletingPathExtension().appendingPathExtension("payload")
            if FileManager.default.fileExists(atPath: payload.path) { try FileManager.default.removeItem(at: payload) }
            try FileManager.default.removeItem(at: url)
        }
    }

    private func allRecords() throws -> [SharedInboxRecord] {
        let batches = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        return try batches.flatMap { batch -> [SharedInboxRecord] in
            guard UUID(uuidString: batch.lastPathComponent) != nil else { return [] }
            return try FileManager.default.contentsOfDirectory(at: batch, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles).filter { $0.pathExtension == "json" }.map { url in
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= Self.maximumTextBytes * 6 + 4096 else { throw SharedInboxError.invalid }
                let record = try JSONDecoder().decode(SharedInboxRecord.self, from: Data(contentsOf: url))
                guard record.version == 1, UUID(uuidString: record.id) != nil,
                      url.lastPathComponent == record.id + ".json", record.byteCount > 0,
                      record.byteCount <= Self.maximumFileBytes else { throw SharedInboxError.invalid }
                return record
            }
        }
    }

    private func accountContext() throws -> SharedInboxAccount? {
        let url = root.appendingPathComponent(".account.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(SharedInboxAccount.self, from: Data(contentsOf: url))
    }

    private func find(_ id: String) throws -> (SharedInboxRecord, URL) {
        guard UUID(uuidString: id) != nil else { throw SharedInboxError.invalid }
        for batch in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) where UUID(uuidString: batch.lastPathComponent) != nil {
            let url = batch.appendingPathComponent(id + ".json")
            if FileManager.default.fileExists(atPath: url.path) {
                let record = try JSONDecoder().decode(SharedInboxRecord.self, from: Data(contentsOf: url))
                guard record.id == id, record.version == 1 else { throw SharedInboxError.invalid }
                return (record, url)
            }
        }
        throw SharedInboxError.invalid
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var location = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try location.setResourceValues(values)
        let descriptor = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw SharedInboxError.unavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw SharedInboxError.unavailable }
        defer { flock(descriptor, LOCK_UN) }
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.lastPathComponent.hasPrefix(".staging-") {
            try FileManager.default.removeItem(at: file)
        }
        return try operation()
    }

    private func protectedWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
    private static func hash(_ payload: SharedPayload) -> String {
        var digest = SHA256()
        digest.update(data: payload.data)
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func cleanName(_ value: String, mime: String) -> String {
        let name = String((value as NSString).lastPathComponent.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(100))
        let ext = ["image/jpeg": "jpg", "image/png": "png", "image/heic": "heic", "application/pdf": "pdf", "text/plain": "txt"][mime] ?? "bin"
        if name.isEmpty { return "Bukti.\(ext)" }
        return name.lowercased().hasSuffix("." + ext) ? name : name + "." + ext
    }
}
