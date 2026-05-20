import Foundation
import Security

// MARK: - Stage 2: pure status interpreters
//
// Translate `OSStatus` (+ optional payload) into Swift outcomes. No I/O.

extension Keychain {
    
    /// What `SecItemUpdate` returned. The orchestration in `set` uses this
    /// to decide whether to fall through to `SecItemAdd`.
    enum UpdateOutcome: Equatable {
        case updated         // errSecSuccess — item existed and was overwritten
        case itemMissing     // errSecItemNotFound — caller should SecItemAdd next
    }
    
    /// Translate a `SecItemUpdate` status into a routing decision, or throw.
    static func interpretUpdate(_ status: OSStatus) throws -> UpdateOutcome {
        switch status {
        case errSecSuccess:               return .updated
        case errSecItemNotFound:          return .itemMissing
        case errSecInteractionNotAllowed: throw KeychainError.locked
        default:                          throw KeychainError.storeFailed(status)
        }
    }
    
    /// Translate a `SecItemAdd` status. Returns normally on success;
    /// throws on every failure mode.
    static func interpretAdd(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:               return
        case errSecInteractionNotAllowed: throw KeychainError.locked
        default:                          throw KeychainError.storeFailed(status)
        }
    }
    
    /// Translate a `SecItemCopyMatching` read result into `String?` or a
    /// thrown error. Distinguishes "not found" (nil) from "found but
    /// undecodable" (throw).
    static func interpretRead(_ status: OSStatus, payload: CFTypeRef?) throws -> String? {
        switch status {
        case errSecSuccess:
            guard
                let data = payload as? Data,
                let value = String(data: data, encoding: .utf8)
            else { throw KeychainError.readFailed(status) }
            return value
        case errSecItemNotFound:          return nil
        case errSecUserCanceled:          throw KeychainError.userCancelled
        case errSecInteractionNotAllowed: throw KeychainError.locked
        default:                          throw KeychainError.readFailed(status)
        }
    }
    
    /// Translate a `SecItemCopyMatching` exists-probe result into `Bool`.
    /// `errSecInteractionNotAllowed` means "item exists but keychain is
    /// locked" — treat as exists=true so callers don't trigger biometry
    /// just to probe.
    static func interpretExists(_ status: OSStatus) -> Bool {
        status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}
