import CalendarCore
import SwiftUI

struct SettingsView: View {
    let onClose: () -> Void
    let onQuit: () -> Void

    @State private var appearance = Preferences.shared.appearance
    @State private var style = Preferences.shared.statusBarStyle
    @State private var format = Preferences.shared.statusBarFormat
    @State private var weekStartsOnMonday = Preferences.shared.weekStartsOnMonday
    @State private var showSolarTerms = Preferences.shared.showSolarTerms
    @State private var showHolidayBadges = Preferences.shared.showHolidayBadges
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var refreshMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("偏好设置")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()

            VStack(alignment: .leading, spacing: 10) {
                styleRow
                formatRow
                Divider()
                appearanceRow
                Picker("每周起始日", selection: $weekStartsOnMonday) {
                    Text("周一").tag(true)
                    Text("周日").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: weekStartsOnMonday) { _, new in
                    Preferences.shared.weekStartsOnMonday = new
                }

                Toggle("显示 24 节气", isOn: $showSolarTerms)
                    .onChange(of: showSolarTerms) { _, new in
                        Preferences.shared.showSolarTerms = new
                    }
                Toggle("显示法定节假日 / 调休", isOn: $showHolidayBadges)
                    .onChange(of: showHolidayBadges) { _, new in
                        Preferences.shared.showHolidayBadges = new
                    }
                Toggle("登录时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, new in
                        // Reverting on failure keeps the switch honest: an
                        // unbundled build cannot register a login item.
                        if !LaunchAtLogin.setEnabled(new) {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }

                Divider()
                holidayDataRow
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
            HStack {
                Button("退出 App", role: .destructive, action: onQuit)
                Spacer()
                Button("完成", action: onClose).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
    }

    private var styleRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("状态栏显示").font(.system(size: 12))
            Picker("", selection: $style) {
                ForEach(Preferences.StatusBarStyle.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: style) { _, new in
                Preferences.shared.statusBarStyle = new
            }
        }
    }

    private var appearanceRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("外观").font(.system(size: 12))
            Picker("", selection: $appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: appearance) { _, new in
                Preferences.shared.appearance = new
                new.apply()
            }
        }
    }

    private var formatRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("状态栏格式").font(.system(size: 12))
            TextField("", text: $format)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .onChange(of: format) { _, new in
                    Preferences.shared.statusBarFormat = new
                }
            Text("预览：\(StatusBarFormatter.render(template: format))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(Preferences.formatTokens.map { "\($0.token) \($0.description)" }
                    .joined(separator: "  "))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        // The template has no effect when the status item is icon-only.
        .disabled(!style.showsText)
        .opacity(style.showsText ? 1 : 0.4)
    }

    private var holidayDataRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("节假日数据").font(.system(size: 12))
                Text(refreshMessage ?? dataSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("检查更新") {
                refreshMessage = "正在更新…"
                HolidayStore.shared.refreshFromRemote(force: true) { years in
                    refreshMessage = years.isEmpty
                        ? "更新失败，继续使用现有数据"
                        : "已更新 " + years.map(String.init).joined(separator: "、") + " 年"
                }
            }
            .controlSize(.small)
        }
    }

    private var dataSummary: String {
        let years = HolidayStore.shared.availableYears
        let yearText = years.isEmpty
            ? "无数据"
            : "已覆盖 " + years.map(String.init).joined(separator: "、") + " 年"
        guard let updated = Preferences.shared.holidayDataUpdatedAt else { return yearText }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return yearText + " · 上次更新 " + formatter.string(from: updated)
    }
}
