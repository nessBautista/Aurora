import XCTest
@testable import AuroraAgent
@testable import AuroraConfig
import AuroraSettings

final class AgentAuthTranslationTests: XCTestCase {

    func testProviderTranslationCoversEveryCase() {
        // Walk every AgentAuth.Provider case and confirm toConfig maps
        // it to a Config.Provider value. When WOR-56 adds .openrouter,
        // a missing case here is a compile error.
        for provider in AgentAuth.Provider.allCases {
            let mapped: Config.Provider = AgentAuth.toConfig(provider)
            // Sanity: rawValue stays in sync — that's the contract we
            // rely on when both enums grow new cases.
            XCTAssertEqual(provider.rawValue, mapped.rawValue,
                "AgentAuth.Provider.\(provider) does not match Config.Provider rawValue")
        }
    }

    func testProviderAllCasesIncludesAnthropic() {
        XCTAssertTrue(AgentAuth.Provider.allCases.contains(.anthropic))
    }

    func testKeyStatusCasesExistAndAreDistinct() {
        // Sanity check — all four mirror cases exist and aren't accidentally
        // equal to each other. Catches a future "oops typed the wrong case
        // name" rename.
        let all: [AgentAuth.KeyStatus] = [.env, .keychain, .envFile, .missing]
        XCTAssertEqual(Set(all).count, all.count)
    }
}

// MARK: - Active provider selection (persisted via AuroraSettings)

final class AgentAuthActiveProviderTests: XCTestCase {

    private var store: SettingsStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.aurora.test.\(UUID().uuidString)"
        store = SettingsStore(suiteName: suiteName)
    }

    override func tearDown() {
        store.reset()
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testNoSelectionReturnsNil() {
        XCTAssertNil(AgentAuth.activeProviderSelection(store: store))
    }

    func testSetThenGetRoundTripsOpenRouter() {
        AgentAuth.setActiveProvider(.openrouter, store: store)
        XCTAssertEqual(AgentAuth.activeProviderSelection(store: store), .openrouter)
    }

    func testSetThenGetRoundTripsAnthropic() {
        AgentAuth.setActiveProvider(.anthropic, store: store)
        XCTAssertEqual(AgentAuth.activeProviderSelection(store: store), .anthropic)
    }

    func testOverwriteReplacesSelection() {
        AgentAuth.setActiveProvider(.anthropic, store: store)
        AgentAuth.setActiveProvider(.openrouter, store: store)
        XCTAssertEqual(AgentAuth.activeProviderSelection(store: store), .openrouter)
    }
}

// Storage round-trip (setKey/clearKey/keyStatus actually hitting keychain
// + env) lives at AuroraKeychainTests and AuroraConfigTests. AuroraAgent
// only owns the Tier-2-to-Tier-4 translation; the underlying storage is
// covered at its own tier.
