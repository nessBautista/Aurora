import XCTest

final class ChatCommandTests: XCTestCase {

    /// Gate on a real key being present in env. Skipped otherwise — CI
    /// without `ANTHROPIC_API_KEY` will not run live chat tests.
    private func skipIfNoApiKey() throws {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !key.isEmpty else {
            throw XCTSkip("ANTHROPIC_API_KEY not set; skipping live chat test.")
        }
    }

    // MARK: - happy path

    func testChatProducesNonEmptyResponse() async throws {
        try skipIfNoApiKey()
        let result = try runAurora(args: ["chat", "--provider", "anthropic", "Reply with just the word PONG."])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(
            result.stdoutTrimmed.isEmpty,
            "stdout was empty; banner went to stderr but the model reply should be on stdout"
        )
    }

    func testBannerGoesToStderrNotStdout() async throws {
        try skipIfNoApiKey()
        let result = try runAurora(args: ["chat", "--provider", "anthropic", "Reply with just the word PONG."])
        // stdout should be the model's reply only — no banner header.
        XCTAssertFalse(result.stdout.contains("─── aurora ──"))
        // stderr should carry the banner.
        XCTAssertTrue(result.stderr.contains("─── aurora ──"))
        XCTAssertTrue(result.stderr.contains("Provider:"))
        XCTAssertTrue(result.stderr.contains("Model:"))
        XCTAssertTrue(result.stderr.contains("API key:"))
    }

    // MARK: - missing key → setup hint

    func testMissingKeyEmitsSetupHint() async throws {
        // Verifies the setup-hint path. Skipped if anthropic is already
        // configured (env / keychain / .env) — we can't reliably unset a
        // parent-shell env var from the subprocess, and we don't want to
        // mutate the dev's keychain just to exercise this branch.
        let status = try runAurora(args: ["auth", "status"])
        guard status.stdout.contains("missing — run") else {
            throw XCTSkip(
                "anthropic key already configured; setup-hint path can't be exercised cleanly."
            )
        }

        let result = try runAurora(args: ["chat", "--provider", "anthropic", "hi"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("no API key configured"))
        XCTAssertTrue(result.stderr.contains("aurora auth set anthropic"))
    }

    // MARK: - provider flag validation (hermetic — fails before any network)

    func testProviderFlagRejectsUnknown() throws {
        let result = try runAurora(args: ["chat", "--provider", "bogus", "hi"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("Unknown provider") || result.stdout.contains("Unknown provider"),
            "expected ValidationError for unknown --provider; got stdout=\(result.stdout) stderr=\(result.stderr)"
        )
    }
}
