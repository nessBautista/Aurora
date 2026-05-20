import Foundation
public extension Keychain {
    // MARK: - Error type
    enum KeychainError: LocalizedError, Equatable {

        case storeFailed(OSStatus)
        case readFailed(OSStatus)
        case userCancelled
        case biometryUnavailable
        case locked

        public var errorDescription: String? {
            switch self {
            case .storeFailed(let status):
                return "Keychain store failed (OSStatus \(status)). "
                + "Check Keychain Access app for conflicts."
            case .readFailed(let status):
                return "Keychain read failed (OSStatus \(status))."
            case .userCancelled:
                return "Cancelled by user."
            case .biometryUnavailable:
                return "Biometric authentication is not available on this device."
            case .locked:
                return "Keychain is locked. Please unlock your macOS login keychain "
                + "or log out and log back in."
            }
        }
    }
}
