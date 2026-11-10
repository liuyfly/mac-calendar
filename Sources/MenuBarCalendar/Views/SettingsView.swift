import CalendarCore
import EventKit
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
    @State private var showAgenda = Preferences.shared.showAgenda
    /// Bumped after an access request so the status line re-reads it.
    @State private var accessRevision = 0
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
                Toggle("显示日历与提醒事项", isOn: $showAgenda)
                    .onChange(of: showAgenda) { _, new in
                        Preferences.shared.showAgenda = new
                        if new { requestAgendaAccess() }
                    }
                if showAgenda {
                    agendaAccessRow
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

    private var agendaAccessRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(agendaAccessSummary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .id(accessRevision)
            Spacer()
            if needsAgendaAction {
                Button(anyUndetermined ? "授权" : "打开系统设置") {
                    if anyUndetermined {
                        requestAgendaAccess()
                    } else {
                        let type: EKEntityType =
                            EventKitAgendaProvider.access(for: .event) == .granted ? .reminder : .event
                        EventKitAgendaProvider.openPrivacySettings(for: type)
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private var agendaAccessSummary: String {
        func label(_ access: EventKitAgendaProvider.Access) -> String {
            switch access {
            case .granted: return "已授权"
            case .denied: return "未授权"
            case .notDetermined: return "待授权"
            case .unavailable: return "不可用"
            }
        }
        return "日历：\(label(EventKitAgendaProvider.access(for: .event)))"
            + " · 提醒事项：\(label(EventKitAgendaProvider.access(for: .reminder)))"
    }

    private var anyUndetermined: Bool {
        EventKitAgendaProvider.access(for: .event) == .notDetermined
            || EventKitAgendaProvider.access(for: .reminder) == .notDetermined
    }

    private var needsAgendaAction: Bool {
        let states = [EventKitAgendaProvider.access(for: .event),
                      EventKitAgendaProvider.access(for: .reminder)]
        return states.contains(.notDetermined) || states.contains(.denied)
    }

    private func requestAgendaAccess() {
        EventKitAgendaProvider.shared.requestAccessIfNeeded {
            accessRevision &+= 1
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
