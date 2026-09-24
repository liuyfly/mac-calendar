// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuBarCalendar",
    // iOS is listed for CalendarCore, which a future iPhone app links against.
    // The MenuBarCalendar executable is AppKit-only and is never built for it.
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CalendarCore", targets: ["CalendarCore"]),
        .executable(name: "MenuBarCalendar", targets: ["MenuBarCalendar"]),
    ],
    targets: [
        // Platform-independent: lunar and solar-term computation, holiday
        // data, the month model and the SwiftUI day cell and month grid. Must
        // not import AppKit or UIKit.
        .target(
            name: "CalendarCore",
            path: "Sources/CalendarCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The macOS menu bar app: status item, panel, settings window and
        // launch at login.
        .executableTarget(
            name: "MenuBarCalendar",
            dependencies: ["CalendarCore"],
            path: "Sources/MenuBarCalendar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
