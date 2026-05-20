import Foundation

/// Calls `op read <reference>` (1Password CLI) and returns the resolved value
/// with surrounding whitespace stripped.
///
/// `op` is located via `/usr/bin/env`, which walks `$PATH`. That handles
/// Apple Silicon Homebrew (`/opt/homebrew/bin/op`), Intel Homebrew
/// (`/usr/local/bin/op`), MacPorts, nix, `mise`/`asdf` shims, or any other
/// install layout — as long as `op` is on the user's `PATH`.
///
/// Called by `loadEnvFile` whenever a `.env` value starts with `op://`.
/// Argument-array invocation (no shell), so a hostile reference can't trigger
/// command substitution; the worst case is `op` itself rejecting the string.
///
/// `fatalError` on failure: if a `.env` declares an `op://` reference, the user
/// expects it to resolve. Crashing loudly with `op`'s own stderr beats silently
/// substituting an empty string and confusing downstream code.
///
/// `internal` — only `loadEnvFile` calls this. Tests reach it via
/// `@testable import AuroraConfig` if needed.
func opRead(_ reference: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["op", "read", reference]
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fatalError("Failed to launch `/usr/bin/env` to invoke `op read`: \(error)")
    }
    guard process.terminationStatus == 0 else {
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrMsg = (String(data: stderrData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // `env` exits 127 when the named program isn't on PATH; surface that
        // distinct cause separately from a real `op` failure.
        if process.terminationStatus == 127 {
            fatalError(
                "`op` not found on PATH. Install the 1Password CLI "
                + "(https://1password.com/downloads/command-line/) or remove "
                + "the `op://` reference from your .env."
            )
        }
        fatalError("`op read \(reference)` failed (exit \(process.terminationStatus)): \(stderrMsg)")
    }
    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}
