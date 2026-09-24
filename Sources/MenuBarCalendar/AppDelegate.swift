import AppKit
import CalendarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.shared.appearance.apply()

        let controller = StatusItemController()
        statusItemController = controller

        // Pull the latest statutory holiday arrangement in the background; the
        // bundled table stays in use if the network is unavailable.
        HolidayStore.shared.refreshFromRemote { _ in }

        // Asked at launch rather than when the panel opens: the system prompt
        // takes focus, which would dismiss the panel underneath it. Only
        // undecided access is asked for, so this prompts once.
        if Preferences.shared.showAgenda {
            EventKitAgendaProvider.shared.requestAccessIfNeeded {
                controller.refreshAgenda()
            }
        }

        // Opens the calendar straight away, for screenshots and manual checks:
        //   dist/MenuBarCalendar.app/Contents/MacOS/MenuBarCalendar --show-on-launch
        // The status item needs a turn of the run loop to get its final
        // position before the panel can be placed under it.
        if CommandLine.arguments.contains("--show-on-launch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                controller.showPanel()
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
