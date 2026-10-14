// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SearcheXtra",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SearcheXtra",
            path: "Sources/SearcheXtra",
            resources: [.copy("Resources/Translations.json"), .copy("Resources/AppIcon.png"), .copy("Resources/FlowDrag.js")],
            // Same reasoning as the canvas app next door: the whole interface is
            // main-thread by nature, and Swift 6's strict isolation buys nothing
            // here but ceremony.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SearcheXtraTests",
            dependencies: ["SearcheXtra"],
            path: "Tests/SearcheXtraTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
