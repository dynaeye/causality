// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CausalityCore",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CausalityCore", targets: ["CausalityCore"]),
        .executable(name: "cs-demo", targets: ["CausalityDemo"]),
        .executable(name: "causal", targets: ["CausalCLI"]),
    ],
    targets: [
        .target(
            name: "CausalityCore",
            path: "Sources/CausalityCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "CausalityDemo",
            dependencies: ["CausalityCore"],
            path: "Sources/CausalityDemo"
        ),
        .executableTarget(
            name: "CausalCLI",
            dependencies: ["CausalityCore"],
            path: "Sources/CausalCLI"
        ),
        .testTarget(
            name: "CausalityCoreTests",
            dependencies: ["CausalityCore"],
            path: "Tests/CausalityCoreTests"
        ),
    ]
)
