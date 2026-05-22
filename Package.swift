// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "aurora",
    platforms: [.macOS(.v14)],
    // The Homebrew formula, integration tests (which spawn `.build/<config>/aurora`),
    // and any user shell aliases all key off the product name — not the target.
    products: [
        .executable(name: "aurora", targets: ["AuroraCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // ── Application ────────────────────────────────
        // ── Tier 1 ─────────────────────────────────────
        .executableTarget(
            name: "AuroraCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Application/AuroraCLI"
        ),
        // ── Execution ──────────────────────────────────
        // ── Tier 2 ─────────────────────────────────────
            .target(
                name: "AuroraAgent",
                dependencies: ["AuroraLLMProvider", "AuroraConfig"],
                path: "Sources/Execution/AuroraAgent"
            ),
        // ── Tier 3 ─────────────────────────────────────
        // LLM provider port + Anthropic adapter. Depends on Tier 4
        // only (Models for the wire format; Config for credentials).
            .target(
                name: "AuroraLLMProvider",
                dependencies: ["AuroraModels", "AuroraConfig"],
                path: "Sources/Execution/AuroraLLMProvider"
            ),                
        // ── Execution ──────────────────────────────────
        // ── Tier 4 ─────────────────────────────────────
        // Three primitives in a downward chain.
        // Keychain ← Config ← Settings. No upward edges, no cycles.
        .target(
            name: "AuroraKeychain",
            path: "Sources/Execution/AuroraKeychain"
        ),
        .target(
            name: "AuroraConfig",
            dependencies: ["AuroraKeychain"],
            path: "Sources/Execution/AuroraConfig"
        ),
        .target(
            name: "AuroraSettings",
            dependencies: ["AuroraConfig"],
            path: "Sources/Execution/AuroraSettings"
        ),
        .target(
            name: "AuroraModels",
            path: "Sources/Execution/AuroraModels"
        ),
        // ── Tests ───────────────────────────────────────────────
        // Note: `AuroraCLI` is an executableTarget and Xcode cannot run
        // XCTest tests linked against an executable target, so CLI
        // coverage lives only in `auroraIntegrationTests` (spawns the
        // built binary as a subprocess). Do not add an `auroraTests`
        // target depending on `AuroraCLI`.
        .testTarget(
            name: "auroraIntegrationTests"
        ),
        .testTarget(
            name: "AuroraKeychainTests",
            dependencies: ["AuroraKeychain"]
        ),
       .testTarget(
           name: "AuroraConfigTests",
           dependencies: ["AuroraConfig"]
       ),
       .testTarget(
           name: "AuroraSettingsTests",
           dependencies: ["AuroraSettings"]
       ),
       .testTarget(
           name: "AuroraModelsTests",
           dependencies: ["AuroraModels"]
       ),
       .testTarget(
           name: "AuroraLLMProviderTests",
           dependencies: ["AuroraLLMProvider", "AuroraModels"]
       ),
        .testTarget(
            name: "AuroraAgentTests",
            dependencies: ["AuroraAgent", "AuroraLLMProvider", "AuroraModels"]
        ),
    ]
)
