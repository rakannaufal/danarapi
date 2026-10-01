import Foundation
import LocalAuthentication

enum AppLockService {
    static var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static func unlock() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Batal"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Buka Danarapi untuk melihat catatan keuangan Anda.")
        } catch {
            return false
        }
    }
}
