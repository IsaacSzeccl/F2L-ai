// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Beacon",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Beacon", targets: ["Beacon"]),
        .executable(name: "beacon-spike", targets: ["BeaconSpike"]),
    ],
    targets: [
        // Pure logic: prompts, parsing, geometry, config. No AppKit, fully unit-tested.
        .target(name: "CoachCore"),
        // The macOS app: island, overlay, capture, accessibility, voice.
        .executableTarget(
            name: "Beacon",
            dependencies: ["CoachCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Week-1 model spike: replays saved snapshots against a model and scores pointing.
        .executableTarget(name: "BeaconSpike", dependencies: ["CoachCore"]),
        .testTarget(name: "CoachCoreTests", dependencies: ["CoachCore"]),
    ]
)
