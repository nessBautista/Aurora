import XCTest
@testable import AuroraLLMProvider
import AuroraModels

/// Exercises `APIClient`'s retry loop in isolation by injecting a stub
/// `LLMProvider` that counts attempts and decides what to throw. The
/// `backoffSeconds: { _ in 0 }` injection keeps the test instant — no real
/// 2s/4s sleeps.
final class APIClientRetryTests: XCTestCase {

    /// Throws TransientError the first `throwCount` times, then succeeds.
    private final class StubProvider: LLMProvider {
        let name = "Stub"
        let modelId = "stub-model"
        let apiKeySource = "test"

        let throwCount: Int
        var attempts = 0

        init(throwCount: Int) { self.throwCount = throwCount }

        func performRequest(
            messages: [Message],
            tools: [[String: Any]]?,
            systemPrompt: String?,
            forcedTool: ForcedTool?
        ) async throws -> (stopReason: String, content: [ContentBlock]) {
            attempts += 1
            if attempts <= throwCount {
                throw TransientError(kind: "HTTP 503", body: "stub")
            }
            return ("end_turn", [.text("ok")])
        }
    }

    /// Always throws a non-transient error.
    private final class NonTransientProvider: LLMProvider {
        let name = "NonTransient"
        let modelId = "x"
        let apiKeySource = "test"
        var attempts = 0

        func performRequest(
            messages: [Message],
            tools: [[String: Any]]?,
            systemPrompt: String?,
            forcedTool: ForcedTool?
        ) async throws -> (stopReason: String, content: [ContentBlock]) {
            attempts += 1
            throw NSError(domain: "test", code: 401, userInfo: nil)
        }
    }

    private let userPing = [Message(role: "user", content: [.text("hi")])]

    func testRetriesAndSucceedsBeforeLimit() async throws {
        let stub = StubProvider(throwCount: 2)
        let client = APIClient(provider: stub, backoffSeconds: { _ in 0 })

        let (stop, content) = try await client.callAPI(messages: userPing)

        XCTAssertEqual(stub.attempts, 3)            // 2 throws + 1 success
        XCTAssertEqual(stop, "end_turn")
        XCTAssertEqual(extractText(content), "ok")
    }

    func testGivesUpAfterMaxAttempts() async throws {
        let stub = StubProvider(throwCount: 99)     // never succeeds
        let client = APIClient(provider: stub, backoffSeconds: { _ in 0 })

        do {
            _ = try await client.callAPI(messages: userPing)
            XCTFail("expected throw")
        } catch let error as TransientError {
            XCTAssertEqual(stub.attempts, 5)        // exactly maxAttempts
            XCTAssertEqual(error.kind, "HTTP 503")
        }
    }

    func testDoesNotRetryNonTransient() async throws {
        let stub = NonTransientProvider()
        let client = APIClient(provider: stub, backoffSeconds: { _ in 0 })

        do {
            _ = try await client.callAPI(messages: userPing)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(stub.attempts, 1)        // no retry
            XCTAssertEqual((error as NSError).code, 401)
        }
    }

    func testRespectsCustomMaxAttempts() async throws {
        // maxAttempts is injectable — verify the bound actually drives the loop.
        let stub = StubProvider(throwCount: 99)
        let client = APIClient(provider: stub, maxAttempts: 2, backoffSeconds: { _ in 0 })

        do {
            _ = try await client.callAPI(messages: userPing)
            XCTFail("expected throw")
        } catch is TransientError {
            XCTAssertEqual(stub.attempts, 2)
        }
    }
}
