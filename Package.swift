// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuBarCalendar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MenuBarCalendar",
            path: "Sources/MenuBarCalendar",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
