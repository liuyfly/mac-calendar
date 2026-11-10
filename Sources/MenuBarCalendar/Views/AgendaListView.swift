import CalendarCore
import SwiftUI

/// The focused day's events and reminders, under the footer.
struct AgendaListView: View {
    let items: [AgendaItem]
    let day: Date
    /// Shown instead of the list when access was refused.
    let isBlocked: Bool

    /// Beyond this many rows the list scrolls rather than stretching the panel
    /// down the screen.
    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 20
    private static let rowSpacing: CGFloat = 2

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    var body: some View {
        if isBlocked {
            permissionHint
        } else if !items.isEmpty {
            VStack(spacing: 0) {
                Divider()
                list
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        let rows = VStack(spacing: Self.rowSpacing) {
            ForEach(items) { row($0) }
        }
        if items.count > Self.visibleRows {
            ScrollView {
                rows
            }
            .frame(height: CGFloat(Self.visibleRows) * Self.rowHeight
                   + CGFloat(Self.visibleRows - 1) * Self.rowSpacing)
        } else {
            rows
        }
    }

    private func row(_ item: AgendaItem) -> some View {
        HStack(spacing: 8) {
            marker(for: item)
                .frame(width: 10)
            Text(item.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(AgendaIndex.timeLabel(for: item, on: day, calendar: Self.calendar))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .combine)
    }

    /// A coloured bar for events and an open circle for reminders, the shapes
    /// Calendar and Reminders use themselves.
    @ViewBuilder
    private func marker(for item: AgendaItem) -> some View {
        let color = item.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
            ?? .accentColor
        switch item.kind {
        case .event:
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3, height: 14)
        case .reminder:
            Circle()
                .strokeBorder(color, lineWidth: 1.5)
                .frame(width: 10, height: 10)
        }
    }

    private var permissionHint: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("未获得日历和提醒事项的访问权限")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("打开系统设置") {
                    EventKitAgendaProvider.openPrivacySettings(for: .event)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}
