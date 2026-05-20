import Foundation
import Security
import LocalAuthentication

/// macOS keychain wrapper with a Touch ID / password gate on reads.
///
/// This file holds Stage 3 (I/O orchestration). Stage 1 (pure query builders)
/// lives in `Keychain+Queries.swift`; Stage 2 (pure status interpreters) in
/// `Keychain+Interpreters.swift`. See `README.md` for the design rationale
/// and security trade-offs.
public enum Keychain {
    
    // MARK: - Stage 3: I/O orchestration
    
    /// Upsert a string value under `service` / `account`.
    /// Tries `SecItemUpdate` first; falls back to `SecItemAdd` when the item
    /// doesn't exist. Race-safer than delete-then-add (no window where a
    /// concurrent `get` sees `errSecItemNotFound` between ops).
    public static func set(
        service: String,
        account: String,
        value: String
    ) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.storeFailed(errSecParam)
        }
        
        let identity = makeIdentityQuery(service: service, account: account)
        let updateAttrs = makeUpdateAttributes(account: account, value: data)
        
        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            updateAttrs as CFDictionary
        )
        
        switch try interpretUpdate(updateStatus) {
        case .updated:
            return
        case .itemMissing:
            let addStatus = SecItemAdd(
                makeAddQuery(service: service, account: account, value: data) as CFDictionary,
                nil
            )
            try interpretAdd(addStatus)
        }
    }
    
    /// Read a secret, prompting Touch ID / password before the read.
    /// Returns `nil` if the item doesn't exist (not an error — caller decides).
    public static func get(
        service: String,
        account: String,
        prompt: String
    ) async throws -> String? {
        // Short-circuit on missing item — no point prompting biometry to read
        // something that isn't there.
        guard exists(service: service, account: account) else {
            return nil
        }
        
        try await authenticateForRead(prompt: prompt)
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            makeReadQuery(service: service, account: account) as CFDictionary,
            &item
        )
        
        return try interpretRead(status, payload: item)
    }
    
    /// Check whether an item exists. Does not trigger biometry.
    public static func exists(service: String, account: String) -> Bool {
        let status = SecItemCopyMatching(
            makeExistsQuery(service: service, account: account) as CFDictionary,
            nil
        )
        return interpretExists(status)
    }
    
    /// Delete the item if it exists. Idempotent — no error if absent.
    public static func clear(service: String, account: String) {
        SecItemDelete(makeIdentityQuery(service: service, account: account) as CFDictionary)
    }
    
    // MARK: - Private — LAContext gate
    
    /// Authenticate the user before a keychain read via `LAContext.evaluatePolicy`.
    /// `.deviceOwnerAuthentication` allows password fallback; switch to
    /// `.deviceOwnerAuthenticationWithBiometrics` for strict biometry only.
    private static func authenticateForRead(prompt: String) async throws {
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw KeychainError.biometryUnavailable
        }
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: prompt
            )
        } catch let error as LAError where error.code == .userCancel {
            throw KeychainError.userCancelled
        } catch {
            throw KeychainError.readFailed(errSecAuthFailed)
        }
    }
}
