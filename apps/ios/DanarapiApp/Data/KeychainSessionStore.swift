import Foundation
import Security

final class KeychainSessionStore: @unchecked Sendable {
    private let service: String
    private let account = "supabase-session-v1"
    private let lock = NSRecursiveLock()

    init(service: String = "id.danarapi.session") { self.service = service }

    func save(_ session: AuthSession) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AppError(code: "INTERNAL", message: "Sesi tidak dapat diperbarui dengan aman.", requestID: nil, details: [:])
        }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppError(code: "INTERNAL", message: "Sesi tidak dapat disimpan dengan aman.", requestID: nil, details: [:]) }
    }

    func load() throws -> AuthSession? {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AppError(code: "INTERNAL", message: "Sesi aman tidak dapat dibaca.", requestID: nil, details: [:]) }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    func replace(_ session: AuthSession, matching current: AuthSession) throws {
        lock.lock()
        defer { lock.unlock() }
        guard session.userID == current.userID, let stored = try load(), stored.userID == current.userID, stored.refreshToken == current.refreshToken else {
            throw AppError(code: "UNAUTHORIZED", message: "Sesi akun berubah. Masuk kembali untuk melanjutkan.", requestID: nil, details: [:])
        }
        try save(session)
    }
}
