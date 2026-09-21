import Foundation
import ServiceManagement

/// Login-item registration.
///
/// `SMAppService` is the supported API, but it only works for a bundled,
/// signed app — an ad-hoc signed build run straight from `.build/` will fail.
/// In that case we fall back to writing a LaunchAgent plist so the feature
/// still works for locally built copies.
enum LaunchAtLogin {
    private static let agentLabel = "com.menubarcalendar.launcher"

    static var isEnabled: Bool {
        if isBundled {
            return SMAppService.mainApp.status == .enabled
        }
        return FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if isBundled, setViaServiceManagement(enabled) {
            return true
        }
        return setViaLaunchAgent(enabled)
    }

    // MARK: - Backends

    private static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private static func setViaServiceManagement(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[MenuBarCalendar] SMAppService failed: \(error.localizedDescription)")
            return false
        }
    }

    private static var agentPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(agentLabel).plist")
    }

    private static func setViaLaunchAgent(_ enabled: Bool) -> Bool {
        let url = agentPlistURL
        guard enabled else {
            try? FileManager.default.removeItem(at: url)
            return true
        }

        let executable = Bundle.main.bundleURL.pathExtension == "app"
            ? "/usr/bin/open"
            : Bundle.main.executablePath ?? ""
        let arguments: [String] = Bundle.main.bundleURL.pathExtension == "app"
            ? ["/usr/bin/open", "-a", Bundle.main.bundleURL.path]
            : [executable]

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": arguments,
            "RunAtLoad": true,
        ]

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url)
            return true
        } catch {
            NSLog("[MenuBarCalendar] LaunchAgent write failed: \(error.localizedDescription)")
            return false
        }
    }
}
