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
        renderSettings(into: outputDir)
    }

    @MainActor
    private static func render(scheme: ColorScheme, name: String, into directory: String) {
        let model = CalendarViewModel()
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
