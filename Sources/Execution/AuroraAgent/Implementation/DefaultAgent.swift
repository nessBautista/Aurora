import Foundation
import AuroraLLMProvider
import AuroraModels

/// Production `Agent`. Wraps an `APIClient` (Tier 3) and exposes the
/// `String → String` chat surface plus the translated `ProviderInfo`.
///
/// `final class` rather than `struct` because:
///   - `APIClient` is a value but `DefaultAgent` may grow reference-typed
///     state later (a future stateful-chat extension would hold history);
///     starting with a class avoids a later type-shape break.
///   - "Service" types are conventionally reference types in Swift.
internal final class DefaultAgent: Agent {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    var providerInfo: ProviderInfo {
        let info = client.bootInfo
        return ProviderInfo(
            providerName: info.providerName,
            modelId:      info.modelId,
            apiKeySource: info.apiKeySource
        )
    }

    func chat(_ prompt: String) async throws -> String {
        let (_, content) = try await client.callAPI(
            messages: [Message(role: "user", content: [.text(prompt)])]
        )
        return extractText(content)
    }
}
