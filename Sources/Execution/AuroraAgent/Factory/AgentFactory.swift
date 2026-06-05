import Foundation
import AuroraConfig
import AuroraLLMProvider

public enum AgentFactory {

    /// Production `Agent`. `async` because it authenticates the resolved
    /// provider's key via `Config.loadKey(for:)` (which may prompt Touch ID).
    ///
    /// Order matters: `loadEnvironment()` first (prompt-free — loads `.env` so
    /// an `LLM_PROVIDER`/model override there counts, and snapshots
    /// `originalKeySource` so the banner stays honest) → resolve the active
    /// provider → `loadKey(for:)` for **only** that provider. Loading just the
    /// resolved provider's key is deliberate: it avoids prompting the keychain
    /// for providers this call won't use.
    public static func makeDefault(providerOverride: AgentAuth.Provider? = nil) async throws -> Agent {
        // Prompt-free: load `.env` + snapshot before resolving.
        Config.loadEnvironment()
        // Selection waterfall: --provider (CLI) → LLM_PROVIDER env → the
        // stored `aurora auth use` choice. No silent default — `nil` means
        // nothing was chosen, surfaced as a setup hint.
        let resolved = Config.resolveActiveProvider(
            override: providerOverride.map(AgentAuth.toConfig),
            envRaw: ProcessInfo.processInfo.environment["LLM_PROVIDER"],
            storedSelection: AgentAuth.activeProviderSelection().map(AgentAuth.toConfig)
        )
        guard let provider = resolved else { throw AgentAuthError.noProviderSelected }
        // Only now authenticate — and only the resolved provider's key.
        await Config.loadKey(for: provider)
        return DefaultAgent(client: makeAPIClient(for: provider))
    }

    /// Test / advanced injection point. Takes an explicit `APIClient` —
    /// typically constructed in tests via `@testable import AuroraLLMProvider`
    /// with a stub `LLMProvider` and `backoffSeconds: { _ in 0 }`.
    ///
    /// `internal` — Phase 4 scope has no external use case for arbitrary
    /// `APIClient` injection. Promote this to `public` if a
    /// multi-provider resolver needs to construct different clients per
    /// call.
    internal static func make(client: APIClient) -> Agent {
        DefaultAgent(client: client)
    }
}
