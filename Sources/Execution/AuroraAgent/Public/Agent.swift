import Foundation


/// Aurora's Tier 2 chat surface. Application code holds an `Agent`
/// reference (from `AgentFactory.makeDefault()`) and calls `chat(_:)` to
/// drive a single round-trip to the model.
public protocol Agent {
        /// Snapshot of the underlying provider's identity for the startup
        /// banner. Read on access — `modelId` and `apiKeySource` re-resolve
        /// from env on every read, matching `APIClient.bootInfo`'s semantics.
        var providerInfo: ProviderInfo { get }
        
        /// Returns the assistant's prose, with `.text` blocks joined by
        /// newlines (via `AuroraModels.extractText`).
        /// Throws `TransientError` if all retries exhausted, `BadResponse`
        /// for unparseable responses, or an `NSError` for non-transient HTTP
        /// failures.
        func chat(_ prompt: String) async throws -> String
}
