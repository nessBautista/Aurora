import Foundation
import AuroraConfig

/// Pure encode/decode between `Settings` and the raw string values that
/// UserDefaults persists. No I/O — tests cover every branch without
/// touching UserDefaults.
///
/// `internal` — only `SettingsStore` calls these. Tests reach the codec
/// via `@testable import AuroraSettings`.
enum SettingsCodec {
    
    /// The raw string-keyed shape that `Settings` round-trips through on
    /// the way to UserDefaults. Modeled as a struct rather than a labeled
    /// tuple because Swift forbids single-element labeled tuples; using a
    /// struct also leaves room to grow more raw fields without a
    /// return-type-breaking refactor.
    struct RawValues: Equatable {
        var selectedProviderRaw: String?
        
        init(selectedProviderRaw: String? = nil) {
            self.selectedProviderRaw = selectedProviderRaw
        }
    }
    
    static let selectedProviderKey = "selectedProvider"
    
    /// Decode a single raw provider string back into a `Settings`.
    /// Unknown raw values resolve to nil (forward-compatible: a settings
    /// file written by a future version with a new provider doesn't
    /// crash an older binary).
    static func decode(selectedProviderRaw: String?) -> Settings {
        Settings(selectedProvider: selectedProviderRaw.flatMap(Config.Provider.init(rawValue:)))
    }
    
    /// Encode `Settings` into the values to write to UserDefaults.
    /// Returns nil-valued raw when the snapshot has no provider — the
    /// store removes the key in that case.
    static func encode(_ settings: Settings) -> RawValues {
        RawValues(selectedProviderRaw: settings.selectedProvider?.rawValue)
    }
}
