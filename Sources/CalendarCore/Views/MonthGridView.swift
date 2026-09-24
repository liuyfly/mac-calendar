import SwiftUI

/// The weekday header and the 6 x 7 day grid for the model's current month.
///
/// Shared by every platform's calendar screen; the header, footer and
/// surrounding chrome are left to each app.
public struct MonthGridView: View {
    @ObservedObject var model: CalendarViewModel

    public init(model: CalendarViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            weekdayRow
            grid
        }
    }

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
                            DayCellView(day: day,
                                        isSelected: model.isSelected(day),
                                        agendaCount: model.agendaItems(on: day.date).count) {
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
}
