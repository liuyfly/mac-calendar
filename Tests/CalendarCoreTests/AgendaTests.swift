import Foundation

/// A local instant, for building agenda items.
private func at(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
}

private let localCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .current
    return c
}()

private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> AgendaItem {
    AgendaItem(id: "\(title)@\(start.timeIntervalSince1970)", kind: .event, title: title,
               start: start, end: end, isAllDay: allDay, color: nil)
}

private func reminder(_ title: String, _ due: Date, allDay: Bool = false) -> AgendaItem {
    AgendaItem(id: title, kind: .reminder, title: title,
               start: due, end: nil, isAllDay: allDay, color: nil)
}

/// Records every request and answers only when told to, so tests control
/// ordering.
private final class FakeAgendaProvider: AgendaProvider {
    var items: [AgendaItem] = []
    var answersImmediately = true
    private(set) var requests: [(start: Date, end: Date)] = []
    private(set) var pending: [([AgendaItem]) -> Void] = []

    func fetchItems(from start: Date, to end: Date,
                    completion: @escaping ([AgendaItem]) -> Void) {
        requests.append((start, end))
        let matching = items.filter { item in
            item.start < end && (item.end ?? item.start) >= start
        }
        if answersImmediately {
            completion(matching)
        } else {
            pending.append { _ in completion(matching) }
        }
    }

    func answer(_ index: Int) { pending[index]([]) }
}

func runAgendaTests() {
    let september = (start: at(2026, 8, 31), end: at(2026, 10, 12))

    TestRunner.suite("AgendaIndex — items land on the days they cover") {
        let items = [
            event("站会", at(2026, 9, 24, 9, 30), at(2026, 9, 24, 10)),
            event("国庆出游", at(2026, 10, 1), at(2026, 10, 4), allDay: true),
            // All-day events can also end at 23:59:59 of their last day.
            event("中秋", at(2026, 9, 25), at(2026, 9, 25, 23, 59), allDay: true),
            event("跨夜", at(2026, 9, 26, 22), at(2026, 9, 27, 2)),
            event("到零点", at(2026, 9, 28, 23), at(2026, 9, 29)),
            reminder("交房租", at(2026, 9, 30, 15)),
            reminder("范围外", at(2026, 11, 20)),
        ]
        let byDay = AgendaIndex.byDay(items, from: september.start, to: september.end,
                                      calendar: localCalendar)
        func titles(_ d: Int, _ m: Int = 9) -> [String] {
            (byDay[localCalendar.startOfDay(for: at(2026, m, d))] ?? []).map(\.title)
        }

        expectEqual(titles(24), ["站会"])
        expectEqual(titles(25), ["中秋"])
        expectEqual(titles(1, 10), ["国庆出游"])
        expectEqual(titles(3, 10), ["国庆出游"], "a three-day event shows on its last day")
        expectEqual(titles(4, 10), [], "an end at midnight is exclusive")
        expectEqual(titles(26), ["跨夜"])
        expectEqual(titles(27), ["跨夜"], "an overnight event counts on both days")
        expectEqual(titles(28), ["到零点"])
        expectEqual(titles(29), [], "23:00–00:00 does not spill into the next day")
        expectEqual(titles(30), ["交房租"])
        expect(!byDay.values.flatMap { $0 }.contains { $0.title == "范围外" },
               "items outside the range are dropped")
    }

    TestRunner.suite("AgendaIndex — whole-day entries first, then by time") {
        let items = [
            reminder("下午提醒", at(2026, 9, 24, 15)),
            event("早会", at(2026, 9, 24, 9), at(2026, 9, 24, 10)),
            event("出差", at(2026, 9, 23, 8), at(2026, 9, 25, 18)),
            reminder("全天提醒", at(2026, 9, 24), allDay: true),
        ]
        let byDay = AgendaIndex.byDay(items, from: september.start, to: september.end,
                                      calendar: localCalendar)
        let titles = (byDay[localCalendar.startOfDay(for: at(2026, 9, 24))] ?? []).map(\.title)
        // 出差 spans the whole of the 24th, so it sorts with the all-day items.
        expectEqual(titles, ["出差", "全天提醒", "早会", "下午提醒"])
    }

    TestRunner.suite("AgendaIndex — time labels") {
        let day = localCalendar.startOfDay(for: at(2026, 9, 24))
        func label(_ item: AgendaItem, on d: Date = day) -> String {
            AgendaIndex.timeLabel(for: item, on: d, calendar: localCalendar)
        }
        expectEqual(label(event("a", at(2026, 9, 24, 9, 30), at(2026, 9, 24, 10))), "09:30–10:00")
        expectEqual(label(event("b", at(2026, 9, 24, 22), at(2026, 9, 25, 2))), "22:00 起")
        expectEqual(label(event("c", at(2026, 9, 23, 22), at(2026, 9, 24, 10))), "至 10:00")
        expectEqual(label(event("d", at(2026, 9, 23, 8), at(2026, 9, 25, 18))), "全天")
        expectEqual(label(event("e", at(2026, 9, 24), at(2026, 9, 25), allDay: true)), "全天")
        expectEqual(label(event("f", at(2026, 9, 24, 9), at(2026, 9, 24, 9))), "09:00",
                    "a zero-length event shows its start only")
        expectEqual(label(reminder("g", at(2026, 9, 24, 15, 5))), "15:05")
        expectEqual(label(reminder("h", at(2026, 9, 24), allDay: true)), "全天")
    }

    TestRunner.suite("CalendarViewModel — agenda counts and the focused list") {
        let provider = FakeAgendaProvider()
        provider.items = [
            event("站会", at(2026, 9, 24, 9, 30), at(2026, 9, 24, 10)),
            reminder("交房租", at(2026, 9, 24, 15)),
            event("国庆", at(2026, 10, 1), at(2026, 10, 2), allDay: true),
        ]
        let model = CalendarViewModel(today: day(2026, 9, 24), agendaProvider: provider)

        expectEqual(provider.requests.count, 1)
        if let request = provider.requests.first {
            // The whole 6 x 7 grid, including borrowed days.
            expectEqual(request.start, localCalendar.startOfDay(for: at(2026, 8, 31)))
            expectEqual(request.end, localCalendar.startOfDay(for: at(2026, 10, 12)))
        }
        expectEqual(model.agendaItems(on: day(2026, 9, 24)).count, 2, "event + reminder")
        expectEqual(model.agendaItems(on: day(2026, 10, 1)).count, 1,
                    "a borrowed day from October still gets its count")
        expectEqual(model.focusedAgenda.map(\.title), ["站会", "交房租"],
                    "with nothing selected the list shows today")

        if let oct1 = model.month.days.first(where: { $0.gregorianDay == 1 && !$0.isInDisplayedMonth }) {
            model.select(oct1)
            expectEqual(model.focusedAgenda.map(\.title), ["国庆"], "the list follows a click")
        } else {
            expect(false, "September's grid should show 10/1")
        }
    }

    TestRunner.suite("CalendarViewModel — a stale agenda answer is ignored") {
        let provider = FakeAgendaProvider()
        provider.answersImmediately = false
        provider.items = [event("九月的事", at(2026, 9, 24, 9), at(2026, 9, 24, 10))]
        let model = CalendarViewModel(today: day(2026, 9, 24), agendaProvider: provider)

        model.step(1)                  // page to October before September answers
        provider.answer(0)             // September's answer arrives late
        expect(model.agenda.isEmpty, "a superseded fetch must not overwrite the current month")
        expectEqual(provider.requests.count, 2)
    }

    TestRunner.suite("CalendarViewModel — agenda turned off") {
        let provider = FakeAgendaProvider()
        provider.items = [event("站会", at(2026, 9, 24, 9), at(2026, 9, 24, 10))]
        Preferences.shared.showAgenda = false
        defer { Preferences.shared.showAgenda = true }

        let model = CalendarViewModel(today: day(2026, 9, 24), agendaProvider: provider)
        expectEqual(provider.requests.count, 0, "nothing is read while the feature is off")
        expect(model.agenda.isEmpty)
    }
}
