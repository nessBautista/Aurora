import Foundation
import Security

// MARK: - Stage 1: pure query builders
//
// Build the dictionaries that `SecItem*` calls expect. No I/O.
// `public extension` makes every declared member public by default.

extension Keychain {
    
    /// Class + service + account — the minimum set of keys that uniquely
    /// identify one keychain item. Used as the base for the other queries
    /// and directly by `clear`.
    static func makeIdentityQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
    
    /// Identity + value + label + accessibility class.
    /// Used by `SecItemAdd` in the fall-through path of `set`.
    static func makeAddQuery(service: String, account: String, value: Data) -> [String: Any] {
        var query = makeIdentityQuery(service: service, account: account)
        query[kSecValueData as String]      = value
        query[kSecAttrLabel as String]      = "Aurora: \(account)"
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return query
    }
    
    /// The attributes-to-update slice for `SecItemUpdate`. Pairs with
    /// `makeIdentityQuery` (used as the WHERE clause) to upsert.
    static func makeUpdateAttributes(account: String, value: Data) -> [String: Any] {
        [
            kSecValueData as String: value,
            kSecAttrLabel as String: "Aurora: \(account)",
        ]
    }
    
    /// Identity + the keys that make `SecItemCopyMatching` return the stored
    /// bytes as `Data`. `kSecMatchLimitOne` is required (not stylistic) when
    /// `kSecReturnData` is true — without it, some keychain paths return a
    /// `CFArray` instead of plain `Data`.
    static func makeReadQuery(service: String, account: String) -> [String: Any] {
        var query = makeIdentityQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
    
    /// Identity + metadata-only flags. `kSecUseAuthenticationUISkip` keeps
    /// the existence probe from triggering biometry — a probe shouldn't
    /// prompt the user.
    static func makeExistsQuery(service: String, account: String) -> [String: Any] {
        var query = makeIdentityQuery(service: service, account: account)
        query[kSecReturnData as String]          = false
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        return query
    }
}
