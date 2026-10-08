import Security
import XCTest
@testable import LetsBotChat

final class KeychainStoreTests: XCTestCase {
    func testRoundTripWithThisDeviceOnlyAccessibility() throws {
        let store = KeychainStore(service: "net.letsbot.chat.tests.\(UUID().uuidString)")
        let key = "visitor.test"
        guard store.set("value-1", for: key) else {
            // Hostless SPM test bundles on some simulators lack a keychain entitlement.
            throw XCTSkip("Keychain unavailable in this test host (OSStatus \(store.lastStatus))")
        }
        XCTAssertEqual(store.string(for: key), "value-1")
        XCTAssertTrue(store.set("value-2", for: key), "update in place")
        XCTAssertEqual(store.string(for: key), "value-2")

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecAttrService as String] = store.service
        var result: AnyObject?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)

        XCTAssertTrue(store.remove(key))
        XCTAssertNil(store.string(for: key))
        XCTAssertTrue(store.remove(key), "removing a missing item is fine")
    }
}
