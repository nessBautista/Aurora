/// # APIClient.swift — Provider-agnostic facade with retry loop
///
/// `APIClient` is what the rest of Aurora calls. It owns:
///   - The selected provider (resolved once at init via `makeLLMProvider`,
///     or injected directly by tests / Phase 4's `AgentFactory`).
///   - The retry loop (shared by all providers, parameterized for testability).
///
/// It does NOT own:
///   - Wire-format encoding/decoding (lives in providers).
///   - Tool schemas, system prompts (passed in by callers).
///   - Message normalization (providers run it as their first step).
///
/// Instantiation: production callers go through `makeAPIClient()` at the
/// bottom of this file. Tests (`@testable import AuroraLLMProvider`)
/// construct directly with `APIClient(provider: stub, backoffSeconds:
/// { _ in 0 })`. The `init(provider:...)` is `internal`, so external
/// modules can't reach in and bypass the production composition path.

import Foundation
import AuroraModels
import AuroraConfig

/// Snapshot of provider identity surfaced for the startup banner. Lives
/// on `APIClient.bootInfo` so external callers can render it without
/// touching `LLMProvider` directly.
public struct BootInfo: Equatable {
    /// Provider display name — `"Anthropic"`, `"OpenRouter"`, etc.
    public let providerName: String
    /// Resolved model identifier after env-var lookup.
    public let modelId: String
    /// Where the API key came from — `"keychain (Touch ID)"`, `"env var"`,
    /// `".env file"`, `"missing"`. Never the key itself.
    public let apiKeySource: String
}

public struct APIClient {
    private let provider: LLMProvider
    private let maxAttempts: Int
    private let backoffSeconds: (Int) -> Int

    /// `maxAttempts` / `backoffSeconds` default to production retry tuning:
    /// 5 attempts with exponential backoff (2s, 4s, 8s, 16s between attempts
    /// — 30s total wall-clock if all four retries fire). Tuned for
    /// `overloaded_error` (HTTP 529) bursts Anthropic ships during peak
    /// hours; a 3-attempt / 1s,2s linear schedule gave up too fast when the
    /// overload window outlasted ~3 seconds in lab testing.
    ///
    /// `internal` — `LLMProvider` is a module-private seam. Tests reach
    /// this via `@testable import AuroraLLMProvider` and inject a stub
    /// plus `backoffSeconds: { _ in 0 }` to verify retry behavior without
    /// real sleeps. Production callers go through `makeAPIClient()`.
    internal init(
        provider: LLMProvider,
        maxAttempts: Int = 5,
        backoffSeconds: @escaping (Int) -> Int = { 1 << $0 }   // 2s, 4s, 8s, 16s
    ) {
        self.provider = provider
        self.maxAttempts = maxAttempts
        self.backoffSeconds = backoffSeconds
    }

    /// Snapshot of provider identity for the startup banner. Read on
    /// access — `modelId` and `apiKeySource` re-resolve from env on every
    /// read, matching the provider's own getter semantics.
    public var bootInfo: BootInfo {
        BootInfo(
            providerName: provider.name,
            modelId: provider.modelId,
            apiKeySource: provider.apiKeySource
        )
    }

    /// One round-trip to the LLM, with retry on transient failures.
    /// Provider-agnostic.
    ///
    /// `forcedTool`: when non-nil, asks the provider to coerce the model into
    /// emitting structured output matching the tool's schema (Anthropic tool-use
    /// coercion; OpenRouter `response_format` once that adapter lands). See
    /// `ForcedTool` and `LLMProvider.performRequest` for details.
    public func callAPI(
        messages: [Message],
        tools: [[String: Any]]? = nil,
        systemPrompt: String? = nil,
        forcedTool: ForcedTool? = nil
    ) async throws -> (String, [ContentBlock]) {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await provider.performRequest(
                    messages: messages,
                    tools: tools,
                    systemPrompt: systemPrompt,
                    forcedTool: forcedTool
                )
            } catch let error as TransientError {
                lastError = error
                if attempt < maxAttempts {
                    let seconds = backoffSeconds(attempt)
                    // Retry log goes to stderr so stdout stays pipeable.
                    FileHandle.standardError.write(
                        Data("  [API \(error.kind), retrying in \(seconds)s...]\n".utf8)
                    )
                    try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                }
            }
        }

        throw lastError ?? NSError(
            domain: "API", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown API error"]
        )
    }
}

// MARK: - Production composition

/// Returns an `APIClient` wired to the adapter for `provider`, with
/// production retry tuning (5 attempts, exponential backoff 2/4/8/16s).
///
/// Tests construct `APIClient` directly and pass a stub provider plus a
/// 0-second backoff; they do not call this function.
public func makeAPIClient(for provider: Config.Provider) -> APIClient {
    APIClient(provider: makeLLMProvider(for: provider))
}
