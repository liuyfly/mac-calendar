import SwiftUI

struct CalendarPanelView: View {
    @ObservedObject var model: CalendarViewModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            weekdayRow
            grid
            Divider()
            footer
        }
        .frame(width: 326)
        .fixedSize(horizontal: false, vertical: true)
        // A popover's vibrancy pulls up whatever sits behind it, which makes
        // dark windows bleed through the light-mode text. An opaque window
        // background keeps the grid readable over anything.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(String(model.month.year))年 \(model.month.month)月")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(model.month.yearSummary) · \(model.month.lunarMonthSummary)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                navButton("chevron.left", help: "上个月") { model.step(-1) }
                // The "today" dot stays smaller than its neighbours on purpose:
                // at the title's size a filled circle reads as a heavy blob.
                navButton("circle.fill", help: "回到今天", size: 9) { model.goToToday() }
                navButton("chevron.right", help: "下个月") { model.step(1) }
                navButton("gearshape", help: "偏好设置", action: onOpenSettings)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// Sized to match the "2026年 9月" title above it.
    private static let navSymbolSize: CGFloat = 16

    private func navButton(_ symbol: String,
                           help: String,
                           size: CGFloat = navSymbolSize,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    // MARK: - Grid

    private var weekdayRow: some View {
        HStack(spacing: 1) {
            ForEach(Array(model.month.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isWeekendColumn(index) ? Color.red.opacity(0.75) : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func isWeekendColumn(_ index: Int) -> Bool {
        Preferences.shared.weekStartsOnMonday ? index >= 5 : (index == 0 || index == 6)
    }

    private var grid: some View {
        VStack(spacing: 1) {
            ForEach(0..<CalendarMonth.rowCount, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<CalendarMonth.columnCount, id: \.self) { column in
                        let index = row * CalendarMonth.columnCount + column
                        if index < model.month.days.count {
                            let day = model.month.days[index]
                            DayCellView(day: day, isSelected: model.isSelected(day)) {
                                model.select(day)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.footerTitle)
                .font(.system(size: 12, weight: .medium))
            Text(model.footerDetail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
