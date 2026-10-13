// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickPromptCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuickPromptCore", targets: ["QuickPromptCore"]),
    ],
    targets: [
        .target(name: "QuickPromptCore"),
        .testTarget(name: "QuickPromptCoreTests", dependencies: ["QuickPromptCore"]),
    ]
)
