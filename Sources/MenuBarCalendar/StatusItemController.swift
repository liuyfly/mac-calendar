import AppKit
import CalendarCore
import SwiftUI

/// Owns the status bar item, the calendar panel and the settings window.
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let viewModel = CalendarViewModel()
    private var panel: CalendarPanel?
    private var settingsWindow: NSWindow?
    private var midnightTimer: Timer?
    /// Watches for clicks in other applications so the panel dismisses the way
    /// a menu would.
    private var outsideClickMonitor: Any?
    /// When the panel last closed, used to tell a genuine "open me" click apart
    /// from the click that just dismissed the panel.
    private var panelClosedAt: Date?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        observeDayChanges()
        refreshTitle()
    }

    deinit {
        midnightTimer?.invalidate()
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Status item

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Updates what the status item shows. Called on launch, on preference
    /// changes, and whenever the date rolls over.
    func refreshTitle() {
        guard let button = statusItem.button else { return }
        let style = Preferences.shared.statusBarStyle

        button.image = style.showsIcon ? StatusItemIcon.make() : nil
        button.title = style.showsText
            ? StatusBarFormatter.render(template: Preferences.shared.statusBarFormat)
            : ""
        // Without a title the button would otherwise keep the text's width.
        button.toolTip = StatusBarFormatter.render(template: "{y}年{M}月{d}日 {周} · {农历}")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel(sender)
        }
    }

    // MARK: - Panel

    private func makePanel() -> CalendarPanel {
        let hosting = NSHostingView(
            rootView: CalendarPanelView(model: viewModel) { [weak self] in
                self?.openSettings()
            }
        )
        // Let the SwiftUI content drive the size; a fixed guess squashes the
        // header.
        hosting.setFrameSize(hosting.fittingSize)
        return CalendarPanel(contentView: hosting)
    }

    private func togglePanel(_ sender: NSStatusBarButton) {
        if panel?.isVisible == true {
            closePanel()
            return
        }
        // Clicking the status item takes key status away from the panel, which
        // closes it before this action ever runs. Without this guard the panel
        // would reopen on the same click and could never be dismissed from the
        // status item.
        if let closedAt = panelClosedAt, Date().timeIntervalSince(closedAt) < 0.25 {
            return
        }
        showPanel(from: sender)
    }

    /// Opens the calendar under the status item.
    func showPanel(from button: NSStatusBarButton? = nil) {
        guard let anchor = button ?? statusItem.button else { return }

        // Every opening starts from the current month with nothing selected,
        // like the system calendar: paging is a transient look-around, not a
        // place to come back to. Resetting here also rebuilds the grid, which
        // picks up preference changes and a date that rolled over while idle.
        viewModel.goToToday()
        refreshTitle()

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.position(below: anchor)
        panel.makeKeyAndOrderFront(nil)
        startWatchingForOutsideClicks()
    }

    func closePanel() {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        panelClosedAt = Date()
        stopWatchingForOutsideClicks()
    }

    /// A borderless panel gets no dismissal behaviour for free. Clicks in other
    /// applications come through a global monitor; clicks elsewhere in this app
    /// arrive as a loss of key status.
    private func startWatchingForOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResignedKey(_:)),
            name: NSWindow.didResignKeyNotification, object: panel)
    }

    private func stopWatchingForOutsideClicks() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didResignKeyNotification, object: panel)
    }

    @objc private func panelResignedKey(_ notification: Notification) {
        closePanel()
    }

    // MARK: - Context menu

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "偏好设置…", action: #selector(openSettingsMenuItem), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "更新节假日数据", action: #selector(refreshHolidays), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 MenuBarCalendar", action: #selector(quit), keyEquivalent: "q")
            .target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil   // restore click-to-popover for the next click
    }

    @objc private func openSettingsMenuItem() { openSettings() }

    @objc private func refreshHolidays() {
        HolidayStore.shared.refreshFromRemote(force: true) { [weak self] _ in
            self?.viewModel.reload()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Settings window

    private func openSettings() {
        closePanel()

        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(
            onClose: { [weak self] in self?.closeSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "MenuBarCalendar 偏好设置"
        window.isReleasedWhenClosed = false
        // Let the SwiftUI content decide the height instead of guessing one.
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closeSettings() {
        settingsWindow?.close()
        viewModel.reload()
        refreshTitle()
    }

    // MARK: - Day rollover

    /// The title must change at local midnight even if nobody touches the app.
    ///
    /// `NSCalendarDayChanged` is the system's own signal and handles time zone
    /// changes; the timer is a backstop, and the wake notification covers a
    /// machine that slept through midnight.
    private func observeDayChanges() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(dayChanged),
            name: .NSCalendarDayChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(dayChanged),
            name: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(dayChanged),
            name: NSWorkspace.didWakeNotification, object: nil)
        scheduleMidnightTimer()
    }

    @objc private func dayChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshTitle()
            self?.viewModel.reload()
            self?.scheduleMidnightTimer()
        }
    }

    private func scheduleMidnightTimer() {
        midnightTimer?.invalidate()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let nextMidnight = calendar.nextDate(
            after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime) else { return }

        let timer = Timer(fireAt: nextMidnight, interval: 0, target: self,
                          selector: #selector(dayChanged), userInfo: nil, repeats: false)
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }
}
