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

    // MARK: - Subprocess helpers

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var stdoutTrimmed: String {
            stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func runAurora(args: [String]) throws -> ProcessResult {
        let binary = try locateBinary()
        let process = Process()
        process.executableURL = binary
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }

    /// Prefer the release binary (what Loop 2 should test). Fall back to
    /// debug so the same test file is runnable in Loop 1 contexts too.
    /// XCTSkip with a clear hint if neither exists.
    private func locateBinary() throws -> URL {
        let root = packageRoot()
        let release = root.appendingPathComponent(".build/release/aurora")
        let debug = root.appendingPathComponent(".build/debug/aurora")
        for candidate in [release, debug]
        where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw XCTSkip("""
            aurora binary not found. Run `swift build -c release --disable-sandbox` \
            (or `swift build`) before this test target.
            """)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // auroraIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // package root (aurora/)
    }
}
