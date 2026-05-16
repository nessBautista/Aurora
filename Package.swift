// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "aurora",
    platforms: [.macOS(.v14)],
    // The Homebrew formula, integration tests (which spawn `.build/<config>/aurora`),
    // and any user shell aliases all key off the product name — not the target.
    products:[
        .executable(name: "aurora", targets: ["AuroraCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // Application layer
        // Tier 1. End-user CLI executable.
        .executableTarget(
            name: "AuroraCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Application/AuroraCLI"
        ),
        .testTarget(
            name: "auroraIntegrationTests"
        ),
    ]
)
