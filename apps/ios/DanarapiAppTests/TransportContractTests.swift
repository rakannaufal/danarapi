import Foundation
import XCTest
import UIKit
@testable import Danarapi

final class TransportContractTests: XCTestCase {
    @MainActor
    func testProviderBrandAssetsAreBundled() throws {
        let logo = try XCTUnwrap(UIImage(named: "GoogleSignInLogo"))
        XCTAssertEqual(logo.size.width, 20)
        XCTAssertEqual(logo.size.height, 20)
        XCTAssertNotNil(UIFont(name: "GoogleSans-Medium", size: 18))
        XCTAssertNotNil(Bundle.main.url(forResource: "Google-Sans-OFL", withExtension: "txt"))
    }

    func testBundledConfigurationUsesPublicCloudKey() throws {
        let configuration = try XCTUnwrap(SupabaseConfiguration.fromBundle())
        XCTAssertEqual(configuration.url.host, "zoccosfjulasqxczhvfm.supabase.co")
        XCTAssertEqual(configuration.url.scheme, "https")
        XCTAssertTrue(configuration.anonKey.hasPrefix("sb_publishable_"))
    }

    @MainActor
    func testOAuthAvailabilityUsesApikeyWithoutPublicKeyBearer() async throws {
        let store = KeychainSessionStore(service: "id.danarapi.tests.\(UUID().uuidString)")
        defer { store.clear() }
        let configuration = SupabaseConfiguration(url: try XCTUnwrap(URL(string: "https://example.invalid")), anonKey: "sb_publishable_test")
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [AuthStubProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        AuthStubProtocol.state.reset()
        let auth = AuthService(configuration: configuration, sessionStore: store, session: session)
        try await auth.ensureOAuthProvider("google")
        do {
            try await auth.ensureOAuthProvider("apple")
            XCTFail("Disabled provider accepted")
        } catch { XCTAssertTrue((error as? AppError)?.message.contains("Provider login tidak valid") == true) }
        XCTAssertEqual(AuthStubProtocol.state.requests.count, 1)
        do {
            _ = try await auth.oauthURL(provider: "apple", verifier: OAuthPKCE.verifier())
            XCTFail("Unsupported provider accepted")
        } catch { XCTAssertTrue((error as? AppError)?.message.contains("Konfigurasi login tidak valid") == true) }
        let request = try XCTUnwrap(AuthStubProtocol.state.requests.first)
        XCTAssertEqual(request.url?.path, "/auth/v1/settings")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(try store.load())
    }

    func testGrantTypeIsQueryNotEncodedPath() throws {
        let configuration = SupabaseConfiguration(url: try XCTUnwrap(URL(string: "https://example.invalid")), anonKey: "public-test-key")
        let url = try configuration.endpoint("/auth/v1/token?grant_type=password")
        XCTAssertEqual(url.path, "/auth/v1/token")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "grant_type", value: "password")])
        XCTAssertFalse(url.absoluteString.contains("%3F"))
        XCTAssertThrowsError(try configuration.endpoint("https://another.invalid/auth"))
    }

    func testFractionalServerDatesAndWholeSecondDates() throws {
        struct Value: Decodable { let date: Date }
        let decoder = JSONDecoder.danarapi
        let fractional = try decoder.decode(Value.self, from: Data(#"{"date":"2026-09-30T03:04:05.123456+00:00"}"#.utf8))
        let whole = try decoder.decode(Value.self, from: Data(#"{"date":"2026-09-30T03:04:05Z"}"#.utf8))
        XCTAssertEqual(fractional.date.timeIntervalSince(whole.date), 0.123, accuracy: 0.001)
        XCTAssertThrowsError(try decoder.decode(Value.self, from: Data(#"{"date":"30/09/2026"}"#.utf8)))
    }

    func testMoneyRequiresDecimalStringsAtJSONBoundary() throws {
        struct Value: Codable { @DecimalString var amount: Int64 }
        let value = try JSONDecoder().decode(Value.self, from: Data(#"{"amount":"-12500"}"#.utf8))
        XCTAssertEqual(value.amount, -12_500)
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(value), as: UTF8.self), #"{"amount":"-12500"}"#)
        for invalid in [#"{"amount":12500}"#, #"{"amount":"1.5"}"#, #"{"amount":"+5"}"#, #"{"amount":"00"}"#, #"{"amount":"-0"}"#, #"{"amount":"9223372036854775808"}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(Value.self, from: Data(invalid.utf8)))
        }
    }

    func testOptionalMoneyRejectsMalformedValuesInsteadOfSilentlyLosingAmount() throws {
        struct Value: Decodable { @OptionalDecimalString var amount: Int64? }
        XCTAssertNil(try JSONDecoder().decode(Value.self, from: Data(#"{"amount":null}"#.utf8)).amount)
        for invalid in [#"{"amount":12500}"#, #"{"amount":"invalid"}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(Value.self, from: Data(invalid.utf8)))
        }
    }

    @MainActor
    func testAuthTransportAndOwnerIsolation() async throws {
        let store = KeychainSessionStore(service: "id.danarapi.tests.\(UUID().uuidString)")
        defer { store.clear() }
        let configuration = SupabaseConfiguration(url: try XCTUnwrap(URL(string: "https://example.invalid")), anonKey: "public-test-key")
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [AuthStubProtocol.self]
        let urlSession = URLSession(configuration: sessionConfiguration)
        defer { urlSession.invalidateAndCancel() }
        let auth = AuthService(configuration: configuration, sessionStore: store, session: urlSession)
        AuthStubProtocol.state.reset()
        let original = AuthSession(accessToken: "original", refreshToken: "refresh-original", userID: "owner-a", email: "a@example.invalid", expiresAt: .distantFuture)
        try store.save(original)
        do {
            _ = try await auth.signIn(email: "b@example.invalid", password: "password-test", expectedUserID: "owner-a")
            XCTFail("Tidak boleh mengganti sesi ketika identitas berbeda")
        } catch {
            XCTAssertEqual(try store.load()?.userID, "owner-a")
            XCTAssertEqual(try store.load()?.accessToken, "original")
        }
        let request = try XCTUnwrap(AuthStubProtocol.state.requests.first)
        XCTAssertEqual(request.url?.path, "/auth/v1/token")
        XCTAssertEqual(request.url?.query, "grant_type=password")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "public-test-key")

        do {
            _ = try await auth.finishOAuth(callback: URL(string: "id.danarapi.app://auth/callback?code=test-code")!, verifier: String(repeating: "a", count: 43), expectedUserID: "owner-a")
            XCTFail("OAuth replaced another owner's session")
        } catch {
            XCTAssertEqual(try store.load()?.userID, "owner-a")
            XCTAssertEqual(try store.load()?.accessToken, "original")
        }
        XCTAssertEqual(AuthStubProtocol.state.requests.last?.url?.query, "grant_type=pkce")
        let previousRequests = AuthStubProtocol.state.requests.count
        do {
            _ = try await auth.finishOAuth(callback: URL(string: "https://hostile.invalid/callback?code=test-code")!, verifier: String(repeating: "a", count: 43))
            XCTFail("Foreign callback accepted")
        } catch {}
        XCTAssertEqual(AuthStubProtocol.state.requests.count, previousRequests)

        let recovery = try await auth.verifyRecovery(email: "b@example.invalid", code: "123456")
        XCTAssertEqual(recovery.userID, "owner-b")
        XCTAssertEqual(try store.load()?.userID, "owner-a")
        try await auth.resetPassword("new-password-test", recovery: recovery)
        let update = try XCTUnwrap(AuthStubProtocol.state.requests.last)
        XCTAssertEqual(update.httpMethod, "PUT")
        XCTAssertEqual(update.url?.path, "/auth/v1/user")
        XCTAssertEqual(update.value(forHTTPHeaderField: "Authorization"), "Bearer stub-access")
        XCTAssertEqual(try store.load()?.accessToken, "original")
    }

    func testBundledDesignTokensDecodeAllNativeValues() throws {
        let catalog = try XCTUnwrap(DesignTokenCatalog.bundled)
        XCTAssertEqual(catalog.version, DesignTokens.version)
        XCTAssertEqual(catalog.hex("primary", theme: "light"), 0x0066CC)
        XCTAssertEqual(catalog.hex("primary", theme: "dark"), 0x80BAFF)
        XCTAssertEqual(catalog.hex("on-primary", theme: "dark"), 0x101C30)
        XCTAssertEqual(catalog.radius["card"], 20)
        XCTAssertEqual(catalog.radius["button"], 12)
        XCTAssertEqual(catalog.radius["card"], Double(DesignTokens.cornerCard))
        XCTAssertEqual(catalog.layout["mobileGutter"], Double(DesignTokens.gutter))
        XCTAssertEqual(catalog.motion.normalMs / 1000, DesignTokens.motion)
        XCTAssertTrue(catalog.motion.respectsReducedMotion)
    }

    @MainActor
    func testOnlineLedgerRetryReusesUUIDUntilAcknowledgement() async throws {
        let store = KeychainSessionStore(service: "id.danarapi.tests.\(UUID().uuidString)")
        defer { store.clear() }
        try store.save(AuthSession(accessToken: "test-access", refreshToken: "test-refresh", userID: "owner-b", email: nil, expiresAt: .distantFuture))
        let configuration = SupabaseConfiguration(url: try XCTUnwrap(URL(string: "https://example.invalid")), anonKey: "public-test-key")
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [AuthStubProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let repository = RemoteRepository(configuration: configuration, sessionStore: store, session: session)
        AuthStubProtocol.state.reset()
        AuthStubProtocol.state.setLedgerStatuses([503, 200, 200])
        let draft = SettlementDraft(billID: "bill", memberID: "member", accountID: "cash", amount: 10_000, occurredAt: .now, note: nil)
        do { try await repository.recordSettlement(draft); XCTFail("Respons pertama harus gagal") }
        catch { XCTAssertEqual((error as? AppError)?.code, "INTERNAL") }
        try await repository.recordSettlement(draft)
        try await repository.recordSettlement(draft)
        let ids = try AuthStubProtocol.state.ledgerBodies.map { body -> String in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let payload = try XCTUnwrap(object["payload"] as? [String: Any])
            return try XCTUnwrap(payload["p_client_mutation_id"] as? String)
        }
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(ids[0], ids[1])
        XCTAssertNotEqual(ids[1], ids[2])
    }

    func testKeychainRefreshCannotResurrectLoggedOutSession() throws {
        let store = KeychainSessionStore(service: "id.danarapi.tests.\(UUID().uuidString)")
        defer { store.clear() }
        let original = AuthSession(accessToken: "original", refreshToken: "original-refresh", userID: "owner-a", email: nil, expiresAt: .now)
        let refreshed = AuthSession(accessToken: "refreshed", refreshToken: "refreshed-token", userID: "owner-a", email: nil, expiresAt: .distantFuture)
        try store.save(original)
        store.clear()
        XCTAssertThrowsError(try store.replace(refreshed, matching: original))
        XCTAssertNil(try store.load())
    }

    @MainActor
    func testCloudReceiptScanUsesAuthenticatedHTTPSWithoutLANPairing() async throws {
        let store = KeychainSessionStore(service: "id.danarapi.tests.\(UUID().uuidString)")
        defer { store.clear() }
        try store.save(AuthSession(accessToken: "test-access", refreshToken: "test-refresh", userID: "owner-b", email: nil, expiresAt: .distantFuture))
        let configuration = SupabaseConfiguration(url: try XCTUnwrap(URL(string: "https://example.invalid")), anonKey: "public-test-key")
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [AuthStubProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        AuthStubProtocol.state.reset()
        let repository = RemoteRepository(configuration: configuration, sessionStore: store, session: session)
        let response = try await repository.scanReceipt(images: [ReceiptScanImage(mimeType: "image/jpeg", data: "test-image")])
        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.data?.grandTotal, 50_000)
        let request = try XCTUnwrap(AuthStubProtocol.state.requests.first)
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "example.invalid")
        XCTAssertEqual(request.url?.path, "/functions/v1/receipt-scan")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "public-test-key")
        XCTAssertEqual(request.timeoutInterval, 110)
        XCTAssertNil(request.value(forHTTPHeaderField: "x-danarapi-native-scan"))
        XCTAssertEqual(AuthStubProtocol.state.requests.count, 1)
    }
}

private final class AuthStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedRequests: [URLRequest] = []
    private var capturedLedgerBodies: [Data] = []
    private var ledgerStatuses: [Int] = []

    var requests: [URLRequest] { lock.withLock { capturedRequests } }
    var ledgerBodies: [Data] { lock.withLock { capturedLedgerBodies } }
    func reset() { lock.withLock { capturedRequests = []; capturedLedgerBodies = []; ledgerStatuses = [] } }
    func record(_ request: URLRequest) { lock.withLock { capturedRequests.append(request) } }
    func setLedgerStatuses(_ statuses: [Int]) { lock.withLock { ledgerStatuses = statuses } }
    func ledgerResponse(body: Data) -> Int {
        lock.withLock {
            capturedLedgerBodies.append(body)
            return ledgerStatuses.isEmpty ? 200 : ledgerStatuses.removeFirst()
        }
    }
}

private final class AuthStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = AuthStubState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "example.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.record(request)
        var status = 200
        if request.url?.path == "/functions/v1/ledger" {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4_096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            status = Self.state.ledgerResponse(body: body)
        }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { return }
        let payload = request.url?.path == "/auth/v1/settings" ? #"{"external":{"google":true,"apple":false}}"# : request.url?.path == "/functions/v1/receipt-scan"
            ? #"{"status":"ok","data":{"merchant":"TOKO DEMO","date":"2025-06-29","items":[{"name":"Kopi","qty":2,"unit_price":25000,"line_total":50000}],"subtotal":50000,"service_charge":0,"tax":0,"discount":0,"rounding":0,"grand_total":50000,"tax_included_in_price":false,"unreadable_fields":[]}}"#
            : #"{"access_token":"stub-access","refresh_token":"stub-refresh","expires_in":3600,"user":{"id":"owner-b","email":"b@example.invalid"}}"#
        let data = Data(payload.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
