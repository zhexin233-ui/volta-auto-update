import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .accessibilityLabel("Volta 自动更新 App 图标")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Volta 自动更新")
                        .font(.headline)
                    Text(model.scheduleSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "dashboard")
            } label: {
                Label("打开控制面板", systemImage: "macwindow")
            }

            Button {
                model.runUpdateNow()
            } label: {
                Label(model.updateButtonTitle, systemImage: "bolt.fill")
            }
            .disabled(model.isUpdating)

            Toggle(
                "每天 \(model.savedScheduleTime) 自动更新",
                isOn: Binding(
                    get: { model.scheduleEnabled },
                    set: { model.setSchedule($0) }
                )
            )
            .disabled(model.scheduleBusy)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
        }
        .padding(14)
        .frame(width: 280)
        .task { model.prepare() }
    }
}
