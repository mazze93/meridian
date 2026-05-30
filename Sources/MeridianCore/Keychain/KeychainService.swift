import Foundation
import CryptoKit
import Security

/// Errors surfaced by Keychain operations. Distinct cases so callers can distinguish
/// recoverable conditions (e.g. first-launch creation) from genuine failures.
public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case randomBytesUnavailable
    case malformedStoredKey
}

/// Owns the 256-bit symmetric key used by `EncryptedStore` for at-rest encryption (D2-11).
/// Key is generated on first use via `SecRandomCopyBytes` and stored in the Keychain with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so it (a) survives reboots, (b) is
/// available to background sync after the first user unlock, and (c) never escrows to
/// iCloud Keychain.
public struct KeychainService {

    public static let defaultService = "com.meridian.localstore.v1"
    public static let localStoreKeyAccount = "store-key"

    public let service: String

    public init(service: String = KeychainService.defaultService) {
        self.service = service
    }

    /// Idempotent: returns the existing key if present, otherwise generates + stores one.
    public func fetchOrCreateLocalStoreKey() throws -> SymmetricKey {
        if let existing = try fetchLocalStoreKey() { return existing }
        let fresh = try Self.generateSymmetricKey()
        try storeLocalStoreKey(fresh)
        return fresh
    }

    /// Returns `nil` (not an error) when no key is stored — that's a valid first-launch state.
    public func fetchLocalStoreKey() throws -> SymmetricKey? {
        let query = baseQuery().merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ], uniquingKeysWith: { _, new in new })
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else { throw KeychainError.malformedStoredKey }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes the stored key. Intended for tests and a future user-initiated "reset" flow.
    public func deleteLocalStoreKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Internals

    private func storeLocalStoreKey(_ key: SymmetricKey) throws {
        let raw = key.withUnsafeBytes { Data($0) }
        let attributes = baseQuery().merging([
            kSecValueData as String: raw,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ], uniquingKeysWith: { _, new in new })
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.localStoreKeyAccount,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private static func generateSymmetricKey() throws -> SymmetricKey {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }
        guard status == errSecSuccess else { throw KeychainError.randomBytesUnavailable }
        return SymmetricKey(data: Data(bytes))
    }
}
