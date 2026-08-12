import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 18) {
                        HStack(alignment: .top, spacing: 18) {
                            toolsCard
                                .frame(maxWidth: .infinity)

                            VStack(spacing: 18) {
                                scheduleCard
                                lastRunCard
                            }
                            .frame(width: 310)
                        }

                        logCard
                    }
                    .padding(.horizontal, 26)
                    .padding(.bottom, 26)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 680)
        .task { model.prepare() }
        .sheet(isPresented: $model.showingAddTool) {
            AddToolView()
                .environmentObject(model)
        }
        .alert(
            "操作未完成",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.clearAlert() } }
            )
        ) {
            Button("好") { model.clearAlert() }
        } message: {
            Text(model.alertMessage ?? "未知错误")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 54, height: 54)
                .accessibilityLabel("Volta 自动更新 App 图标")
                .shadow(color: Color.indigo.opacity(0.24), radius: 12, y: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text("Volta 自动更新")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("让命令行工具保持新鲜，也保持安静")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(
                title: model.scheduleEnabled ? "自动更新已开启" : "自动更新已关闭",
                color: model.scheduleEnabled ? .green : .secondary,
                symbol: model.scheduleEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
            )

            Button {
                model.refresh()
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .help("刷新版本与运行状态")
            .disabled(model.isRefreshing || model.isUpdating)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }

    private var toolsCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("工具状态")
                            .font(.title3.weight(.semibold))
                        Text("当前安装版本与 npm 最新版本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Text("\(model.tools.count) 个工具")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Button {
                            model.showingAddTool = true
                        } label: {
                            Label("新增", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.bottom, 14)

                Divider()

                if model.tools.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("还没有配置工具")
                            .font(.headline)
                        Text("点击“新增”添加需要由 Volta 管理的 npm 包。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                } else {
                    ForEach(Array(model.tools.enumerated()), id: \.element.id) { index, tool in
                        ToolRow(tool: tool) {
                            model.deleteTool(tool)
                        }
                        .padding(.vertical, 15)
                        if index < model.tools.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }

                Button {
                    model.runUpdateNow()
                } label: {
                    HStack {
                        if model.isUpdating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(model.updateButtonTitle)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.indigo)
                .disabled(model.isUpdating || model.isRefreshing)
                .padding(.top, 8)
            }
        }
    }

    private var scheduleCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("每日调度", systemImage: "calendar.badge.clock")
                        .font(.headline)
                    Spacer()
                    if model.scheduleBusy {
                        ProgressView().controlSize(.small)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(model.selectedScheduleTime)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("每天")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    DatePicker(
                        "执行时间",
                        selection: $model.scheduleDate,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.field)

                    if model.scheduleTimeHasChanges {
                        Button("保存") { model.saveScheduleTime() }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                    }
                }
                .disabled(model.scheduleBusy)

                Toggle(
                    "启用自动更新",
                    isOn: Binding(
                        get: { model.scheduleEnabled },
                        set: { model.setSchedule($0) }
                    )
                )
                .toggleStyle(.switch)
                .tint(.indigo)
                .disabled(model.scheduleBusy)

                VStack(alignment: .leading, spacing: 7) {
                    ScheduleHint(symbol: "moon.zzz.fill", text: "休眠时错过，会在唤醒后补跑")
                    ScheduleHint(symbol: "power", text: "关机后登录，若已过 \(model.savedScheduleTime) 会补跑")
                    ScheduleHint(symbol: "shield.checkered", text: "自动任务每天最多执行一次")
                }
            }
        }
    }

    private var lastRunCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("最近执行", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Spacer()
                    Circle()
                        .fill(lastRunColor)
                        .frame(width: 9, height: 9)
                }

                Text(model.runtimeStatus?.stateTitle ?? "尚未运行")
                    .font(.title3.weight(.semibold))

                if let status = model.runtimeStatus {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(status.modeTitle, systemImage: status.mode == "manual" ? "hand.tap.fill" : "calendar")
                        if !status.finishedAt.isEmpty {
                            Label(formatTimestamp(status.finishedAt), systemImage: "checkmark.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("首次自动或手动更新后，这里会显示结果。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var logCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("运行日志")
                            .font(.headline)
                        Text("保留最近的检查与更新输出")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开日志目录") { model.openDataFolder() }
                        .buttonStyle(.bordered)
                }

                ScrollView {
                    Text(model.logText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(13)
                }
                .frame(height: 150)
                .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(Color(red: 0.78, green: 0.95, blue: 0.83))
            }
        }
    }

    private var lastRunColor: Color {
        switch model.runtimeStatus?.state {
        case "success": .green
        case "failed": .red
        case "running": .orange
        default: .secondary
        }
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.075, green: 0.085, blue: 0.14),
                Color(red: 0.055, green: 0.105, blue: 0.15)
            ]
        }

        return [
            Color(red: 0.965, green: 0.963, blue: 0.985),
            Color(red: 0.925, green: 0.945, blue: 0.975)
        ]
    }

    private func formatTimestamp(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ToolRow: View {
    let tool: ToolStatus
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(rowColor.opacity(0.12))
                Image(systemName: tool.definition.symbol)
                    .foregroundStyle(rowColor)
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(tool.definition.name)
                    .font(.body.weight(.semibold))
                Text(tool.definition.package)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    Text(tool.currentVersion ?? "—")
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(tool.latestVersion ?? "—")
                }
                .font(.system(.caption, design: .monospaced).weight(.medium))

                StatusPill(title: tool.state.title, color: rowColor, symbol: rowSymbol)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("从更新列表中删除")
        }
    }

    private var rowColor: Color {
        switch tool.state {
        case .latest: .green
        case .updateAvailable: .orange
        case .notInstalled: .secondary
        case .unavailable: .red
        }
    }

    private var rowSymbol: String {
        switch tool.state {
        case .latest: "checkmark.circle.fill"
        case .updateAvailable: "arrow.up.circle.fill"
        case .notInstalled: "minus.circle.fill"
        case .unavailable: "exclamationmark.circle.fill"
        }
    }
}

private struct AddToolView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var package = ""
    @State private var name = ""
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.indigo.opacity(0.14))
                    Image(systemName: "plus.app.fill")
                        .foregroundStyle(.indigo)
                        .font(.title2)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("新增工具")
                        .font(.title3.weight(.semibold))
                    Text("添加由 Volta 管理的 npm 命令行包")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("npm 包名", text: $package, prompt: Text("例如 @scope/tool"))
                TextField("显示名称", text: $name, prompt: Text("例如 My Tool"))
            }
            .formStyle(.grouped)

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加") {
                    if let error = model.addTool(package: package, name: name) {
                        validationMessage = error
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .keyboardShortcut(.defaultAction)
                .disabled(package.isEmpty || name.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

private struct PanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 18, y: 7)
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.11), in: Capsule())
    }
}

private struct ScheduleHint: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
