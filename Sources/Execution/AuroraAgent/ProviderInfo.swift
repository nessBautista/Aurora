import Foundation
/// Snapshot of provider identity for the startup banner.
///
/// `Sendable` so Application can shuttle it across actor / Task
/// boundaries (e.g. printing it from a different context than the agent
/// was constructed on).


public struct ProviderInfo: Sendable, Equatable {
    /// Provider display name — `"Anthropic"`, `"OpenRouter"`, etc.
    public let providerName: String
    /// Resolved model identifier after env-var lookup.
    public let modelId: String
    /// Where the API key came from — `"keychain (Touch ID)"`, `"env var"`,
    /// `".env file"`, `"missing"`. Never the key itself.
    public let apiKeySource: String
    
    
    public init(providerName: String, modelId: String, apiKeySource: String) {
        self.providerName = providerName
        self.modelId = modelId
        self.apiKeySource = apiKeySource
    }
}
