import XCTest
@testable import AuroraConfig

// MARK: - Provider enum

final class ConfigProviderEnumTests: XCTestCase {

    func testAnthropicEnvVarName() {
        XCTAssertEqual(Config.Provider.anthropic.envVarName, "ANTHROPIC_API_KEY")
    }

    func testAnthropicKeychainAccount() {
        XCTAssertEqual(Config.Provider.anthropic.keychainAccount, "anthropic_api_key")
    }

    func testAnthropicDisplayName() {
        XCTAssertEqual(Config.Provider.anthropic.displayName, "Anthropic")
    }

    // MARK: OpenRouter (WOR-56)

    func testOpenRouterEnvVarName() {
        XCTAssertEqual(Config.Provider.openrouter.envVarName, "OPENROUTER_API_KEY")
    }

    func testOpenRouterKeychainAccount() {
        XCTAssertEqual(Config.Provider.openrouter.keychainAccount, "openrouter_api_key")
    }

    func testOpenRouterDisplayName() {
        XCTAssertEqual(Config.Provider.openrouter.displayName, "OpenRouter")
    }

    func testAllCasesIncludesBothProviders() {
        XCTAssertEqual(Set(Config.Provider.allCases), [.anthropic, .openrouter])
    }
}

// MARK: - resolveKeySource — pure priority decision

final class ConfigResolveKeySourceTests: XCTestCase {

    func testEnvWinsOverEverything() {
        XCTAssertEqual(
            Config.resolveKeySource(envHasKey: true, keychainHasItem: true, envFileExists: true),
            .env
        )
    }

    func testKeychainWinsWhenNoEnv() {
        XCTAssertEqual(
            Config.resolveKeySource(envHasKey: false, keychainHasItem: true, envFileExists: true),
            .keychain
        )
    }

    func testEnvFileWinsWhenNoEnvOrKeychain() {
        XCTAssertEqual(
            Config.resolveKeySource(envHasKey: false, keychainHasItem: false, envFileExists: true),
            .envFile
        )
    }

    func testMissingWhenNoSignalIsTrue() {
        XCTAssertEqual(
            Config.resolveKeySource(envHasKey: false, keychainHasItem: false, envFileExists: false),
            .missing
        )
    }

    func testEnvFileIgnoredWhenEnvOrKeychainProvideKey() {
        // The priority is strict — once a higher tier reports a key,
        // lower tiers don't affect the result. Pin this explicitly.
        XCTAssertEqual(
            Config.resolveKeySource(envHasKey: true, keychainHasItem: false, envFileExists: false),
            .env
        )
        XCTAssertEqual(
            Config.resolveKeySource(envHasKey: false, keychainHasItem: true, envFileExists: false),
            .keychain
        )
    }
}

// MARK: - resolveActiveProvider — pure selection precedence

final class ConfigResolveActiveProviderTests: XCTestCase {

    func testOverrideWinsOverEverything() {
        XCTAssertEqual(
            Config.resolveActiveProvider(override: .anthropic, envRaw: "openrouter", storedSelection: .openrouter),
            .anthropic
        )
    }

    func testEnvUsedWhenNoOverride() {
        XCTAssertEqual(
            Config.resolveActiveProvider(override: nil, envRaw: "openrouter", storedSelection: .anthropic),
            .openrouter
        )
    }

    func testEnvIsCaseInsensitive() {
        XCTAssertEqual(
            Config.resolveActiveProvider(override: nil, envRaw: "OpenRouter", storedSelection: nil),
            .openrouter
        )
    }

    func testInvalidEnvFallsThroughToStored() {
        XCTAssertEqual(
            Config.resolveActiveProvider(override: nil, envRaw: "bogus", storedSelection: .anthropic),
            .anthropic
        )
    }

    func testStoredUsedWhenNoOverrideOrEnv() {
        XCTAssertEqual(
            Config.resolveActiveProvider(override: nil, envRaw: nil, storedSelection: .openrouter),
            .openrouter
        )
    }

    func testNilWhenNothingSelected() {
        XCTAssertNil(
            Config.resolveActiveProvider(override: nil, envRaw: nil, storedSelection: nil)
        )
    }

    func testInvalidEnvWithNoStoredReturnsNil() {
        XCTAssertNil(
            Config.resolveActiveProvider(override: nil, envRaw: "bogus", storedSelection: nil)
        )
    }
}

// MARK: - loadKey — prompt-free short-circuit

final class ConfigLoadKeyTests: XCTestCase {

    func testLoadKeyNoOpWhenEnvAlreadySet() async {
        // When the env var is already present, loadKey must NOT touch the
        // keychain (no Touch ID prompt) and must leave the value unchanged.
        // This short-circuit is what keeps the resolved-provider read quiet
        // when a key is supplied via env / .env.
        let key = "ANTHROPIC_API_KEY"
        let saved = ProcessInfo.processInfo.environment[key]
        setenv(key, "preset-value", 1)
        defer { if let s = saved { setenv(key, s, 1) } else { unsetenv(key) } }

        await Config.loadKey(for: .anthropic)

        XCTAssertEqual(ProcessInfo.processInfo.environment[key], "preset-value")
    }
}

// MARK: - loadEnvFile — parser hardening

final class LoadEnvFileTests: XCTestCase {

    private var tmpEnvPath: String!
    private var trackedKeys: [String] = []

    override func setUp() {
        super.setUp()
        tmpEnvPath = NSTemporaryDirectory()
            .appending("aurora-loadenv-test-\(UUID().uuidString).env")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpEnvPath)
        for key in trackedKeys { unsetenv(key) }
        trackedKeys = []
        super.tearDown()
    }

    private func writeEnv(_ contents: String) {
        try! contents.write(toFile: tmpEnvPath, atomically: true, encoding: .utf8)
    }

    /// Register a key for unsetenv() in tearDown so the test doesn't leak
    /// state into sibling tests.
    private func track(_ key: String) -> String {
        trackedKeys.append(key)
        return key
    }

    // happy path -----------------------------------------------------

    func testReadsSimpleKeyValuePair() {
        let key = track("AURORA_TEST_SIMPLE")
        writeEnv("\(key)=hello")
        loadEnvFile(tmpEnvPath)
        XCTAssertEqual(ProcessInfo.processInfo.environment[key], "hello")
    }

    func testSkipsBlankLinesAndComments() {
        let key = track("AURORA_TEST_AFTER_NOISE")
        writeEnv("""

        # this is a comment
        # another one

        \(key)=value

        """)
        loadEnvFile(tmpEnvPath)
        XCTAssertEqual(ProcessInfo.processInfo.environment[key], "value")
    }

    // quote stripping ------------------------------------------------

    func testStripsDoubleQuotes() {
        let key = track("AURORA_TEST_DQUOTE")
        writeEnv("\(key)=\"hello world\"")
        loadEnvFile(tmpEnvPath)
        XCTAssertEqual(ProcessInfo.processInfo.environment[key], "hello world")
    }

    func testStripsSingleQuotes() {
        let key = track("AURORA_TEST_SQUOTE")
        writeEnv("\(key)='hello world'")
        loadEnvFile(tmpEnvPath)
        XCTAssertEqual(ProcessInfo.processInfo.environment[key], "hello world")
    }

    func testDoesNotStripUnmatchedQuotes() {
        let key = track("AURORA_TEST_UNMATCHED")
        writeEnv("\(key)=\"hello'")
        loadEnvFile(tmpEnvPath)
        XCTAssertEqual(ProcessInfo.processInfo.environment[key], "\"hello'")
    }

    func testHandlesEmptyQuotedValue() {
        let key = track("AURORA_TEST_EMPTY")
        writeEnv("\(key)=\"\"")
        loadEnvFile(tmpEnvPath)
        XCTAssertEqual(ProcessInfo.processInfo.environment[key], "")
    }

    // key-shape gate -------------------------------------------------

    func testRejectsExportPrefix() {
        // `export FOO=bar` produces key "export FOO" which fails the regex.
        let key = "AURORA_TEST_EXPORT_REJECTED"
        trackedKeys.append(key) // in case the test fails and the var got set
        writeEnv("export \(key)=should_not_be_set")
        loadEnvFile(tmpEnvPath)
        XCTAssertNil(ProcessInfo.processInfo.environment[key])
    }

    func testRejectsKeyContainingSpace() {
        // The regex requires identifier shape; spaces aren't allowed.
        let badKey = "AURORA TEST WITH SPACES"
        writeEnv("\(badKey)=value")
        loadEnvFile(tmpEnvPath)
        XCTAssertNil(ProcessInfo.processInfo.environment[badKey])
    }

    func testRejectsLineWithoutEquals() {
        let key = track("AURORA_TEST_NO_EQUALS")
        writeEnv("\(key)_LINE_WITH_NO_EQUALS")
        loadEnvFile(tmpEnvPath)
        XCTAssertNil(ProcessInfo.processInfo.environment[key])
    }

    // priority -------------------------------------------------------

    func testExistingEnvVarIsNotOverridden() {
        let key = track("AURORA_TEST_PRESET")
        setenv(key, "preset-value", 1)
        writeEnv("\(key)=file-value")
        loadEnvFile(tmpEnvPath)
        XCTAssertEqual(
            ProcessInfo.processInfo.environment[key],
            "preset-value",
            "existing env should win over .env file"
        )
    }

    // missing file ---------------------------------------------------

    func testMissingFileIsSilentNoOp() {
        let nonexistent = NSTemporaryDirectory().appending("definitely-not-there-\(UUID().uuidString).env")
        // Should not throw or crash.
        loadEnvFile(nonexistent)
    }

    // SECURITY — the core "treat the file as data, never source it" test

    func testCommandSubstitutionStoredAsLiteralString() {
        // The canary: if any code path shell-evaluates the value, `touch`
        // would create this file. We assert (a) the env var contains the
        // literal text and (b) the canary file was NOT created.
        let key = track("AURORA_TEST_INJECTION")
        let canary = NSTemporaryDirectory().appending("aurora-injection-canary-\(UUID().uuidString)")
        let payload = "$(touch \(canary))"
        writeEnv("\(key)=\(payload)")

        loadEnvFile(tmpEnvPath)

        XCTAssertEqual(
            ProcessInfo.processInfo.environment[key],
            payload,
            "value must be stored literally, not shell-evaluated"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: canary),
            "canary file exists — somewhere in the parse path a shell evaluated the substitution"
        )
        // belt-and-suspenders cleanup if the assertion above ever flips
        try? FileManager.default.removeItem(atPath: canary)
    }

    func testVariableExpansionStoredAsLiteralString() {
        // `${HOME}` should NOT be expanded — the bash parser rejects expansion,
        // and the Swift parser inherits that property because setenv doesn't
        // re-evaluate.
        let key = track("AURORA_TEST_VAR_EXPANSION")
        writeEnv("\(key)=${HOME}/foo")
        loadEnvFile(tmpEnvPath)
        XCTAssertEqual(ProcessInfo.processInfo.environment[key], "${HOME}/foo")
    }
}

// MARK: - Integration — real keychain + env, with cleanup

final class ConfigIntegrationTests: XCTestCase {

    private let provider: Config.Provider = .anthropic

    override func setUp() {
        super.setUp()
        Config.clearAPIKey(for: provider)
        unsetenv(provider.envVarName)
    }

    override func tearDown() {
        Config.clearAPIKey(for: provider)
        unsetenv(provider.envVarName)
        super.tearDown()
    }

    func testSetAPIKeyMakesKeySourceKeychain() throws {
        try Config.setAPIKey(for: provider, "secret")
        XCTAssertEqual(Config.keySource(for: provider), .keychain)
    }

    func testClearAPIKeyRemovesKeychainSource() throws {
        try Config.setAPIKey(for: provider, "secret")
        Config.clearAPIKey(for: provider)
        XCTAssertNotEqual(Config.keySource(for: provider), .keychain)
    }

    func testEnvVarWinsOverKeychainEndToEnd() throws {
        try Config.setAPIKey(for: provider, "from-keychain")
        setenv(provider.envVarName, "from-env", 1)
        XCTAssertEqual(Config.keySource(for: provider), .env)
    }
}
