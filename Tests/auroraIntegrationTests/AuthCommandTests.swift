import XCTest

final class AuthCommandTests: XCTestCase {

    // MARK: - help

    func testAuthHelpListsSubcommands() throws {
        let result = try runAurora(args: ["auth", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("set"))
        XCTAssertTrue(result.stdout.contains("status"))
        XCTAssertTrue(result.stdout.contains("clear"))
    }

    func testAuroraHelpListsAuthAndChat() throws {
        let result = try runAurora(args: ["--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("auth"))
        XCTAssertTrue(result.stdout.contains("chat"))
        // Existing hello subcommand still listed.
        XCTAssertTrue(result.stdout.contains("hello"))
    }

    // MARK: - status

    func testStatusReportsAValidSourceForEveryProvider() throws {
        // `keySource` is metadata-only — never prompts Touch ID — so this
        // test is safe to run anywhere. It only asserts on the output's
        // *shape*: every known provider gets a row, and the row mentions
        // one of the four known sources.
        let result = try runAurora(args: ["auth", "status"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("anthropic_api_key:"))
        let validSources = ["process env", "keychain", ".env file", "missing"]
        XCTAssertTrue(
            validSources.contains { result.stdout.contains($0) },
            "stdout did not mention any known source. stdout=\(result.stdout)"
        )
    }

    func testStatusReportsEnvWhenKeyVarIsSet() throws {
        // Setting ANTHROPIC_API_KEY in the subprocess env forces the
        // "process env" branch regardless of what's in the dev's
        // keychain (env wins in Config's resolution order).
        let result = try runAurora(
            args: ["auth", "status"],
            env: ["ANTHROPIC_API_KEY": "sk-fake-test-key-not-real"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("process env"))
    }

    // MARK: - clear (idempotent)

    func testClearAnthropicIsIdempotent() throws {
        // Clearing a non-existent key is a silent no-op. Run twice and
        // expect identical success.
        let first  = try runAurora(args: ["auth", "clear", "anthropic"])
        let second = try runAurora(args: ["auth", "clear", "anthropic"])
        XCTAssertEqual(first.exitCode, 0)
        XCTAssertEqual(second.exitCode, 0)
        XCTAssertTrue(first.stdout.contains("✓"))
        XCTAssertTrue(second.stdout.contains("✓"))
    }

    // MARK: - validation

    func testRejectsUnknownProvider() throws {
        let result = try runAurora(args: ["auth", "clear", "bogus"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("Unknown provider") || result.stdout.contains("Unknown provider"),
            "expected ValidationError mentioning unknown provider; got stdout=\(result.stdout) stderr=\(result.stderr)"
        )
    }
}
