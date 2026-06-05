import Foundation
import AuroraKeychain

/// Aurora-specific credential resolution. Knows the Aurora keychain
/// service/account constants and the source-priority order; delegates the
/// actual keychain interaction to `AuroraKeychain`.
///
/// See `README.md` in this directory for the priority order, the async
/// reasoning, and the `preLoadKeySources` snapshot trick.
public enum Config {
    
    static let keychainService = "aurora"
    
    /// Providers Aurora can talk to. Each carries its own env var name and
    /// keychain account; one switch per case keeps the per-provider knobs
    /// in a single place.
    public enum Provider: String, CaseIterable {
        case anthropic
        case openrouter

        public var envVarName: String {
            switch self {
            case .anthropic:  return "ANTHROPIC_API_KEY"
            case .openrouter: return "OPENROUTER_API_KEY"
            }
        }
        
        public var keychainAccount: String {
            switch self {
            case .anthropic:  return "anthropic_api_key"
            case .openrouter: return "openrouter_api_key"
            }
        }
        
        public var displayName: String {
            switch self {
            case .anthropic:  return "Anthropic"
            case .openrouter: return "OpenRouter"
            }
        }
    }
    
    /// Where Aurora found (or would find) a provider's API key.
    /// `keySource(for:)` reports this; `load()` walks the same order.
    public enum KeySource: Equatable {
        case env        // process env var already set
        case keychain   // macOS keychain (Touch ID protected)
        case envFile    // <cwd>/.env
        case missing    // nothing configured anywhere
    }
    
    // MARK: - Helpers
    
    /// Decide which `KeySource` applies given the three signals.
    /// Pure function: identical inputs always produce identical outputs.
    /// `internal` — testing seam reached via `@testable import AuroraConfig`.
    static func resolveKeySource(
        envHasKey: Bool,
        keychainHasItem: Bool,
        envFileExists: Bool
    ) -> KeySource {
        if envHasKey       { return .env }
        if keychainHasItem { return .keychain }
        if envFileExists   { return .envFile }
        return .missing
    }
    
    /// Pure provider-selection precedence: `--provider` (already validated by
    /// the CLI) → `LLM_PROVIDER` env → the stored `Settings.selectedProvider`.
    /// Returns `nil` when nothing selects a provider anywhere — the caller
    /// surfaces a "run `aurora auth use`" hint rather than silently defaulting.
    ///
    /// `envRaw` is parsed leniently here (case-insensitive; an unrecognized
    /// value is ignored and falls through). A typo'd `--provider` never
    /// reaches this function — it's a `ValidationError` at the CLI boundary,
    /// matching `auth set`.
    public static func resolveActiveProvider(
        override: Provider?,
        envRaw: String?,
        storedSelection: Provider?
    ) -> Provider? {
        if let override { return override }
        if let envRaw, let parsed = Provider(rawValue: envRaw.lowercased()) {
            return parsed
        }
        return storedSelection
    }

    // MARK: - I/O orchestration
    
    /// Store a provider's API key in the macOS keychain.
    public static func setAPIKey(for provider: Provider, _ key: String) throws {
        try Keychain.set(
            service: keychainService,
            account: provider.keychainAccount,
            value: key
        )
    }
    
    /// Remove a provider's stored API key. Idempotent.
    public static func clearAPIKey(for provider: Provider) {
        Keychain.clear(
            service: keychainService,
            account: provider.keychainAccount
        )
    }
    
    /// Report where this provider's API key would come from right now,
    /// without loading it. Walks the same priority as `load()`.
    public static func keySource(for provider: Provider) -> KeySource {
        resolveKeySource(
            envHasKey: ProcessInfo.processInfo.environment[provider.envVarName] != nil,
            keychainHasItem: Keychain.exists(service: keychainService, account: provider.keychainAccount),
            envFileExists: FileManager.default.fileExists(atPath: defaultEnvFilePath())
        )
    }
    
    /// Where this provider's API key was BEFORE `load()` ran — the user's
    /// "original" credential storage. Used by banners so they show
    /// "keychain (Touch ID)" rather than "env var" after `load()` has copied
    /// the keychain value into process env. Falls back to the live
    /// `keySource(for:)` if `load()` hasn't been called yet.
    public static func originalKeySource(for provider: Provider) -> KeySource {
        preLoadKeySources[provider] ?? keySource(for: provider)
    }
    
    /// Resolve credentials for every known provider into process env.
    /// Priority is `env > keychain > .env > missing` per provider.
    /// `async` because `Keychain.get` is async (it calls `LAContext.evaluatePolicy`).
    public static func load() async {
        await loadInto(envFilePath: defaultEnvFilePath())
    }
    
    // MARK: - Internal seam
    
    /// Same as `load()` but accepts an explicit `.env` path so tests can
    /// verify the path used without `chdir`-ing the process.
    internal static func loadInto(envFilePath: String) async {
        // Snapshot pre-load key source per provider. Once set on first
        // load, never overwritten.
        for provider in Provider.allCases where preLoadKeySources[provider] == nil {
            preLoadKeySources[provider] = keySource(for: provider)
        }
        
        // Per-provider: env > keychain. Skip the keychain prompt for any
        // provider whose env var is already populated. `try?` is deliberate
        // — keychain errors (cancel, biometry off, locked) should fall
        // through to .env loading rather than abort `load()` entirely.
        for provider in Provider.allCases {
            if ProcessInfo.processInfo.environment[provider.envVarName] == nil {
                if let key = try? await Keychain.get(
                    service: keychainService,
                    account: provider.keychainAccount,
                    prompt: "Aurora needs your \(provider.displayName) API key"
                ), !key.isEmpty {
                    setenv(provider.envVarName, key, 1)
                }
            }
        }
        
        // Always load .env for non-API-key configuration. Silent if file
        // missing; never overrides a var already in process env.
        loadEnvFile(envFilePath)
    }
    
    // MARK: - Private
    
    private nonisolated(unsafe) static var preLoadKeySources: [Provider: KeySource] = [:]
    
    private static func defaultEnvFilePath() -> String {
        FileManager.default.currentDirectoryPath.appending("/.env")
    }
}
