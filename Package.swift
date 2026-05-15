// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "aurora",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "aurora",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "auroraTests",
            dependencies: ["aurora"]
        ),
    ]
)
