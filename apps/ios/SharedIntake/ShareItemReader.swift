import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum ShareReadError: LocalizedError, Sendable {
    case unsupported, unavailable, timeout, noProof
    var errorDescription: String? {
        switch self {
        case .unsupported: "Format bukti belum dapat dibaca. Bagikan gambar, PDF, atau teks transaksi."
        case .unavailable: "Aplikasi pengirim belum menyediakan isi bukti. Coba baca ulang, atau simpan bukti ke Foto/Files lalu bagikan dari sana."
        case .timeout: "Aplikasi pengirim terlalu lama menyiapkan bukti. Coba baca ulang."
        case .noProof: "Kiriman hanya berisi tautan atau keterangan kosong. Bagikan gambar/PDF bukti atau teks transaksi; tautan bank tidak dibuka otomatis."
        }
    }
}

struct ShareReadResult: Sendable {
    let payloads: [SharedPayload]
    let notes: [String]
}

@MainActor enum ShareItemReader {
    private enum Item: Sendable {
        case proof(SharedPayload, converted: Bool)
        case text(String)
        case link
        case empty
    }

    static func read(_ providers: [NSItemProvider], timeout: TimeInterval = 8) async throws -> ShareReadResult {
        guard !providers.isEmpty else { throw ShareReadError.unavailable }
        guard providers.count <= 10 else { throw SharedInboxError.tooLarge }
        var proofs: [SharedPayload] = []
        var texts: [String] = []
        var notes: Set<String> = []
        let deadline = Date().addingTimeInterval(30)
        for provider in providers {
            try Task.checkCancellation()
            let available = deadline.timeIntervalSinceNow
            guard available > 0 else { throw ShareReadError.timeout }
            switch try await read(provider, timeout: min(timeout, available)) {
            case let .proof(payload, converted):
                proofs.append(payload)
                if converted { notes.insert("Gambar dari aplikasi pengirim disalin sebagai JPEG agar dapat dibaca. Periksa dengan bukti asli di aplikasi bank.") }
            case let .text(text): texts.append(text)
            case .link: notes.insert("Tautan pendamping tidak dibuka. Hanya bukti transaksi yang disimpan.")
            case .empty: break
            }
        }
        let context = texts.joined(separator: "\n\n")
        guard context.utf8.count <= SharedInbox.maximumTextBytes, proofs.count <= 5 else { throw SharedInboxError.tooLarge }
        if proofs.isEmpty {
            guard !context.isEmpty else { throw ShareReadError.noProof }
            return ShareReadResult(payloads: [try SharedPayload.text(context)], notes: notes.sorted())
        }
        return ShareReadResult(payloads: proofs.map { SharedPayload(name: $0.name, data: $0.data, context: context) }, notes: notes.sorted())
    }

    private static func read(_ provider: NSItemProvider, timeout: TimeInterval) async throws -> Item {
        let identifiers = provider.registeredTypeIdentifiers
        let name = provider.suggestedName ?? "Bukti transaksi"
        let binary = identifiers.filter { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .pdf)
        }.sorted { rank($0) < rank($1) }
        var failures: [Error] = []
        let deadline = Date().addingTimeInterval(timeout)
        func attemptTimeout() throws -> TimeInterval {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw ShareReadError.timeout }
            return min(max(timeout / 3, 0.01), remaining)
        }
        // Try every advertised image/PDF representation, not just the first generic UTI.
        for type in binary {
            do { return try await file(provider, type: type, name: name, timeout: attemptTimeout()) }
            catch { try fatal(error); failures.append(error) }
            do { return try await data(provider, type: type, name: name, binaryOnly: true, timeout: attemptTimeout()) }
            catch { try fatal(error); failures.append(error) }
        }
        if provider.canLoadObject(ofClass: UIImage.self) {
            do { return try await image(provider, name: name, timeout: attemptTimeout()) }
            catch { try fatal(error); failures.append(error) }
        }
        for type in binary {
            do { return try await item(provider, type: type, name: name, binaryOnly: true, timeout: attemptTimeout()) }
            catch { try fatal(error); failures.append(error) }
        }
        // Some exporters advertise only file-url/data. Validate the actual bytes locally.
        for type in identifiers where UTType(type)?.conforms(to: .url) == true {
            do { return try await item(provider, type: type, name: name, binaryOnly: !binary.isEmpty, timeout: attemptTimeout()) }
            catch { try fatal(error); failures.append(error) }
        }
        if provider.canLoadObject(ofClass: NSURL.self) {
            do { return try await urlObject(provider, name: name, binaryOnly: !binary.isEmpty, timeout: attemptTimeout()) }
            catch { try fatal(error); failures.append(error) }
        }
        if binary.isEmpty {
            for type in identifiers where UTType(type)?.conforms(to: .text) == true {
                do { return try await item(provider, type: type, name: name, binaryOnly: false, timeout: attemptTimeout()) }
                catch { try fatal(error); failures.append(error) }
            }
            for type in identifiers where type == UTType.data.identifier || type == UTType.content.identifier {
                do { return try await data(provider, type: type, name: name, binaryOnly: false, timeout: attemptTimeout()) }
                catch { try fatal(error); failures.append(error) }
                do { return try await item(provider, type: type, name: name, binaryOnly: false, timeout: attemptTimeout()) }
                catch { try fatal(error); failures.append(error) }
            }
        }
        if failures.contains(where: { ($0 as? ShareReadError) == .timeout }) { throw ShareReadError.timeout }
        throw failures.isEmpty ? ShareReadError.unsupported : ShareReadError.unavailable
    }

    private static func rank(_ type: String) -> Int {
        if type == UTType.image.identifier { return 2 }
        return UTType(type)?.conforms(to: .pdf) == true ? 0 : 1
    }
    private static func fatal(_ error: Error) throws {
        if error is CancellationError { throw error }
        if case SharedInboxError.tooLarge = error { throw error }
    }

    private static func file(_ provider: NSItemProvider, type: String, name: String, timeout: TimeInterval) async throws -> Item {
        try await load(timeout: timeout) { gate in
            let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                gate.resolve {
                    guard let url else { throw error ?? ShareReadError.unavailable }
                    // The temporary provider URL is valid only inside this callback.
                    return try fromURL(url, name: name, binaryOnly: true)
                }
            }
            gate.setProgress(progress)
        }
    }
    private static func data(_ provider: NSItemProvider, type: String, name: String, binaryOnly: Bool, timeout: TimeInterval) async throws -> Item {
        try await load(timeout: timeout) { gate in
            let progress = provider.loadDataRepresentation(forTypeIdentifier: type) { bytes, error in
                gate.resolve {
                    guard let bytes else { throw error ?? ShareReadError.unavailable }
                    return try fromData(bytes, name: name, binaryOnly: binaryOnly)
                }
            }
            gate.setProgress(progress)
        }
    }
    private static func image(_ provider: NSItemProvider, name: String, timeout: TimeInterval) async throws -> Item {
        try await load(timeout: timeout) { gate in
            let progress = provider.loadObject(ofClass: UIImage.self) { object, error in
                gate.resolve {
                    guard let image = object as? UIImage else { throw error ?? ShareReadError.unavailable }
                    return try fromImage(image, name: name)
                }
            }
            gate.setProgress(progress)
        }
    }
    private static func item(_ provider: NSItemProvider, type: String, name: String, binaryOnly: Bool, timeout: TimeInterval) async throws -> Item {
        try await load(timeout: timeout) { gate in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                gate.resolve {
                    if let image = value as? UIImage { return try fromImage(image, name: name) }
                    if let url = value as? URL { return try fromURL(url, name: name, binaryOnly: binaryOnly) }
                    if let bytes = value as? Data {
                        if UTType(type)?.conforms(to: .url) == true, let text = String(data: bytes, encoding: .utf8), let url = URL(string: text) {
                            return try fromURL(url, name: name, binaryOnly: binaryOnly)
                        }
                        return try fromData(bytes, name: name, binaryOnly: binaryOnly)
                    }
                    if let text = value as? String {
                        if let url = URL(string: text), url.isFileURL { return try fromURL(url, name: name, binaryOnly: binaryOnly) }
                        if binaryOnly { throw ShareReadError.unsupported }
                        return try fromText(text)
                    }
                    if !binaryOnly, let attributed = value as? NSAttributedString { return try fromText(attributed.string) }
                    throw error ?? ShareReadError.unsupported
                }
            }
        }
    }

    private static func urlObject(_ provider: NSItemProvider, name: String, binaryOnly: Bool, timeout: TimeInterval) async throws -> Item {
        try await load(timeout: timeout) { gate in
            let progress = provider.loadObject(ofClass: NSURL.self) { object, error in
                gate.resolve {
                    guard let url = object as? NSURL else { throw error ?? ShareReadError.unavailable }
                    return try fromURL(url as URL, name: name, binaryOnly: binaryOnly)
                }
            }
            gate.setProgress(progress)
        }
    }

    nonisolated private static func fromURL(_ url: URL, name: String, binaryOnly: Bool) throws -> Item {
        guard url.isFileURL else {
            if binaryOnly { throw ShareReadError.unsupported }
            return .link
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else { throw ShareReadError.unavailable }
        guard size <= SharedInbox.maximumFileBytes else { throw SharedInboxError.tooLarge }
        return try fromData(Data(contentsOf: url), name: name == "Bukti transaksi" ? url.lastPathComponent : name, binaryOnly: binaryOnly)
    }
    nonisolated private static func fromData(_ bytes: Data, name: String, binaryOnly: Bool) throws -> Item {
        guard bytes.count <= SharedInbox.maximumFileBytes else { throw SharedInboxError.tooLarge }
        guard !bytes.isEmpty else { throw ShareReadError.unavailable }
        if let mime = SharedPayload.mime(bytes), mime != "text/plain" {
            return .proof(SharedPayload(name: name, data: bytes, context: ""), converted: false)
        }
        if let source = CGImageSourceCreateWithData(bytes as CFData, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
            return try fromImage(UIImage(cgImage: image), name: name)
        }
        if !binaryOnly, let text = String(data: bytes, encoding: .utf8) { return try fromText(text) }
        throw ShareReadError.unsupported
    }
    nonisolated private static func fromImage(_ image: UIImage, name: String) throws -> Item {
        let width = image.cgImage?.width ?? Int(image.size.width * image.scale)
        let height = image.cgImage?.height ?? Int(image.size.height * image.scale)
        guard width > 0, height > 0, width <= 8000, height <= 8000, width * height <= 16_000_000 else { throw SharedInboxError.tooLarge }
        for quality in [0.9, 0.7, 0.5] {
            if let bytes = image.jpegData(compressionQuality: quality), bytes.count <= SharedInbox.maximumFileBytes {
                return .proof(SharedPayload(name: (name as NSString).deletingPathExtension + ".jpg", data: bytes, context: ""), converted: true)
            }
        }
        throw SharedInboxError.tooLarge
    }
    nonisolated private static func fromText(_ value: String) throws -> Item {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= SharedInbox.maximumTextBytes else { throw SharedInboxError.tooLarge }
        guard !text.isEmpty else { return .empty }
        if text.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://\S+$"#, options: .regularExpression) != nil { return .link }
        guard !text.contains("\0") else { throw ShareReadError.unsupported }
        return .text(text)
    }

    private static func load<T: Sendable>(timeout: TimeInterval, start: @MainActor (ShareCallback<T>) -> Void) async throws -> T {
        let gate = ShareCallback<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                start(gate)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { gate.finish(.failure(ShareReadError.timeout), cancel: true) }
            }
        } onCancel: { gate.finish(.failure(CancellationError()), cancel: true) }
    }
}

// Cancellation/timeout and late provider callbacks must resume the continuation exactly once.
private final class ShareCallback<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var result: Result<T, Error>?
    private var progress: Progress?
    private var finished = false
    func install(_ value: CheckedContinuation<T, Error>) {
        lock.lock()
        if let result { lock.unlock(); value.resume(with: result) }
        else { continuation = value; lock.unlock() }
    }
    func setProgress(_ value: Progress) {
        lock.lock(); let cancel = finished; if !cancel { progress = value }; lock.unlock()
        if cancel { value.cancel() }
    }
    func resolve(_ operation: () throws -> T) {
        lock.lock(); let ignored = finished; lock.unlock()
        if !ignored { finish(Result(catching: operation)) }
    }
    func finish(_ value: Result<T, Error>, cancel: Bool = false) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let callback = continuation; continuation = nil
        if callback == nil { result = value }
        let task = progress; progress = nil
        lock.unlock()
        if cancel { task?.cancel() }
        callback?.resume(with: value)
    }
}
