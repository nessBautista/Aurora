import Foundation

/// Reads a `.env` file at `path` and sets every `KEY=value` line as an
/// environment variable, unless that variable is already set in the process
/// (existing env wins — keeps `env > .env` priority consistent).
///
/// Parsing discipline mirrors the bash reference parser in
/// `scripts/bump-tap.sh`: the file is read as data, never sourced. Values
/// reach `setenv` as literal bytes, so command-substitution payloads like
/// `$(rm -rf ~)` end up as inert strings rather than executed code — the
/// "treat the file as data" principle this module is built around.
///
/// - Keys must match `[A-Za-z_][A-Za-z0-9_]*` (POSIX identifier shape).
///   Lines that fail this — including `export KEY=val`, leading whitespace
///   in the key, or stray text before `=` — are logged to stderr and skipped.
/// - Values surrounded by matching single or double quotes have those quotes
///   stripped. Whitespace inside quotes is preserved.
/// - If the post-quote value starts with `op://`, it's resolved via 1Password's
///   `op read` CLI.
/// - Silent no-op if the file doesn't exist.
///
/// `internal` — only `Config.loadInto` calls this. Tests reach it via
/// `@testable import AuroraConfig` if needed.
func loadEnvFile(_ path: String) {
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
    let keyPattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#
    for line in contents.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        let parts = trimmed.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else {
            warnMalformed(line: line, path: path)
            continue
        }
        let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
        guard key.range(of: keyPattern, options: .regularExpression) != nil else {
            warnMalformed(line: line, path: path)
            continue
        }
        var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2) ||
           (value.hasPrefix("'")  && value.hasSuffix("'")  && value.count >= 2) {
            value = String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("op://") {
            value = opRead(value)
        }
        if ProcessInfo.processInfo.environment[key] == nil {
            setenv(key, value, 1)
        }
    }
}

/// Write a one-line warning to stderr about a malformed `.env` line.
/// Matches the wording of the bash reference parser so users see the same
/// message whether the file is read by Aurora or by `bump-tap.sh`.
private func warnMalformed(line: String, path: String) {
    let msg = "✗ ignoring malformed line in \(path): \(line)\n"
    FileHandle.standardError.write(Data(msg.utf8))
}
