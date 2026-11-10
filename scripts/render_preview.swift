import AppKit
import SwiftUI

/// Renders the real popover off-screen to PNG, in both appearances. Used to
/// check layout without clicking through the status bar.
@main
enum PreviewRenderer {

    @MainActor
    static func main() {
        let outputDir = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : FileManager.default.currentDirectoryPath

        // SwiftUI needs an initialized application, but nothing should appear.
        NSApplication.shared.setActivationPolicy(.prohibited)

        render(scheme: .light, name: "panel-light.png", into: outputDir)
        render(scheme: .dark, name: "panel-dark.png", into: outputDir)
        render(scheme: .light, name: "panel-agenda-light.png", into: outputDir,
               agenda: SampleAgendaProvider())
        render(scheme: .dark, name: "panel-agenda-dark.png", into: outputDir,
               agenda: SampleAgendaProvider())
        renderSettings(into: outputDir)
    }

    @MainActor
    private static func render(scheme: ColorScheme, name: String, into directory: String,
                               agenda: AgendaProvider? = nil) {
        let model = CalendarViewModel(agendaProvider: agenda)
        let content = CalendarPanelView(model: model, onOpenSettings: {})
            .environment(\.colorScheme, scheme)
            .background(backgroundColor(for: scheme))
        write(content, name: name, into: directory)
    }

    @MainActor
    private static func renderSettings(into directory: String) {
        let content = SettingsView(onClose: {}, onQuit: {})
            .environment(\.colorScheme, .light)
            .background(backgroundColor(for: .light))
        write(content, name: "settings-light.png", into: directory)
    }

    private static func backgroundColor(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(nsColor: NSColor(calibratedWhite: 0.17, alpha: 1))
            : Color(nsColor: .white)
    }

    @MainActor
    private static func write(_ content: some View, name: String, into directory: String) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            print("failed to render \(name)")
            return
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try? png.write(to: url)
        print("wrote \(url.path)  (\(Int(image.size.width))x\(Int(image.size.height)) pt)")
    }
}

/// Made-up events and reminders around today, so the preview shows the count
/// badges and the day list without touching the real calendar database.
final class SampleAgendaProvider: AgendaProvider {
    func fetchItems(from start: Date, to end: Date,
                    completion: @escaping ([AgendaItem]) -> Void) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            let d = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
        }
        let blue = AgendaItem.Color(red: 0.10, green: 0.50, blue: 0.95)
        let orange = AgendaItem.Color(red: 0.98, green: 0.58, blue: 0.10)
        let purple = AgendaItem.Color(red: 0.62, green: 0.35, blue: 0.85)
        func event(_ t: String, _ s: Date, _ e: Date, _ c: AgendaItem.Color, allDay: Bool = false) -> AgendaItem {
            AgendaItem(id: t + "\(s)", kind: .event, title: t, start: s, end: e, isAllDay: allDay, color: c)
        }
        func reminder(_ t: String, _ due: Date, allDay: Bool = false) -> AgendaItem {
            AgendaItem(id: t + "\(due)", kind: .reminder, title: t, start: due, end: nil,
                       isAllDay: allDay, color: orange)
        }
        completion([
            event("产品周会", at(0, 10), at(0, 11), blue),
            event("和设计对一下面板交互细节", at(0, 14, 30), at(0, 15, 30), purple),
            reminder("交房租", at(0, 18)),
            reminder("买中秋月饼", at(0), allDay: true),
            event("周报", at(1, 16), at(1, 17), blue),
            event("国庆出游", at(7), at(10), purple, allDay: true),
            reminder("续签 iPhone App", at(3, 9)),
            event("体检", at(-2, 8), at(-2, 10), blue),
            reminder("还信用卡", at(-5), allDay: true),
            reminder("备份照片", at(-5, 21)),
        ])
    }
}
