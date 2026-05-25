/// # LLMProvider.swift — The Wire-Format Adapter Protocol
///
/// A wire-format adapter for an LLM API. Implementations translate between
/// Aurora's internal Message/ContentBlock model and a specific provider's
/// request/response shape.
///
/// ## Contract every implementation must follow
///
///  1. Run `MessageNormalizer.normalize(messages)` first (handles orphaned tool_use).
///  2. Encode to the provider's wire format. Preserve message order.
///     Never invent IDs.
///  3. Throw `TransientError` for retry-worthy failures (HTTP 429, 5xx,
///     overloaded).
///  4. Throw `BadResponse` for malformed responses you can't parse defensively.
///  5. Decode the response back to `(stopReason, [ContentBlock])`.
///
/// The stop-reason vocabulary is the Anthropic vocabulary: `"tool_use"`,
/// `"end_turn"`, `"max_tokens"`, `"stop_sequence"`, `"content_filter"`.
/// Adapters map their provider's terms to these.

import Foundation
import AuroraModels

protocol LLMProvider {
    /// Display name for the boot banner — `"Anthropic"`, `"OpenRouter"`, etc.
    var name: String { get }

    /// Resolved model identifier — whatever ended up being used after env-var
    /// lookup. Computed on access; honors mid-process env mutations.
    var modelId: String { get }

    /// Where the API key was sourced from, for the boot banner.
    /// Returns something like `"keychain (Touch ID)"`, `"env var"`,
    /// `".env file"`, `"missing"` — never the key itself.
    var apiKeySource: String { get }

    /// One round-trip to the LLM. Implementations MUST run
    /// `MessageNormalizer.normalize` as the first step.
    ///
    /// `forcedTool`: when non-nil, the provider must coerce the model into
    /// emitting structured input for the named tool on this turn. The
    /// Anthropic path uses tool-use coercion (synthetic tool with
    /// `strict: true` + `tool_choice: {type: "tool", name: ...}`); other
    /// providers map to the equivalent on their wire format. Providers
    /// without a structured-output mechanism may ignore the parameter and
    /// rely on caller-side free-text JSON extraction.
    func performRequest(
        messages: [Message],
        tools: [[String: Any]]?,
        systemPrompt: String?,
        forcedTool: ForcedTool?
    ) async throws -> (stopReason: String, content: [ContentBlock])
}

extension LLMProvider {
    /// Convenience overload — callers that don't need structured output keep
    /// using the 3-arg shape. Forwards to the 4-arg method with
    /// `forcedTool: nil`.
    func performRequest(
        messages: [Message],
        tools: [[String: Any]]?,
        systemPrompt: String?
    ) async throws -> (stopReason: String, content: [ContentBlock]) {
        try await performRequest(
            messages: messages,
            tools: tools,
            systemPrompt: systemPrompt,
            forcedTool: nil
        )
    }
}

// `TransientError` and `BadResponse` live in `LLMProvider+Errors.swift`.

// MARK: - Production composition

/// Returns the configured concrete `LLMProvider`. Today there's exactly
/// one — `AnthropicProvider`. As additional adapters land this grows into
/// a switch over a `LLM_PROVIDER` env var; for now it's a one-liner. This
/// is the only place production code resolves the provider concrete.
///
/// `internal` — `LLMProvider` is a module-private DI seam. External
/// callers compose through `makeAPIClient()` and never name a provider
/// directly.
func makeLLMProvider() -> LLMProvider {
    AnthropicProvider()
}
