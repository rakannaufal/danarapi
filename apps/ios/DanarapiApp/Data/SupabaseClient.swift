import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit

enum OAuthPKCE {
    static let scheme = "id.danarapi.app"
    static let redirect = "id.danarapi.app://auth/callback"
    static func verifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppError.validation("Login belum dapat dimulai.") }
        return base64URL(Data(bytes))
    }
    static func challenge(_ verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    private static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

@MainActor
protocol OAuthBrowserSession: AnyObject {
    var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)? { get set }
    func start() -> Bool
    func cancel()
}

extension ASWebAuthenticationSession: OAuthBrowserSession {}

@MainActor
final class OAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    typealias SessionFactory = (URL, String?, @escaping (URL?, Error?) -> Void) -> any OAuthBrowserSession
    private var session: (any OAuthBrowserSession)?
    private var anchor: UIWindow?
    private var continuation: CheckedContinuation<URL, Error>?
    private var attemptID: UUID?
    private var timeoutTask: Task<Void, Never>?
    private let timeout: Duration
    private let makeSession: SessionFactory

    init(timeout: Duration = .seconds(120), makeSession: @escaping SessionFactory = { url, scheme, callback in ASWebAuthenticationSession(url: url, callbackURLScheme: scheme, completionHandler: callback) }) {
        self.timeout = timeout
        self.makeSession = makeSession
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor ?? UIWindow() }
    func authenticate(url: URL, presentationWindow: UIWindow? = nil) async throws -> URL {
        try Task.checkCancellation()
        guard session == nil, let window = presentationWindow ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })?.windows.first(where: \.isKeyWindow) else { throw AppError.validation("Login belum dapat dibuka. Tutup dialog lalu coba lagi.") }
        let identifier = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.anchor = window
                self.continuation = continuation
                self.attemptID = identifier
                let browser = makeSession(url, OAuthPKCE.scheme) { [weak self] callback, error in
                    Task { @MainActor [weak self] in
                        if let callback { self?.complete(identifier: identifier, result: .success(callback)) }
                        else if let failure = error as? ASWebAuthenticationSessionError, failure.code == .canceledLogin { self?.complete(identifier: identifier, result: .failure(CancellationError())) }
                        else { self?.complete(identifier: identifier, result: .failure(AppError.validation("Login belum berhasil. Silakan coba kembali."))) }
                    }
                }
                browser.presentationContextProvider = self
                session = browser
                timeoutTask = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.complete(identifier: identifier, result: .failure(AppError(code: "TIMEOUT", message: "Login melewati batas waktu. Silakan coba kembali.", requestID: nil, details: [:])))
                }
                if !browser.start() { complete(identifier: identifier, result: .failure(AppError.validation("Login belum dapat dimulai. Silakan coba kembali."))) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.complete(identifier: identifier, result: .failure(CancellationError())) }
        }
    }

    func cancel() {
        guard let attemptID else { return }
        complete(identifier: attemptID, result: .failure(CancellationError()))
    }

    private func complete(identifier: UUID, result: Result<URL, Error>) {
        guard attemptID == identifier, let continuation else { return }
        let browser = session
        self.continuation = nil
        attemptID = nil
        session = nil
        anchor = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        browser?.cancel()
        continuation.resume(with: result)
    }
}

struct SupabaseConfiguration: Sendable {
    let url: URL
    let anonKey: String

    func endpoint(_ path: String) throws -> URL {
        guard let relative = URLComponents(string: path),
              relative.scheme == nil, relative.host == nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw AppError.validation("Alamat backend tidak valid.") }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [components.path, relative.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))].filter { !$0.isEmpty }.joined(separator: "/")
        components.percentEncodedQuery = relative.percentEncodedQuery
        guard let result = components.url else { throw AppError.validation("Alamat backend tidak valid.") }
        return result
    }

    static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfiguration? {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: rawURL), url.scheme == "https", url.host != nil,
              let anonKey = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !anonKey.isEmpty, !anonKey.hasPrefix("replace-"), !anonKey.hasPrefix("sb_secret_")
        else { return nil }
        return SupabaseConfiguration(url: url, anonKey: anonKey)
    }
}

actor SupabaseHTTPClient {
    private let configuration: SupabaseConfiguration
    private let sessionStore: KeychainSessionStore
    private let session: URLSession
    private var refreshTask: Task<AuthSession, Error>?

    init(configuration: SupabaseConfiguration, sessionStore: KeychainSessionStore, session: URLSession = .shared) {
        self.configuration = configuration
        self.sessionStore = sessionStore
        self.session = session
    }

    func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String = "POST",
        body: Body?,
        authenticated: Bool = true,
        decoder: JSONDecoder = .danarapi,
        timeout: TimeInterval = 30
    ) async throws -> Response {
        var request = URLRequest(url: try configuration.endpoint(path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            let token = try await accessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONEncoder.danarapi.encode(body) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError(code: "INTERNAL", message: "Respons server tidak valid.", requestID: nil, details: [:]) }
        guard (200..<300).contains(http.statusCode) else { throw decodeError(data: data, status: http.statusCode) }
        return try decoder.decode(Response.self, from: data)
    }

    func requestWithoutResponse<Body: Encodable>(path: String, method: String = "POST", body: Body?, authenticated: Bool = true) async throws {
        let _: EmptyResponse = try await request(path: path, method: method, body: body, authenticated: authenticated)
    }

    func data(
        path: String,
        method: String = "POST",
        body: Data? = nil,
        authenticated: Bool = true,
        contentType: String = "application/json",
        headers: [String: String] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: try configuration.endpoint(path))
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if authenticated {
            let token = try await accessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw decodeError(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        return data
    }

    private func accessToken() async throws -> String {
        guard let current = try sessionStore.load() else { throw AppError(code: "UNAUTHORIZED", message: "Sesi telah berakhir.", requestID: nil, details: [:]) }
        guard current.expiresAt <= Date().addingTimeInterval(60) else { return current.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task { [configuration, sessionStore, session] in
            var request = URLRequest(url: try configuration.endpoint("/auth/v1/token?grant_type=refresh_token"))
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["refresh_token": current.refreshToken])
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 500 || http.statusCode == 429 {
                throw AppError(code: http.statusCode == 429 ? "QUOTA_EXCEEDED" : "INTERNAL", message: "Penyegaran sesi belum tersedia. Coba lagi nanti.", requestID: nil, details: [:])
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let envelope = try? JSONDecoder().decode(AuthEnvelope.self, from: data),
                  let access = envelope.accessToken, let refresh = envelope.refreshToken,
                  envelope.user?.id == current.userID,
                  let stored = try sessionStore.load(), stored.userID == current.userID, stored.refreshToken == current.refreshToken
            else { throw AppError(code: "UNAUTHORIZED", message: "Sesi telah berakhir. Masuk kembali dengan akun yang sama untuk melanjutkan perubahan perangkat.", requestID: nil, details: [:]) }
            let updated = AuthSession(accessToken: access, refreshToken: refresh, userID: current.userID, email: envelope.user?.email ?? current.email, expiresAt: Date().addingTimeInterval(TimeInterval(envelope.expiresIn ?? 3600)))
            try sessionStore.replace(updated, matching: current)
            return updated
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value.accessToken
    }

    private func decodeError(data: Data, status: Int) -> AppError {
        if status == 404,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["code"] as? String == "NOT_FOUND" {
            return AppError(code: "CLOUD_UNAVAILABLE", message: "Layanan cloud belum tersedia. Hubungi pengelola aplikasi.", requestID: nil, details: [:])
        }
        if let error = try? JSONDecoder().decode(AppError.self, from: data) { return error }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String {
            if let nested = message.data(using: .utf8), let error = try? JSONDecoder().decode(AppError.self, from: nested) { return error }
            return AppError(code: status == 401 ? "UNAUTHORIZED" : "INTERNAL", message: message, requestID: nil, details: [:])
        }
        return AppError(code: status == 401 ? "UNAUTHORIZED" : "INTERNAL", message: "Server tidak dapat memproses permintaan.", requestID: nil, details: [:])
    }
}

private struct EmptyResponse: Decodable {}

actor AuthService {
    private let configuration: SupabaseConfiguration
    private let sessionStore: KeychainSessionStore
    private let session: URLSession

    init(configuration: SupabaseConfiguration, sessionStore: KeychainSessionStore, session: URLSession = .shared) {
        self.configuration = configuration
        self.sessionStore = sessionStore
        self.session = session
    }

    func ensureOAuthProvider(_ provider: String) async throws {
        guard provider == "google" else { throw AppError.validation("Provider login tidak valid.") }
        var request = URLRequest(url: try configuration.endpoint("/auth/v1/settings"))
        request.timeoutInterval = 15
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AppError.validation("Layanan login belum tersedia. Coba lagi nanti.") }
        struct Settings: Decodable { let external: [String: Bool] }
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        guard settings.external[provider] == true else { throw AppError.validation("Login Google belum diaktifkan. Hubungi pengelola aplikasi.") }
    }

    func oauthURL(provider: String, verifier: String) throws -> URL {
        guard provider == "google", verifier.count >= 43, configuration.url.scheme == "https", var components = URLComponents(url: try configuration.endpoint("/auth/v1/authorize"), resolvingAgainstBaseURL: false) else { throw AppError.validation("Konfigurasi login tidak valid.") }
        components.queryItems = [URLQueryItem(name: "provider", value: provider), URLQueryItem(name: "redirect_to", value: OAuthPKCE.redirect), URLQueryItem(name: "code_challenge", value: OAuthPKCE.challenge(verifier)), URLQueryItem(name: "code_challenge_method", value: "s256"), URLQueryItem(name: "prompt", value: "select_account")]
        guard let url = components.url else { throw AppError.validation("Alamat login tidak valid.") }
        return url
    }

    func finishOAuth(callback: URL, verifier: String, expectedUserID: String? = nil) async throws -> AuthSession {
        guard callback.scheme == OAuthPKCE.scheme, callback.host == "auth", callback.path == "/callback", let components = URLComponents(url: callback, resolvingAgainstBaseURL: false), !(components.queryItems ?? []).contains(where: { $0.name == "error" || $0.name == "error_description" }), let code = components.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw AppError.validation("Respons login tidak valid.") }
        let envelope: AuthEnvelope = try await authRequest(path: "/auth/v1/token?grant_type=pkce", body: ["auth_code": code, "code_verifier": verifier])
        let value = try authSession(envelope: envelope, fallbackEmail: nil)
        guard expectedUserID == nil || value.userID == expectedUserID else { throw AppError.validation("Masuk kembali dengan akun yang sama agar perubahan perangkat tidak berpindah pemilik.") }
        try Task.checkCancellation()
        try sessionStore.save(value)
        return value
    }

    func signIn(email: String, password: String, expectedUserID: String? = nil) async throws -> AuthSession {
        let envelope: AuthEnvelope = try await authRequest(path: "/auth/v1/token?grant_type=password", body: ["email": email, "password": password])
        let value = try authSession(envelope: envelope, fallbackEmail: email)
        guard expectedUserID == nil || value.userID == expectedUserID else {
            throw AppError.validation("Masuk kembali dengan akun yang sama agar perubahan perangkat tidak berpindah pemilik.")
        }
        try sessionStore.save(value)
        return value
    }

    func signUp(email: String, password: String) async throws {
        let _: AuthEnvelope = try await authRequest(path: "/auth/v1/signup", body: ["email": email, "password": password])
    }

    func verify(email: String, code: String) async throws -> AuthSession {
        let envelope: AuthEnvelope = try await authRequest(path: "/auth/v1/verify", body: ["email": email, "token": code, "type": "signup"])
        return try store(envelope: envelope, fallbackEmail: email)
    }

    func requestPasswordReset(email: String) async throws {
        let _: GenericAuthResponse = try await authRequest(path: "/auth/v1/recover", body: ["email": email])
    }

    func resendVerification(email: String) async throws {
        let _: GenericAuthResponse = try await authRequest(path: "/auth/v1/resend", body: ["email": email, "type": "signup"])
    }

    func verifyRecovery(email: String, code: String) async throws -> AuthSession {
        let envelope: AuthEnvelope = try await authRequest(path: "/auth/v1/verify", body: ["email": email, "token": code, "type": "recovery"])
        return try authSession(envelope: envelope, fallbackEmail: email)
    }

    func resetPassword(_ password: String, recovery: AuthSession) async throws {
        guard password.count >= 8 else { throw AppError.validation("Kata sandi minimal 8 karakter.") }
        var request = URLRequest(url: try configuration.endpoint("/auth/v1/user"))
        request.httpMethod = "PUT"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(recovery.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["password": password])
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.validation("Kata sandi belum diubah. Periksa syarat kata sandi atau minta kode pemulihan baru.")
        }
    }

    func refresh() async throws -> AuthSession {
        guard let current = try sessionStore.load() else { throw AppError(code: "UNAUTHORIZED", message: "Tidak ada sesi.", requestID: nil, details: [:]) }
        let envelope: AuthEnvelope = try await authRequest(path: "/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": current.refreshToken])
        let value = try authSession(envelope: envelope, fallbackEmail: current.email)
        try sessionStore.replace(value, matching: current)
        return value
    }

    func signOut() async throws {
        guard let current = try sessionStore.load() else { return }
        var request = URLRequest(url: try configuration.endpoint("/auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await session.data(for: request)
        sessionStore.clear()
    }

    private func authRequest<Response: Decodable>(path: String, body: [String: String]) async throws -> Response {
        var request = URLRequest(url: try configuration.endpoint(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AppError(code: (response as? HTTPURLResponse)?.statusCode == 429 ? "QUOTA_EXCEEDED" : "UNAUTHORIZED", message: object?["msg"] as? String ?? object?["message"] as? String ?? "Autentikasi gagal.", requestID: nil, details: [:])
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func store(envelope: AuthEnvelope, fallbackEmail: String?) throws -> AuthSession {
        let value = try authSession(envelope: envelope, fallbackEmail: fallbackEmail)
        try sessionStore.save(value)
        return value
    }

    private func authSession(envelope: AuthEnvelope, fallbackEmail: String?) throws -> AuthSession {
        guard let accessToken = envelope.accessToken, let refreshToken = envelope.refreshToken, let user = envelope.user else {
            throw AppError(code: "UNAUTHORIZED", message: "Verifikasi akun belum selesai.", requestID: nil, details: [:])
        }
        let value = AuthSession(accessToken: accessToken, refreshToken: refreshToken, userID: user.id, email: user.email ?? fallbackEmail, expiresAt: Date().addingTimeInterval(TimeInterval(envelope.expiresIn ?? 3600)))
        return value
    }
}

private struct AuthEnvelope: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: AuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct AuthUser: Decodable {
    let id: String
    let email: String?
}

private struct GenericAuthResponse: Decodable {}
