// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIProviderMenuBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "AIProviderMenuBar", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
