import XCTest

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var stdoutTrimmed: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Spawns the built `aurora` binary as a subprocess and captures its
/// exit code, stdout, and stderr. Used by every integration test class.
///
/// `env:` lets tests deterministically control individual environment
/// variables for the subprocess. Semantics: the parent process's env is
/// inherited as a base, then `env` overrides are layered on top. Empty
/// string is a *value* (POSIX "set to empty"), not "unset" — to make a
/// var look truly absent, the caller has to skip the test when the
/// parent has it set, because we can't unset what we never set.
func runAurora(args: [String], env: [String: String]? = nil) throws -> ProcessResult {
    let binary = try locateBinary()
    let process = Process()
    process.executableURL = binary
    process.arguments = args

    if let overrides = env {
        var merged = ProcessInfo.processInfo.environment
        for (key, value) in overrides { merged[key] = value }
        process.environment = merged
    }

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
