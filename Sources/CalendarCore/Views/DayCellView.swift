import SwiftUI

struct DayCellView: View {
    let day: DayInfo
    let isSelected: Bool
    /// Events plus open reminders on this day; 0 hides the badge.
    var agendaCount: Int = 0
    let action: () -> Void

    private var isHighlighted: Bool { day.isToday || isSelected }

    var body: some View {
        VStack(spacing: 1) {
            Text("\(day.gregorianDay)")
                .font(.system(size: 15, weight: day.isToday ? .semibold : .regular))
                .foregroundStyle(primaryColor)
            Text(subtitleText)
                .font(.system(size: 9.5, weight: subtitleWeight))
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        // Nudged down so the 休 / 班 badge clears the date above it.
        .offset(y: 2)
        .background(background)
        .overlay(alignment: .topTrailing) { badge }
        .overlay(alignment: .topLeading) { agendaBadge }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .opacity(day.isInDisplayedMonth ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var background: some View {
        if day.isToday {
            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor)
        } else if isSelected {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.10))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch day.holidayStatus {
        case .off:
            badgeLabel("休", color: .red)
        case .workday:
            badgeLabel("班", color: .secondary)
        case nil:
            EmptyView()
        }
    }

    /// The count sits opposite the 休 / 班 badge. On today's filled cell it
    /// inverts, since an accent badge would vanish into the accent background.
    @ViewBuilder
    private var agendaBadge: some View {
        if agendaCount > 0 {
            Text(agendaCount > 99 ? "99+" : "\(agendaCount)")
                .font(.system(size: 7.5, weight: .bold).monospacedDigit())
                .foregroundStyle(day.isToday ? Color.accentColor : .white)
                .padding(.horizontal, 3)
                .padding(.vertical, 0.5)
                .background(Capsule().fill(day.isToday ? Color.white : Color.accentColor))
                .padding(1.5)
        }
    }

    private func badgeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 1.5)
            .padding(.vertical, 0.5)
            .background(RoundedRectangle(cornerRadius: 2.5).fill(color))
            .padding(1.5)
    }

    private var subtitleText: String {
        switch day.subtitle {
        case .festival(let name), .solarTerm(let name), .lunar(let name): return name
        }
    }

    private var subtitleWeight: Font.Weight {
        if case .lunar = day.subtitle { return .regular }
        return .semibold
    }

    // MARK: - Colours

    private var primaryColor: Color {
        if day.isToday { return .white }
        switch day.holidayStatus {
        case .off:
            return .red
        case .workday:
            // A traded-away weekend is a working day; the weekend colour would
            // say the opposite of the 班 badge next to it.
            return .primary
        case nil:
            return day.isWeekend ? .red : .primary
        }
    }

    private var secondaryColor: Color {
        if day.isToday { return .white.opacity(0.9) }
        switch day.subtitle {
        case .festival: return .red
        case .solarTerm: return .green
        case .lunar: return .secondary
        }
    }

    private var accessibilityText: String {
        let agenda = agendaCount > 0 ? " \(agendaCount) 项日程" : ""
        return "\(day.gregorianDay)日 \(day.detailLine)\(agenda)"
    }
}
