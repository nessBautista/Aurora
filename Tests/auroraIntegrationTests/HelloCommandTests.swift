import XCTest

/// Subprocess-based integration tests for the built `aurora` binary.
/// Spawns `.build/release/aurora` (or debug, as fallback) and asserts
/// on stdout, stderr, and exit code.
///
/// Run with Loop 2:
///   swift build -c release --disable-sandbox
///   swift test --filter auroraIntegrationTests
final class HelloCommandTests: XCTestCase {

    func testHelloPrintsGreeting() throws {
        let result = try runAurora(args: ["hello", "world"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutTrimmed, "Hello, world!")
    }

    func testHelloHandlesMultiWordName() throws {
        let result = try runAurora(args: ["hello", "Ada Lovelace"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutTrimmed, "Hello, Ada Lovelace!")
    }

    func testHelloMissingArgumentExitsNonZero() throws {
        let result = try runAurora(args: ["hello"])
        XCTAssertNotEqual(result.exitCode, 0)
        // Note: assertion coupled to ArgumentParser's error format.
        // If its wording changes, update here.
        XCTAssertTrue(result.stderr.contains("Missing expected argument"),
                      "stderr was: \(result.stderr)")
    }

    func testHelpListsSubcommands() throws {
        let result = try runAurora(args: ["--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("hello"),
                      "stdout was: \(result.stdout)")
    }
}
