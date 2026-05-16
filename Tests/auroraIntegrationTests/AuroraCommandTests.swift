import XCTest

/// Integration tests for the root `aurora` command — flags, help text,
/// and behavior that isn't tied to a specific subcommand. Subcommand
/// tests live in their own files (e.g., HelloCommandTests).
final class AuroraCommandTests: XCTestCase {

    func testVersionFlagPrintsVersionString() throws {
        let result = try runAurora(args: ["--version"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutTrimmed, "0.0.1-dev")
    }

    func testHelpMentionsVersionFlag() throws {
        let result = try runAurora(args: ["--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("--version"),
                      "stdout was: \(result.stdout)")
    }
}
