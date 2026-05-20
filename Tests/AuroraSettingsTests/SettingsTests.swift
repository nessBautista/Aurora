import XCTest
import AuroraConfig
@testable import AuroraSettings

// MARK: - Settings value type

final class SettingsValueTypeTests: XCTestCase {

    func testDefaultInitHasNilProvider() {
        XCTAssertNil(Settings().selectedProvider)
    }

    func testExplicitInitCarriesProvider() {
        XCTAssertEqual(
            Settings(selectedProvider: .anthropic).selectedProvider,
            .anthropic
        )
    }

    func testEquatable() {
        XCTAssertEqual(Settings(), Settings())
        XCTAssertEqual(
            Settings(selectedProvider: .anthropic),
            Settings(selectedProvider: .anthropic)
        )
        XCTAssertNotEqual(
            Settings(selectedProvider: .anthropic),
            Settings(selectedProvider: nil)
        )
    }
}

// MARK: - Pure codec — no UserDefaults

final class SettingsCodecTests: XCTestCase {

    func testDecodeNilRawReturnsEmptySettings() {
        XCTAssertEqual(SettingsCodec.decode(selectedProviderRaw: nil), Settings())
    }

    func testDecodeKnownRawReturnsProvider() {
        XCTAssertEqual(
            SettingsCodec.decode(selectedProviderRaw: "anthropic"),
            Settings(selectedProvider: .anthropic)
        )
    }

    func testDecodeUnknownRawReturnsEmpty() {
        // Forward-compat: a future version may write "openrouter" before
        // the current binary knows about it. Don't crash; return nil.
        XCTAssertEqual(
            SettingsCodec.decode(selectedProviderRaw: "openrouter"),
            Settings()
        )
    }

    func testEncodeEmptyHasNilRaw() {
        XCTAssertNil(SettingsCodec.encode(Settings()).selectedProviderRaw)
    }

    func testEncodeProvider() {
        XCTAssertEqual(
            SettingsCodec.encode(Settings(selectedProvider: .anthropic)).selectedProviderRaw,
            "anthropic"
        )
    }

    func testEncodeDecodeRoundTrip() {
        for input in [Settings(), Settings(selectedProvider: .anthropic)] {
            let encoded = SettingsCodec.encode(input)
            let decoded = SettingsCodec.decode(selectedProviderRaw: encoded.selectedProviderRaw)
            XCTAssertEqual(decoded, input)
        }
    }
}

// MARK: - Integration — real UserDefaults with isolated suite

final class SettingsStoreTests: XCTestCase {

    private var store: SettingsStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.aurora.test.\(UUID().uuidString)"
        store = SettingsStore(suiteName: suiteName)
    }

    override func tearDown() {
        store.reset()
        // Belt-and-suspenders: wipe the entire test domain so a crashed
        // test (or a future field we forget to handle in reset) can't
        // leak state to the next run.
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoadOnEmptyStoreReturnsNilProvider() {
        XCTAssertNil(store.load().selectedProvider)
    }

    func testSaveThenLoadRoundTripsProvider() {
        store.save(Settings(selectedProvider: .anthropic))
        XCTAssertEqual(store.load().selectedProvider, .anthropic)
    }

    func testSaveNilProviderClearsExisting() {
        store.save(Settings(selectedProvider: .anthropic))
        store.save(Settings(selectedProvider: nil))
        XCTAssertNil(store.load().selectedProvider)
    }

    func testDifferentSuiteNamesIsolateState() {
        store.save(Settings(selectedProvider: .anthropic))
        let other = SettingsStore(suiteName: "com.aurora.test.\(UUID().uuidString)")
        XCTAssertNil(other.load().selectedProvider)
    }

    func testResetWipesPersistedProvider() {
        store.save(Settings(selectedProvider: .anthropic))
        store.reset()
        XCTAssertNil(store.load().selectedProvider)
    }
}
