import Foundation
import AuroraConfig
import AuroraSettings

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

    // MARK: - Active provider selection

    /// Persist the user's chosen default provider (the `aurora auth use`
    /// target). Delegates to `AuroraSettings`.
    public static func setActiveProvider(_ provider: Provider) {
        setActiveProvider(provider, store: makeSettingsStore())
    }

    /// The persisted default provider, or `nil` if none has been chosen.
    /// `nil` is what the resolver turns into a "run `aurora auth use`" hint
    /// rather than silently defaulting.
    public static func activeProviderSelection() -> Provider? {
        activeProviderSelection(store: makeSettingsStore())
    }

    /// `internal` test seam — inject an isolated `SettingsStore(suiteName:)`
    /// so tests don't touch the developer's real preferences. Production
    /// callers use the no-arg overloads above (which never name
    /// `SettingsStore`, keeping the Application layer free of an
    /// `AuroraSettings` import).
    internal static func setActiveProvider(_ provider: Provider, store: SettingsStore) {
        var settings = store.load()
        settings.selectedProvider = toConfig(provider)
        store.save(settings)
    }

    internal static func activeProviderSelection(store: SettingsStore) -> Provider? {
        store.load().selectedProvider.map(fromConfig)
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

    /// Inverse of `toConfig` — maps a persisted `Config.Provider` back to the
    /// Tier 2 enum. Exhaustive so a new `Config.Provider` case is a compile
    /// error here until mirrored.
    internal static func fromConfig(_ provider: Config.Provider) -> Provider {
        switch provider {
        case .anthropic:  return .anthropic
        case .openrouter: return .openrouter
        }
    }
}

/// Errors surfaced by the provider-selection flow.
public enum AgentAuthError: LocalizedError {
    /// No provider was chosen via `--provider`, `LLM_PROVIDER`, or a stored
    /// `aurora auth use` selection.
    case noProviderSelected

    public var errorDescription: String? {
        switch self {
        case .noProviderSelected:
            return "No LLM provider selected. Run `aurora auth use <provider>`, "
                + "set LLM_PROVIDER, or pass --provider <provider>."
        }
    }
}
