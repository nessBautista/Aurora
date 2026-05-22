import XCTest
@testable import AuroraAgent
@testable import AuroraConfig

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

// Storage round-trip (setKey/clearKey/keyStatus actually hitting keychain
// + env) lives at AuroraKeychainTests and AuroraConfigTests. AuroraAgent
// only owns the Tier-2-to-Tier-4 translation; the underlying storage is
// covered at its own tier.
