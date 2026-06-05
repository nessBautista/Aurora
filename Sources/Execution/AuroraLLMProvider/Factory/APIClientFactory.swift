/// # APIClientFactory.swift — Production composition for AuroraLLMProvider
///
/// The module's production wiring in one place: the public `makeAPIClient`
/// entry point and the internal `makeLLMProvider` it composes. Tests bypass
/// both — they construct `APIClient(provider:backoffSeconds:)` directly with a
/// stub `LLMProvider` and a 0-second backoff.

import AuroraConfig

/// Returns an `APIClient` wired to the adapter for `provider`, with
/// production retry tuning (5 attempts, exponential backoff 2/4/8/16s).
///
/// Tests construct `APIClient` directly and pass a stub provider plus a
/// 0-second backoff; they do not call this function.
public func makeAPIClient(for provider: Config.Provider) -> APIClient {
    APIClient(provider: makeLLMProvider(for: provider))
}

/// Resolves a `Config.Provider` to its concrete `LLMProvider` adapter. This
/// is the only place production code maps the provider enum to a concrete.
///
/// `internal` — `LLMProvider` is a module-private DI seam. External callers
/// compose through `makeAPIClient(for:)` and never name a provider concrete
/// directly.
func makeLLMProvider(for provider: Config.Provider) -> LLMProvider {
    switch provider {
    case .anthropic:  return AnthropicProvider()
    case .openrouter: return OpenRouterProvider()
    }
}
