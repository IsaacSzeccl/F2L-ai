// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "F2L",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "F2L", targets: ["F2L"]),
    ],
    targets: [
        // Platform-neutral logic shared in behaviour with the Windows companion: prompts, the DeepSeek client,
        // conversation storage, Pip's poses and placement. No AppKit, fully unit-tested.
        .target(name: "CoachCore"),
        // The macOS Pip companion. AppKit only (no SwiftUI macros), so it also builds with the Command Line Tools.
        .executableTarget(
            name: "F2L",
            dependencies: ["CoachCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Swift Testing. Run with scripts/test.sh, which also works before Xcode's licence is accepted.
        .testTarget(name: "CoachCoreTests", dependencies: ["CoachCore"]),
    ]
)
