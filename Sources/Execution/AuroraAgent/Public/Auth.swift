import Foundation
import AuroraConfig

public enum AgentAuth {

    /// LLM providers Aurora can talk to.
    /// Mirrors `Config.Provider`.
    public enum Provider: String, CaseIterable {
        case anthropic
        case openrouter
    }

    /// Where an API key lives. Mirrors `Config.KeySource`.
    public enum KeyStatus: Equatable {
        case env       // process env var already set
        case keychain  // macOS keychain (Touch ID protected on read)
        case envFile   // <cwd>/.env file
        case missing   // nothing configured anywhere
    }

    /// Store an API key in the macOS keychain (Touch ID protected on read).
    public static func setKey(_ provider: Provider, _ key: String) throws {
        try Config.setAPIKey(for: toConfig(provider), key)
    }

    /// Remove a stored API key. Idempotent — clearing a non-existent key
    /// is a silent no-op.
    public static func clearKey(_ provider: Provider) {
        Config.clearAPIKey(for: toConfig(provider))
    }

    /// Report where the provider's API key would come from, without
    /// actually loading it. Doesn't trigger Touch ID.
    public static func keyStatus(_ provider: Provider) -> KeyStatus {
        switch Config.keySource(for: toConfig(provider)) {
        case .env:      return .env
        case .keychain: return .keychain
        case .envFile:  return .envFile
        case .missing:  return .missing
        }
    }

    // MARK: - Tier 2 ↔ Tier 4 translation

    /// `internal` — visible to tests so the enum mapping stays pinned
    /// (a missing translation case for a future provider is a compile
    /// error in the test, not a silent runtime fallthrough).
    internal static func toConfig(_ provider: Provider) -> Config.Provider {
        switch provider {
        case .anthropic:  return .anthropic
        case .openrouter: return .openrouter
        }
    }
}
