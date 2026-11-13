import Foundation
import Security

protocol CloudTokenStore: Sendable {
    func read() throws -> String?
    func save(_ token: String) throws
    func remove() throws
}

struct CloudKeychain: CloudTokenStore {
    let service: String
    init(service: String = "com.hdd290187.qingread.cloud") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "readOnlyDevice", kSecAttrSynchronizable as String: false]
    }
    func read() throws -> String? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw storageError(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw CloudError.keychain }
        return value
    }
    func save(_ token: String) throws {
        let values: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw storageError(added) }
        } else if status != errSecSuccess { throw storageError(status) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw storageError(status) }
    }
    private func storageError(_ status: OSStatus) -> Error { NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
}

#if DEBUG
/// Test credentials are generated at runtime and exist only in memory.
final class CloudMemoryTokenStore: CloudTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    init(_ token: String? = nil) { value = token }
    func read() throws -> String? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ token: String) throws { lock.lock(); value = token; lock.unlock() }
    func remove() throws { lock.lock(); value = nil; lock.unlock() }
}
#endif
