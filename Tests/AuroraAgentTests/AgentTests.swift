import XCTest
@testable import AuroraAgent
@testable import AuroraLLMProvider
import AuroraModels

// MARK: - Test helpers

/// Stub `LLMProvider` that records the last request and returns a
/// canned response. Lives next to the test that uses it; not a shared
/// helper.
private final class StubProvider: LLMProvider {
    let name: String
    let modelId: String
    let apiKeySource: String

    var capturedMessages: [Message] = []
    var capturedTools: [[String: Any]]? = nil
    var capturedSystemPrompt: String? = nil
    var response: (String, [ContentBlock]) = ("end_turn", [.text("ok")])

    init(
        name: String = "Stub",
        modelId: String = "stub-model",
        apiKeySource: String = "test"
    ) {
        self.name = name
        self.modelId = modelId
        self.apiKeySource = apiKeySource
    }

    func performRequest(
        messages: [Message],
        tools: [[String: Any]]?,
        systemPrompt: String?,
        forcedTool: ForcedTool?
    ) async throws -> (stopReason: String, content: [ContentBlock]) {
        capturedMessages = messages
        capturedTools = tools
        capturedSystemPrompt = systemPrompt
        return response
    }
}

private func makeAgent(provider: StubProvider) -> Agent {
    let client = APIClient(provider: provider, backoffSeconds: { _ in 0 })
    return AgentFactory.make(client: client)
}

// MARK: - Agent.chat

final class AgentChatTests: XCTestCase {

    func testReturnsExtractedTextFromAssistantResponse() async throws {
        let stub = StubProvider()
        stub.response = ("end_turn", [.text("hello world")])
        let agent = makeAgent(provider: stub)

        let result = try await agent.chat("hi")

        XCTAssertEqual(result, "hello world")
    }

    func testSendsSingleUserMessageWithPromptAsText() async throws {
        let stub = StubProvider()
        let agent = makeAgent(provider: stub)

        _ = try await agent.chat("ping")

        XCTAssertEqual(stub.capturedMessages.count, 1)
        XCTAssertEqual(stub.capturedMessages[0].role, "user")
        XCTAssertEqual(stub.capturedMessages[0].content.count, 1)
        XCTAssertEqual(extractText(stub.capturedMessages[0].content), "ping")
    }

    func testDoesNotPassToolsOrSystemPrompt() async throws {
        // Auth-flow scope is no-tools, no-system-prompt. Verify the
        // single-shot path doesn't sneak either in.
        let stub = StubProvider()
        let agent = makeAgent(provider: stub)

        _ = try await agent.chat("hi")

        XCTAssertNil(stub.capturedTools)
        XCTAssertNil(stub.capturedSystemPrompt)
    }

    func testJoinsMultipleTextBlocksWithNewlines() async throws {
        let stub = StubProvider()
        stub.response = ("end_turn", [.text("line 1"), .text("line 2")])
        let agent = makeAgent(provider: stub)

        let result = try await agent.chat("hi")

        XCTAssertEqual(result, "line 1\nline 2")
    }

    func testIgnoresNonTextBlocks() async throws {
        // The agent loop is single-shot — any tool_use block coming back
        // from the model is dropped, not interpreted. extractText handles
        // this by filtering for .text only.
        let stub = StubProvider()
        stub.response = ("end_turn", [
            .toolUse(id: "tu_1", name: "echo", input: [:]),
            .text("only this"),
            .toolResult(toolUseId: "tu_1", content: "ignored"),
        ])
        let agent = makeAgent(provider: stub)

        let result = try await agent.chat("hi")

        XCTAssertEqual(result, "only this")
    }

    func testReturnsEmptyStringWhenNoTextBlocks() async throws {
        let stub = StubProvider()
        stub.response = ("end_turn", [.toolUse(id: "x", name: "y", input: [:])])
        let agent = makeAgent(provider: stub)

        // XCTAssertEqual's @autoclosure can't contain `await`, so evaluate
        // first then assert.
        let result = try await agent.chat("hi")
        XCTAssertEqual(result, "")
    }

    func testPropagatesTransientErrorAfterRetriesExhausted() async throws {
        // The underlying APIClient retries TransientError up to maxAttempts
        // times. After exhaustion, the error propagates to Agent.chat.
        final class AlwaysFailing: LLMProvider {
            let name = "x"; let modelId = "x"; let apiKeySource = "x"
            func performRequest(messages: [Message],
                                tools: [[String: Any]]?,
                                systemPrompt: String?,
                                forcedTool: ForcedTool?)
            async throws -> (stopReason: String, content: [ContentBlock]) {
                throw TransientError(kind: "HTTP 503", body: "stub")
            }
        }
        let client = APIClient(
            provider: AlwaysFailing(),
            maxAttempts: 2,
            backoffSeconds: { _ in 0 }
        )
        let agent = AgentFactory.make(client: client)

        do {
            _ = try await agent.chat("hi")
            XCTFail("expected throw")
        } catch let error as TransientError {
            XCTAssertEqual(error.kind, "HTTP 503")
        }
    }
}

// MARK: - Agent.providerInfo

final class AgentProviderInfoTests: XCTestCase {

    func testTranslatesBootInfoToProviderInfo() {
        let stub = StubProvider(
            name: "Anthropic",
            modelId: "claude-sonnet-4-6",
            apiKeySource: "keychain (Touch ID)"
        )
        let agent = makeAgent(provider: stub)

        let info = agent.providerInfo

        XCTAssertEqual(info.providerName, "Anthropic")
        XCTAssertEqual(info.modelId, "claude-sonnet-4-6")
        XCTAssertEqual(info.apiKeySource, "keychain (Touch ID)")
    }

    func testProviderInfoReadsFreshOnEachAccess() {
        // BootInfo re-resolves modelId/apiKeySource from the provider on
        // each read; ProviderInfo is computed from BootInfo, so it should
        // also be fresh. Verify by mutating a property between reads.
        final class MutableProvider: LLMProvider {
            let name = "Stub"
            var _modelId = "v1"
            var modelId: String { _modelId }
            let apiKeySource = "test"
            // Return-type tuple labels must match the protocol exactly —
            // `(stopReason:content:)`, not an unlabeled tuple.
            func performRequest(messages: [Message],
                                tools: [[String: Any]]?,
                                systemPrompt: String?,
                                forcedTool: ForcedTool?)
            async throws -> (stopReason: String, content: [ContentBlock]) {
                ("end_turn", [.text("")])
            }
        }
        let provider = MutableProvider()
        let client = APIClient(provider: provider, backoffSeconds: { _ in 0 })
        let agent = AgentFactory.make(client: client)

        XCTAssertEqual(agent.providerInfo.modelId, "v1")
        provider._modelId = "v2"
        XCTAssertEqual(agent.providerInfo.modelId, "v2")
    }
}
