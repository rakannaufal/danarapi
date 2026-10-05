import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Danarapi

@MainActor final class ShareItemReaderTests: XCTestCase {
    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            ("BSI TEST" as NSString).draw(at: CGPoint(x: 10, y: 10), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
    }
    func testDataOnlyImageFallbackDoesNotNeedTemporaryFile() async throws {
        let provider = DataOnlyBankProvider(data: try XCTUnwrap(image().pngData()), identifiers: [UTType.image.identifier])
        let result = try await ShareItemReader.read([provider])
        XCTAssertEqual(result.payloads.first?.mime, "image/png")
        XCTAssertEqual(result.payloads.first?.data, provider.bytes)
        XCTAssertEqual(provider.fileAttempts, 1)
    }
    func testNativeUIImageShareBecomesReadableProof() async throws {
        let provider = NSItemProvider(object: image())
        let result = try await ShareItemReader.read([provider])
        let data = try XCTUnwrap(result.payloads.first?.data)
        XCTAssertNotNil(UIImage(data: data))
        XCTAssertTrue(result.payloads.first?.mime?.hasPrefix("image/") == true)
    }
    func testLegacyUIImageFallbackWithUnavailableFileAndData() async throws {
        let provider = LegacyBankProvider(image: image())
        let result = try await ShareItemReader.read([provider])
        XCTAssertEqual(result.payloads.first?.mime, "image/jpeg")
        XCTAssertTrue(result.notes.contains { $0.contains("JPEG") })
        XCTAssertNotNil(UIImage(data: try XCTUnwrap(result.payloads.first?.data)))
    }
    func testGenericDataContainsImageRatherThanText() async throws {
        let provider = DataOnlyBankProvider(data: try XCTUnwrap(image().pngData()), identifiers: [UTType.data.identifier])
        let result = try await ShareItemReader.read([provider])
        XCTAssertEqual(result.payloads.first?.mime, "image/png")
    }
    func testUnsupportedImageEncodingConvertedToJPEG() async throws {
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image().cgImage), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try await ShareItemReader.read([DataOnlyBankProvider(data: bytes as Data, identifiers: [UTType.tiff.identifier])])
        XCTAssertEqual(result.payloads.first?.mime, "image/jpeg")
        XCTAssertTrue(result.notes.contains { $0.contains("JPEG") })
    }
    func testImageWithLinkAndTextDoesNotRejectEntireShareOrFetchURL() async throws {
        let imageProvider = DataOnlyBankProvider(data: try XCTUnwrap(image().pngData()), identifiers: [UTType.png.identifier])
        let link = NSItemProvider(object: NSURL(string: "https://bank.example.invalid/private")!)
        let text = NSItemProvider(object: "Bukti transfer bank" as NSString)
        let result = try await ShareItemReader.read([imageProvider, link, text])
        XCTAssertEqual(result.payloads.count, 1)
        XCTAssertEqual(result.payloads[0].context, "Bukti transfer bank")
        XCTAssertFalse(result.payloads[0].context.contains("https://"))
        XCTAssertTrue(result.notes.contains { $0.contains("Tautan") })
    }
    func testEmptyCompanionCaptionDoesNotDiscardImage() async throws {
        let provider = DataOnlyBankProvider(data: try XCTUnwrap(image().pngData()), identifiers: [UTType.png.identifier])
        let result = try await ShareItemReader.read([provider, NSItemProvider(object: "  \n " as NSString)])
        XCTAssertEqual(result.payloads.count, 1)
        XCTAssertTrue(result.payloads[0].context.isEmpty)
    }
    func testFileURLWithWrongExtensionUsesActualContent() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try image().pngData()?.write(to: url)
        let result = try await ShareItemReader.read([NSItemProvider(object: url as NSURL)])
        XCTAssertEqual(result.payloads.first?.mime, "image/png")
    }
    func testMultipleRepresentationsFallbackToOtherAdvertisedType() async throws {
        let provider = DataOnlyBankProvider(data: try XCTUnwrap(image().pngData()), identifiers: [UTType.pdf.identifier, UTType.png.identifier], brokenTypes: [UTType.pdf.identifier])
        let result = try await ShareItemReader.read([provider])
        XCTAssertEqual(result.payloads.first?.mime, "image/png")
    }
    func testLinkOnlyRejectedWithSpecificGuidance() async throws {
        do {
            _ = try await ShareItemReader.read([NSItemProvider(object: NSURL(string: "https://bank.example.invalid/proof")!)])
            XCTFail("Link-only accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("hanya berisi tautan")) }
    }
    func testOversizedRepresentationDoesNotFallbackToCaption() async throws {
        let provider = DataOnlyBankProvider(data: Data(repeating: 1, count: SharedInbox.maximumFileBytes + 1), identifiers: [UTType.png.identifier])
        do {
            _ = try await ShareItemReader.read([provider, NSItemProvider(object: "Nominal Rp150000" as NSString)])
            XCTFail("Oversized accepted")
        } catch { XCTAssertTrue(error is SharedInboxError) }
    }
    func testAdvertisedImageCannotSilentlyBecomeCaptionOrRemoteLink() async throws {
        do {
            _ = try await ShareItemReader.read([DataOnlyBankProvider(data: Data("Bukti transfer".utf8), identifiers: [UTType.image.identifier])])
            XCTFail("Image became text")
        } catch { XCTAssertTrue(error is ShareReadError) }
    }
    func testProviderTimeoutDoesNotHangOnLateCallback() async throws {
        let provider = DataOnlyBankProvider(data: try XCTUnwrap(image().pngData()), identifiers: [UTType.png.identifier], delay: 0.1)
        do { _ = try await ShareItemReader.read([provider], timeout: 0.01); XCTFail("Timeout accepted") }
        catch { XCTAssertTrue(error is ShareReadError) }
        try await Task.sleep(for: .milliseconds(200))
    }
    func testCancellationStopsPendingProvider() async throws {
        let provider = DataOnlyBankProvider(data: try XCTUnwrap(image().pngData()), identifiers: [UTType.png.identifier], delay: 0.2)
        let task = Task { try await ShareItemReader.read([provider]) }
        await Task.yield(); task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled task completed") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await Task.sleep(for: .milliseconds(250))
    }
}

private final class DataOnlyBankProvider: NSItemProvider, @unchecked Sendable {
    let bytes: Data
    private let types: [String]
    private let brokenTypes: Set<String>
    private let delay: TimeInterval
    private(set) var fileAttempts = 0
    init(data: Data, identifiers: [String], brokenTypes: Set<String> = [], delay: TimeInterval = 0) {
        bytes = data; types = identifiers; self.brokenTypes = brokenTypes; self.delay = delay
        super.init()
    }
    override var registeredTypeIdentifiers: [String] { types }
    override func canLoadObject(ofClass aClass: any NSItemProviderReading.Type) -> Bool { false }
    override func loadFileRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping @Sendable (URL?, Error?) -> Void) -> Progress {
        fileAttempts += 1
        completionHandler(nil, NSError(domain: NSItemProvider.errorDomain, code: -1000))
        return Progress(totalUnitCount: 1)
    }
    override func loadDataRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping @Sendable (Data?, Error?) -> Void) -> Progress {
        let bytes = bytes; let broken = brokenTypes.contains(typeIdentifier)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { completionHandler(broken ? nil : bytes, broken ? NSError(domain: NSItemProvider.errorDomain, code: -1000) : nil) }
        return Progress(totalUnitCount: 1)
    }
    override func loadItem(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]? = nil, completionHandler: NSItemProvider.CompletionHandler? = nil) {
        completionHandler?(nil, NSError(domain: NSItemProvider.errorDomain, code: -1000))
    }
}

private final class LegacyBankProvider: NSItemProvider, @unchecked Sendable {
    let proof: UIImage
    init(image: UIImage) { proof = image; super.init() }
    override var registeredTypeIdentifiers: [String] { [UTType.image.identifier] }
    override func canLoadObject(ofClass aClass: any NSItemProviderReading.Type) -> Bool { false }
    override func loadFileRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping @Sendable (URL?, Error?) -> Void) -> Progress {
        completionHandler(nil, nil); return Progress(totalUnitCount: 1)
    }
    override func loadDataRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping @Sendable (Data?, Error?) -> Void) -> Progress {
        completionHandler(nil, nil); return Progress(totalUnitCount: 1)
    }
    override func loadItem(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]? = nil, completionHandler: NSItemProvider.CompletionHandler? = nil) {
        completionHandler?(proof, nil)
    }
}
