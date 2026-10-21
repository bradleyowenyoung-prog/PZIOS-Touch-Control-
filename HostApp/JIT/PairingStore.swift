// The device pairing file is a credential for this iPhone, so it lives in the iOS Keychain (this device only, never in backups or Files),
// not in Documents. It is never logged. The JIT helper receives it as request data and writes only a temporary copy that it deletes at once.
import Foundation
import Security

enum PairingStore {
    private static let service = (Bundle.main.bundleIdentifier ?? "pziOS") + ".jit", account = "pairing"      // from the bundle id, so your own id gets its own keychain item

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load() -> Data? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func save(_ data: Data) -> Bool {
        SecItemDelete(base as CFDictionary)
        var q = base
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }


    static var exists: Bool { load() != nil }

    /// A pairing file left in Documents/StikJIT (copied in with Files or Finder, or by an older build) is moved into the Keychain and removed.
    static func migrateLegacyFile() {
        let url = GameFiles.documents.appendingPathComponent("StikJIT/pairingFile.plist")
        guard let data = try? Data(contentsOf: url), !data.isEmpty, save(data) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
