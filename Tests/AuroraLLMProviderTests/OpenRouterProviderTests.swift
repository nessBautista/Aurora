import XCTest
@testable import AuroraLLMProvider
import AuroraModels

final class OpenRouterProviderTests: XCTestCase {

    private var session: URLSession!
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let envKey = "OPENROUTER_API_KEY"
    private var savedEnv: String?

    override func setUp() {
        super.setUp()
        HTTPStub.reset()
        session = HTTPStub.makeSession()
        savedEnv = ProcessInfo.processInfo.environment[envKey]
        unsetenv(envKey)
    }

    override func tearDown() {
        HTTPStub.reset()
        session = nil
        if let saved = savedEnv {
            setenv(envKey, saved, 1)
        } else {
            unsetenv(envKey)
        }
        super.tearDown()
    }

    // MARK: - Helpers

    /// OpenAI-shaped 200 body: choices[0].message.content + finish_reason.
    private func ok(content: String = "hi", finishReason: String = "stop") -> Data {
        let json: [String: Any] = [
            "id": "test-id",
            "model": "anthropic/claude-sonnet-4.6",
            "choices": [[
                "message": ["role": "assistant", "content": content],
                "finish_reason": finishReason,
            ]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2],
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private func provider() -> OpenRouterProvider {
        OpenRouterProvider(urlSession: session)
    }

    private let userPing = [Message(role: "user", content: [.text("ping")])]

    // MARK: - Request shape

    func testRequestUrlMethodAndHeaders() async throws {
        setenv(envKey, "sk-or-test", 1)
        HTTPStub.handler = { _ in (self.http(200), self.ok()) }

        _ = try await provider().performRequest(messages: userPing, tools: nil, systemPrompt: nil)

        XCTAssertEqual(HTTPStub.capturedRequests.count, 1)
        let req = HTTPStub.capturedRequests[0]
        XCTAssertEqual(req.url, endpoint)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        // Attribution headers are sent (optional, but present in our requests).
        XCTAssertNotNil(req.value(forHTTPHeaderField: "HTTP-Referer"))
        XCTAssertNotNil(req.value(forHTTPHeaderField: "X-Title"))
    }

    func testRequestBodyHasOpenAIShape() async throws {
        HTTPStub.handler = { _ in (self.http(200), self.ok()) }

        _ = try await provider().performRequest(messages: userPing, tools: nil, systemPrompt: nil)

        let bodyData = try XCTUnwrap(HTTPStub.bodyData(from: HTTPStub.capturedRequests[0]))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertNotNil(body["model"])
        XCTAssertNotNil(body["max_completion_tokens"])
        XCTAssertNil(body["max_tokens"])   // we send the forward-compatible field only
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        // OpenAI shape: content is a string, not an array of blocks.
        XCTAssertEqual(messages[0]["content"] as? String, "ping")
    }

    func testSystemPromptInsertedAsLeadingSystemMessage() async throws {
        HTTPStub.handler = { _ in (self.http(200), self.ok()) }

        _ = try await provider().performRequest(
            messages: userPing, tools: nil, systemPrompt: "You are helpful."
        )

        let bodyData = try XCTUnwrap(HTTPStub.bodyData(from: HTTPStub.capturedRequests[0]))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "You are helpful.")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
    }

    func testNoTopLevelSystemFieldEvenWithSystemPrompt() async throws {
        // OpenAI uses messages[0].role=="system", NOT a top-level "system"
        // field. Make sure we didn't accidentally port Anthropic's shape.
        HTTPStub.handler = { _ in (self.http(200), self.ok()) }

        _ = try await provider().performRequest(
            messages: userPing, tools: nil, systemPrompt: "You are helpful."
        )

        let bodyData = try XCTUnwrap(HTTPStub.bodyData(from: HTTPStub.capturedRequests[0]))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertNil(body["system"])
    }

    // MARK: - 200 parsing

    func testParses200Response() async throws {
        HTTPStub.handler = { _ in (self.http(200), self.ok(content: "hello world", finishReason: "stop")) }

        let (stop, content) = try await provider().performRequest(
            messages: userPing, tools: nil, systemPrompt: nil
        )

        XCTAssertEqual(stop, "end_turn")               // stop → end_turn
        XCTAssertEqual(extractText(content), "hello world")
    }

    func testFinishReasonLengthMapsToMaxTokens() async throws {
        HTTPStub.handler = { _ in (self.http(200), self.ok(content: "...", finishReason: "length")) }
        let (stop, _) = try await provider().performRequest(messages: userPing, tools: nil, systemPrompt: nil)
        XCTAssertEqual(stop, "max_tokens")
    }

    func testUnknownFinishReasonPassesThrough() async throws {
        HTTPStub.handler = { _ in (self.http(200), self.ok(content: "x", finishReason: "future_reason")) }
        let (stop, _) = try await provider().performRequest(messages: userPing, tools: nil, systemPrompt: nil)
        XCTAssertEqual(stop, "future_reason")
    }

    // MARK: - Transient errors

    func testThrows408AsTransient() async throws {
        HTTPStub.handler = { _ in (self.http(408), Data("timeout".utf8)) }
        await XCTAssertThrowsTransient(kind: "HTTP 408") {
            _ = try await self.provider().performRequest(messages: self.userPing, tools: nil, systemPrompt: nil)
        }
    }

    func testThrows429AsTransient() async throws {
        HTTPStub.handler = { _ in (self.http(429), Data("rate limited".utf8)) }
        await XCTAssertThrowsTransient(kind: "HTTP 429") {
            _ = try await self.provider().performRequest(messages: self.userPing, tools: nil, systemPrompt: nil)
        }
    }

    func testThrows503AsTransient() async throws {
        HTTPStub.handler = { _ in (self.http(503), Data("upstream busted".utf8)) }
        await XCTAssertThrowsTransient(kind: "HTTP 503") {
            _ = try await self.provider().performRequest(messages: self.userPing, tools: nil, systemPrompt: nil)
        }
    }

    // MARK: - 402 out-of-credits is TERMINAL, not transient

    func testInsufficientCreditsIsTerminal() async throws {
        // OpenRouter signals out-of-credits with HTTP 402 — a billing error
        // that retrying never recovers. There is no `insufficient_quota` body
        // marker (that's OpenAI's vocabulary); classification is status-code
        // only, so 402 must fall through to a non-transient throw.
        let body = #"{"error":{"code":402,"message":"insufficient credits"}}"#
        HTTPStub.handler = { _ in (self.http(402), Data(body.utf8)) }
        do {
            _ = try await provider().performRequest(messages: userPing, tools: nil, systemPrompt: nil)
            XCTFail("expected throw")
        } catch is TransientError {
            XCTFail("402 (out of credits) must NOT be transient")
        } catch {
            // Expected — provider throws a non-transient NSError.
            XCTAssertEqual(HTTPStub.capturedRequests.count, 1)
        }
    }

    // MARK: - BadResponse

    func testThrowsBadResponseOn200WithMissingFields() async throws {
        HTTPStub.handler = { _ in (self.http(200), Data(#"{"foo":"bar"}"#.utf8)) }

        do {
            _ = try await provider().performRequest(messages: userPing, tools: nil, systemPrompt: nil)
            XCTFail("expected throw")
        } catch let error as BadResponse {
            XCTAssertEqual(error.provider, "OpenRouter")
            XCTAssertTrue(error.detail.contains("choices") || error.detail.contains("content"))
        }
    }

    // MARK: - Model id resolution

    func testCheapModelEnvWinsOverDefault() {
        let savedCheap = ProcessInfo.processInfo.environment["OPENROUTER_CHEAP_MODEL_ID"]
        let savedDefault = ProcessInfo.processInfo.environment["OPENROUTER_MODEL_ID"]
        defer {
            if let s = savedCheap { setenv("OPENROUTER_CHEAP_MODEL_ID", s, 1) }
            else { unsetenv("OPENROUTER_CHEAP_MODEL_ID") }
            if let s = savedDefault { setenv("OPENROUTER_MODEL_ID", s, 1) }
            else { unsetenv("OPENROUTER_MODEL_ID") }
        }

        setenv("OPENROUTER_MODEL_ID", "anthropic/claude-sonnet-4.6", 1)
        setenv("OPENROUTER_CHEAP_MODEL_ID", "anthropic/claude-haiku-4.5", 1)
        XCTAssertEqual(provider().modelId, "anthropic/claude-haiku-4.5")

        unsetenv("OPENROUTER_CHEAP_MODEL_ID")
        XCTAssertEqual(provider().modelId, "anthropic/claude-sonnet-4.6")
    }

    func testDefaultModelWhenNoEnvSet() {
        let savedCheap = ProcessInfo.processInfo.environment["OPENROUTER_CHEAP_MODEL_ID"]
        let savedDefault = ProcessInfo.processInfo.environment["OPENROUTER_MODEL_ID"]
        let savedLegacy = ProcessInfo.processInfo.environment["MODEL_ID"]
        defer {
            if let s = savedCheap { setenv("OPENROUTER_CHEAP_MODEL_ID", s, 1) }
            else { unsetenv("OPENROUTER_CHEAP_MODEL_ID") }
            if let s = savedDefault { setenv("OPENROUTER_MODEL_ID", s, 1) }
            else { unsetenv("OPENROUTER_MODEL_ID") }
            if let s = savedLegacy { setenv("MODEL_ID", s, 1) }
            else { unsetenv("MODEL_ID") }
        }

        unsetenv("OPENROUTER_CHEAP_MODEL_ID")
        unsetenv("OPENROUTER_MODEL_ID")
        unsetenv("MODEL_ID")
        XCTAssertEqual(provider().modelId, "anthropic/claude-sonnet-4.6")
    }

    // MARK: - Non-transient HTTP errors fail fast

    func testThrowsNonTransientWithoutRetry() async throws {
        HTTPStub.handler = { _ in (self.http(401), Data("invalid api key".utf8)) }

        do {
            _ = try await provider().performRequest(messages: userPing, tools: nil, systemPrompt: nil)
            XCTFail("expected throw")
        } catch is TransientError {
            XCTFail("401 should not be transient")
        } catch {
            // Expected — provider throws NSError; APIClient's retry loop won't retry it.
            XCTAssertEqual(HTTPStub.capturedRequests.count, 1)
        }
    }

    // MARK: - Tools / forcedTool not driven yet

    func testToolsAndForcedToolAreNotSentInRequestBody() async throws {
        // WOR-56 deliberately ignores tools and forcedTool — pin the
        // before/after contract so a future change that maps response_format
        // has to flip these assertions explicitly.
        HTTPStub.handler = { _ in (self.http(200), self.ok()) }

        let toolStub: [[String: Any]] = [
            ["name": "echo", "description": "x", "input_schema": [:] as [String: Any]],
        ]
        let forcedStub = ForcedTool(name: "submit_state", schema: [:])

        _ = try await provider().performRequest(
            messages: userPing, tools: toolStub, systemPrompt: nil, forcedTool: forcedStub
        )

        let bodyData = try XCTUnwrap(HTTPStub.bodyData(from: HTTPStub.capturedRequests[0]))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertNil(body["tools"])
        XCTAssertNil(body["response_format"])
        XCTAssertNil(body["tool_choice"])
    }

    // MARK: - Assertion helper

    private func XCTAssertThrowsTransient(
        kind expectedKind: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: () async throws -> Void
    ) async {
        do {
            try await block()
            XCTFail("expected TransientError", file: file, line: line)
        } catch let error as TransientError {
            XCTAssertEqual(error.kind, expectedKind, file: file, line: line)
        } catch {
            XCTFail("expected TransientError, got \(error)", file: file, line: line)
        }
    }
}
