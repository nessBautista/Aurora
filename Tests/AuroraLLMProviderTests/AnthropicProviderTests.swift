import XCTest
@testable import AuroraLLMProvider
import AuroraModels

final class AnthropicProviderTests: XCTestCase {

    private var session: URLSession!
    private let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let envKey = "ANTHROPIC_API_KEY"
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

    private func ok(stopReason: String = "end_turn", text: String = "hi") -> Data {
        let json: [String: Any] = [
            "stop_reason": stopReason,
            "content": [["type": "text", "text": text]],
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: messagesURL, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private func provider() -> AnthropicProvider {
        AnthropicProvider(urlSession: session)
    }

    private let userPing = [Message(role: "user", content: [.text("ping")])]

    // MARK: - Request shape

    func testRequestUrlMethodAndHeaders() async throws {
        setenv(envKey, "sk-test", 1)
        HTTPStub.handler = { _ in (self.http(200), self.ok()) }

        _ = try await provider().performRequest(messages: userPing, tools: nil, systemPrompt: nil)

        XCTAssertEqual(HTTPStub.capturedRequests.count, 1)
        let req = HTTPStub.capturedRequests[0]
        XCTAssertEqual(req.url, messagesURL)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(req.value(forHTTPHeaderField: "content-type"), "application/json")
    }

    func testRequestBodyShape() async throws {
        HTTPStub.handler = { _ in (self.http(200), self.ok()) }

        _ = try await provider().performRequest(messages: userPing, tools: nil, systemPrompt: nil)

        let bodyData = try XCTUnwrap(HTTPStub.bodyData(from: HTTPStub.capturedRequests[0]))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertNotNil(body["model"])
        XCTAssertNotNil(body["max_tokens"])
        XCTAssertNotNil(body["messages"])
        // Optional fields not passed → not present in body.
        XCTAssertNil(body["tools"])
        XCTAssertNil(body["system"])
    }

    // MARK: - Tool-use coercion (forcedTool)

    func testForcedToolAddsToolChoiceAndStrictToolToBody() async throws {
        HTTPStub.handler = { _ in (self.http(200), self.ok()) }

        let schema: [String: Any] = [
            "type": "object",
            "properties": ["build_succeeded": ["type": "boolean"]] as [String: Any],
            "required": ["build_succeeded"],
            "additionalProperties": false,
        ]
        let forced = ForcedTool(name: "submit_state", schema: schema)

        _ = try await provider().performRequest(
            messages: userPing,
            tools: nil,
            systemPrompt: nil,
            forcedTool: forced
        )

        let bodyData = try XCTUnwrap(HTTPStub.bodyData(from: HTTPStub.capturedRequests[0]))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        // tool_choice forces the named tool with disable_parallel_tool_use=true.
        let toolChoice = try XCTUnwrap(body["tool_choice"] as? [String: Any])
        XCTAssertEqual(toolChoice["type"] as? String, "tool")
        XCTAssertEqual(toolChoice["name"] as? String, "submit_state")
        XCTAssertEqual(toolChoice["disable_parallel_tool_use"] as? Bool, true)

        // tools array contains the synthesized strict tool definition.
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        let synth = tools[0]
        XCTAssertEqual(synth["name"] as? String, "submit_state")
        XCTAssertEqual(synth["strict"] as? Bool, true)
        XCTAssertNotNil(synth["description"])
        let inputSchema = try XCTUnwrap(synth["input_schema"] as? [String: Any])
        XCTAssertEqual(inputSchema["type"] as? String, "object")
        XCTAssertEqual(inputSchema["additionalProperties"] as? Bool, false)
    }

    func testForcedToolIsAppendedAlongsideRegularTools() async throws {
        // Coercion mode must not replace the agent's regular tool schemas —
        // Anthropic requires the forced tool be present in the tools array,
        // but other tools the agent had access to earlier in the loop must
        // remain available so the model can reference them in its reasoning.
        HTTPStub.handler = { _ in (self.http(200), self.ok()) }

        let regularTools: [[String: Any]] = [
            ["name": "echo", "description": "echo", "input_schema": ["type": "object"] as [String: Any]],
        ]
        let forced = ForcedTool(
            name: "submit_state",
            schema: ["type": "object", "additionalProperties": false]
        )

        _ = try await provider().performRequest(
            messages: userPing,
            tools: regularTools,
            systemPrompt: nil,
            forcedTool: forced
        )

        let bodyData = try XCTUnwrap(HTTPStub.bodyData(from: HTTPStub.capturedRequests[0]))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, ["echo", "submit_state"])
    }

    func testNoForcedToolMeansNoToolChoiceInBody() async throws {
        // Default 3-arg call shape must not introduce a tool_choice key.
        HTTPStub.handler = { _ in (self.http(200), self.ok()) }

        _ = try await provider().performRequest(
            messages: userPing,
            tools: nil,
            systemPrompt: nil,
            forcedTool: nil
        )

        let bodyData = try XCTUnwrap(HTTPStub.bodyData(from: HTTPStub.capturedRequests[0]))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertNil(body["tool_choice"])
    }

    // MARK: - 200 parsing

    func testParses200Response() async throws {
        HTTPStub.handler = { _ in (self.http(200), self.ok(stopReason: "end_turn", text: "hello world")) }

        let (stop, content) = try await provider().performRequest(
            messages: userPing, tools: nil, systemPrompt: nil
        )

        XCTAssertEqual(stop, "end_turn")
        XCTAssertEqual(extractText(content), "hello world")
    }

    // MARK: - Transient errors

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

    func testThrowsOverloadedAsTransient() async throws {
        // The body-based overloaded check is the fallback for cases where the
        // status code itself isn't 429/5xx but the payload signals overload.
        // Use a 4xx outside 429 so the status checks fall through and the
        // body check fires.
        let body = #"{"error":{"type":"overloaded_error","message":"slow down"}}"#
        HTTPStub.handler = { _ in (self.http(400), Data(body.utf8)) }
        await XCTAssertThrowsTransient(kind: "overloaded") {
            _ = try await self.provider().performRequest(messages: self.userPing, tools: nil, systemPrompt: nil)
        }
    }

    // MARK: - BadResponse

    func testThrowsBadResponseOn200WithMissingFields() async throws {
        HTTPStub.handler = { _ in (self.http(200), Data(#"{"foo":"bar"}"#.utf8)) }

        do {
            _ = try await provider().performRequest(messages: userPing, tools: nil, systemPrompt: nil)
            XCTFail("expected throw")
        } catch let error as BadResponse {
            XCTAssertEqual(error.provider, "Anthropic")
            XCTAssertTrue(error.detail.contains("missing"))
        }
    }

    // MARK: - Model id resolution

    func testCheapModelEnvWinsOverDefaultModelEnv() {
        // Save + clean both vars so the test is deterministic.
        let savedCheap = ProcessInfo.processInfo.environment["ANTHROPIC_CHEAP_MODEL_ID"]
        let savedDefault = ProcessInfo.processInfo.environment["ANTHROPIC_MODEL_ID"]
        defer {
            if let s = savedCheap { setenv("ANTHROPIC_CHEAP_MODEL_ID", s, 1) }
            else { unsetenv("ANTHROPIC_CHEAP_MODEL_ID") }
            if let s = savedDefault { setenv("ANTHROPIC_MODEL_ID", s, 1) }
            else { unsetenv("ANTHROPIC_MODEL_ID") }
        }

        setenv("ANTHROPIC_MODEL_ID", "claude-sonnet-4-6", 1)
        setenv("ANTHROPIC_CHEAP_MODEL_ID", "claude-haiku-4-5-20251001", 1)
        XCTAssertEqual(provider().modelId, "claude-haiku-4-5-20251001")

        // With cheap unset, falls back to ANTHROPIC_MODEL_ID.
        unsetenv("ANTHROPIC_CHEAP_MODEL_ID")
        XCTAssertEqual(provider().modelId, "claude-sonnet-4-6")
    }

    // MARK: - Non-transient HTTP errors fail fast

    func testThrowsNonTransientWithoutRetry() async throws {
        HTTPStub.handler = { _ in (self.http(401), Data("invalid x-api-key".utf8)) }

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
