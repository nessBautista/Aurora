
import AuroraAgent

enum Container {
    /// Construct the production `Agent` via the Tier 2 factory, which resolves
    /// the active provider (`--provider` → `LLM_PROVIDER` → stored selection).
    /// Throws `AgentAuthError.noProviderSelected` when nothing selects one.
    static func makeAgent(providerOverride: AgentAuth.Provider? = nil) async throws -> Agent {
        try await AgentFactory.makeDefault(providerOverride: providerOverride)
    }
}
