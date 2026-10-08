import Foundation
import Security

/// Small key/value secure storage used for the visitor token.
protocol SecureStore: AnyObject, Sendable {
    func string(for key: String) -> String?
    @discardableResult func set(_ value: String, for key: String) -> Bool
    @discardableResult func remove(_ key: String) -> Bool
}

/// Keychain-backed ``SecureStore``.
///
/// Items are generic passwords with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: readable after the first
/// unlock (so push handling in the background works), never synced to iCloud and never restored to another device.
final class KeychainStore: SecureStore, @unchecked Sendable {
    let service: String
    private let lock = NSLock()

    init(service: String = "net.letsbot.chat") {
        self.service = service
    }

    /// Last `OSStatus` returned by the Keychain (for diagnostics and tests).
    private(set) var lastStatus: OSStatus = errSecSuccess

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func string(for key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        lastStatus = status
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func set(_ value: String, for key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let data = Data(value.utf8)
        let query = baseQuery(key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        lastStatus = status
        return status == errSecSuccess
    }

    @discardableResult
    func remove(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        lastStatus = status
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// In-memory ``SecureStore`` (tests and previews).
final class MemoryStore: SecureStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    init(_ values: [String: String] = [:]) { self.values = values }

    func string(for key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    @discardableResult
    func set(_ value: String, for key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
        return true
    }

    @discardableResult
    func remove(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        values[key] = nil
        return true
    }
}
