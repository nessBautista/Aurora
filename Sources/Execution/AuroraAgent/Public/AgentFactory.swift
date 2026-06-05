import Foundation
import AuroraConfig
import AuroraLLMProvider

public enum AgentFactory {

    /// Production `Agent`. `async` because it runs `Config.load()` before
    /// constructing the agent — this is what makes `.env`-based model
    /// overrides (`ANTHROPIC_MODEL_ID`, etc.) and keychain-sourced
    /// `ANTHROPIC_API_KEY` take effect on the first read of
    /// `agent.providerInfo` (the banner) and the first `chat()` call.
    ///
    /// `Config.load()` snapshots `originalKeySource` on first call so the
    /// banner can still show "keychain (Touch ID)" after the keychain
    /// value is copied into env (see `Config.originalKeySource(for:)`).
    public static func makeDefault(providerOverride: AgentAuth.Provider? = nil) async throws -> Agent {
        await Config.load()
        // Selection waterfall: --provider (CLI) → LLM_PROVIDER env → the
        // stored `aurora auth use` choice. No silent default — `nil` means
        // nothing was chosen, surfaced as a setup hint.
        let resolved = Config.resolveActiveProvider(
            override: providerOverride.map(AgentAuth.toConfig),
            envRaw: ProcessInfo.processInfo.environment["LLM_PROVIDER"],
            storedSelection: AgentAuth.activeProviderSelection().map(AgentAuth.toConfig)
        )
        guard let provider = resolved else { throw AgentAuthError.noProviderSelected }
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
