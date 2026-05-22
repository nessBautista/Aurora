import XCTest
@testable import AuroraAgent
@testable import AuroraLLMProvider
import AuroraModels

final class AgentFactoryTests: XCTestCase {

    /// Minimal stub — `make(client:)` just needs to round-trip the client.
    private final class TraceProvider: LLMProvider {
        let name = "Trace"
        let modelId = "trace"
        let apiKeySource = "test"
        var called = false
        func performRequest(messages: [Message],
                            tools: [[String: Any]]?,
                            systemPrompt: String?,
                            forcedTool: ForcedTool?)
        async throws -> (stopReason: String, content: [ContentBlock]) {
            called = true
            return ("end_turn", [.text("ok")])
        }
    }

    func testMakeReturnsAgentBackedByInjectedClient() async throws {
        let trace = TraceProvider()
        let client = APIClient(provider: trace, backoffSeconds: { _ in 0 })
        let agent = AgentFactory.make(client: client)

        _ = try await agent.chat("hi")

        XCTAssertTrue(trace.called, "make(client:) did not wire the injected client into the agent")
    }

    // makeDefault() is not unit-tested here — it calls Config.load() and
    // makeAPIClient(), both of which reach real macOS keychain / Anthropic.
    // Phase 5's integration tests exercise the full path; D.3 below is the
    // optional manual smoke test for WOR-54.
}
