import AppKit
import CalendarCore
import EventKit

/// Reads events and reminders from the system Calendar and Reminders stores.
///
/// There is no syncing here: iCloud already keeps those stores in step with
/// the user's other devices, so this only reads what is on this Mac. Access is
/// read-only.
final class EventKitAgendaProvider: AgendaProvider {
    static let shared = EventKitAgendaProvider()

    enum Access: Equatable {
        case granted
        case denied
        case notDetermined
        /// No usage description in Info.plist, as for the bare binary from
        /// `swift build`. Asking would terminate the process, so the feature
        /// is simply off.
        case unavailable
    }

    private let store = EKEventStore()
    private let queue = DispatchQueue(label: "MenuBarCalendar.agenda", qos: .userInitiated)

    /// Called on the main queue whenever the calendar database changes, from
    /// this Mac or through iCloud.
    var onChange: (() -> Void)?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.onChange?()
        }
    }

    // MARK: - Access

    static func access(for type: EKEntityType) -> Access {
        let key = type == .event
            ? "NSCalendarsFullAccessUsageDescription"
            : "NSRemindersFullAccessUsageDescription"
        guard Bundle.main.object(forInfoDictionaryKey: key) != nil else { return .unavailable }

        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        // Write-only access cannot read anything back, so it is as good as no.
        default: return .denied
        }
    }

    /// True when neither store can be read and at least one was refused, which
    /// is when the panel explains why the list is empty. Refusing only one is
    /// taken as a choice and not nagged about.
    static var isBlocked: Bool {
        let events = access(for: .event), reminders = access(for: .reminder)
        return events != .granted && reminders != .granted
            && (events == .denied || reminders == .denied)
    }

    /// Asks for whichever access has not been decided yet, one prompt at a
    /// time. `completion` runs on the main queue.
    func requestAccessIfNeeded(completion: @escaping () -> Void) {
        requestEvents { [weak self] in
            self?.requestReminders {
                // A store created before access was granted can keep returning
                // nothing until it is reset.
                self?.store.reset()
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    private func requestEvents(then next: @escaping () -> Void) {
        guard Self.access(for: .event) == .notDetermined else { return next() }
        store.requestFullAccessToEvents { _, _ in next() }
    }

    private func requestReminders(then next: @escaping () -> Void) {
        guard Self.access(for: .reminder) == .notDetermined else { return next() }
        store.requestFullAccessToReminders { _, _ in next() }
    }

    /// Opens the privacy pane where access can be granted after a refusal.
    static func openPrivacySettings(for type: EKEntityType) {
        let anchor = type == .event ? "Privacy_Calendars" : "Privacy_Reminders"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - AgendaProvider

    func fetchItems(from start: Date, to end: Date,
                    completion: @escaping ([AgendaItem]) -> Void) {
        let readEvents = Self.access(for: .event) == .granted
        let readReminders = Self.access(for: .reminder) == .granted
        guard readEvents || readReminders else { return completion([]) }

        // Event queries are synchronous and can take a moment on a large
        // database, so they stay off the main thread.
        queue.async { [store] in
            var items: [AgendaItem] = []
            if readEvents {
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
                items += store.events(matching: predicate).compactMap(Self.item(from:))
            }
            guard readReminders else { return completion(items) }

            // Only open reminders with a due date in range: completed ones and
            // undated ones are not shown.
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: start, ending: end, calendars: nil)
            store.fetchReminders(matching: predicate) { reminders in
                items += (reminders ?? []).compactMap(Self.item(from:))
                completion(items)
            }
        }
    }

    // MARK: - Conversion

    private static func item(from event: EKEvent) -> AgendaItem? {
        // A declined invitation is not something the user will attend.
        if event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined {
            return nil
        }
        guard let start = event.startDate else { return nil }
        let base = event.eventIdentifier ?? event.calendarItemIdentifier
        return AgendaItem(
            // Occurrences of a recurring event share one identifier.
            id: "\(base)@\(start.timeIntervalSince1970)",
            kind: .event,
            title: event.title?.isEmpty == false ? event.title : "（无标题）",
            start: start,
            end: event.endDate,
            isAllDay: event.isAllDay,
            color: color(event.calendar?.cgColor)
        )
    }

    private static func item(from reminder: EKReminder) -> AgendaItem? {
        guard !reminder.isCompleted,
              let components = reminder.dueDateComponents,
              let due = Calendar.current.date(from: components) else { return nil }
        return AgendaItem(
            id: reminder.calendarItemIdentifier,
            kind: .reminder,
            title: reminder.title?.isEmpty == false ? reminder.title : "（无标题）",
            start: due,
            end: nil,
            // A due date without a time is a whole-day reminder.
            isAllDay: components.hour == nil,
            color: color(reminder.calendar?.cgColor)
        )
    }

    private static func color(_ cgColor: CGColor?) -> AgendaItem.Color? {
        guard let cgColor,
              let rgb = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else { return nil }
        return AgendaItem.Color(red: Double(rgb.redComponent),
                                green: Double(rgb.greenComponent),
                                blue: Double(rgb.blueComponent))
    }
}
