import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var tools: [ToolStatus] = ToolConfigurationStore.defaultDefinitions.map {
        ToolStatus(definition: $0, currentVersion: nil, latestVersion: nil, state: .unavailable)
    }
    @Published var scheduleEnabled = false
    @Published var scheduleDate = AppModel.date(from: "09:00")
    @Published var savedScheduleTime = "09:00"
    @Published var scheduleBusy = false
    @Published var isRefreshing = false
    @Published var isUpdating = false
    @Published var runtimeStatus: RuntimeStatus?
    @Published var logText = "正在读取状态…"
    @Published var alertMessage: String?
    @Published var showingAddTool = false

    private var prepared = false

    var updateButtonTitle: String {
        isUpdating ? "正在更新…" : "立即检查并更新"
    }

    var scheduleSummary: String {
        scheduleEnabled ? "每天 \(savedScheduleTime) 自动执行" : "自动更新已关闭"
    }

    var selectedScheduleTime: String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: scheduleDate)
        return String(format: "%02d:%02d", components.hour ?? 9, components.minute ?? 0)
    }

    var scheduleTimeHasChanges: Bool {
        selectedScheduleTime != savedScheduleTime
    }

    func prepare() {
        guard !prepared else { return }
        prepared = true
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            let localData = await Task.detached(priority: .userInitiated) { () -> (LocalSnapshot, [ToolDefinition], String?) in
                try? SchedulerService.syncRuntime()
                do {
                    return (SchedulerService.loadSnapshot(), try ToolConfigurationStore.load(), nil)
                } catch {
                    return (SchedulerService.loadSnapshot(), ToolConfigurationStore.defaultDefinitions, error.localizedDescription)
                }
            }.value

            tools = await VersionService.loadStatuses(definitions: localData.1)
            apply(localData.0)
            if let configurationError = localData.2 {
                alertMessage = configurationError
            }
            isRefreshing = false
        }
    }

    func setSchedule(_ enabled: Bool) {
        guard !scheduleBusy else { return }
        scheduleBusy = true
        let previousValue = scheduleEnabled
        let scheduleTime = savedScheduleTime
        scheduleEnabled = enabled

        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    try SchedulerService.setSchedule(enabled: enabled, time: scheduleTime)
                    return OperationOutcome(succeeded: true, message: "")
                } catch {
                    return OperationOutcome(succeeded: false, message: error.localizedDescription)
                }
            }.value

            if !outcome.succeeded {
                scheduleEnabled = previousValue
                alertMessage = outcome.message
            }
            scheduleBusy = false
            refreshLocalState()
        }
    }

    func saveScheduleTime() {
        guard !scheduleBusy, scheduleTimeHasChanges else { return }
        scheduleBusy = true
        let newTime = selectedScheduleTime

        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    try SchedulerService.setScheduleTime(newTime)
                    return OperationOutcome(succeeded: true, message: "")
                } catch {
                    return OperationOutcome(succeeded: false, message: error.localizedDescription)
                }
            }.value

            if outcome.succeeded {
                savedScheduleTime = newTime
            } else {
                scheduleDate = Self.date(from: savedScheduleTime)
                alertMessage = outcome.message
            }
            scheduleBusy = false
            refreshLocalState()
        }
    }

    func addTool(package: String, name: String) -> String? {
        let trimmedPackage = package.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validationError = ToolConfigurationStore.validate(package: trimmedPackage, name: trimmedName) {
            return validationError
        }

        do {
            var definitions = try ToolConfigurationStore.load()
            guard !definitions.contains(where: { $0.package == trimmedPackage }) else {
                return "这个 npm 包已经在列表中。"
            }
            definitions.append(ToolDefinition(package: trimmedPackage, name: trimmedName))
            try ToolConfigurationStore.save(definitions)
            showingAddTool = false
            isRefreshing = false
            refresh()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func deleteTool(_ tool: ToolStatus) {
        do {
            let definitions = try ToolConfigurationStore.load().filter { $0.package != tool.definition.package }
            try ToolConfigurationStore.save(definitions)
            tools.removeAll { $0.id == tool.id }
            isRefreshing = false
            refresh()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func runUpdateNow() {
        guard !isUpdating else { return }
        isUpdating = true

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> OperationOutcome in
                do {
                    let result = try SchedulerService.runManualUpdate()
                    if result.exitCode == 0 {
                        return OperationOutcome(succeeded: true, message: "更新任务已完成。")
                    }
                    return OperationOutcome(
                        succeeded: false,
                        message: result.output.isEmpty ? "更新失败，退出码 \(result.exitCode)" : result.output
                    )
                } catch {
                    return OperationOutcome(succeeded: false, message: error.localizedDescription)
                }
            }.value

            if !outcome.succeeded {
                alertMessage = outcome.message
            }
            isUpdating = false
            isRefreshing = false
            refresh()
        }
    }

    func openDataFolder() {
        try? FileManager.default.createDirectory(
            at: RuntimeLocator.dataDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(RuntimeLocator.dataDirectory)
    }

    func clearAlert() {
        alertMessage = nil
    }

    private func refreshLocalState() {
        Task {
            let snapshot = await Task.detached(priority: .utility) {
                SchedulerService.loadSnapshot()
            }.value
            apply(snapshot)
        }
    }

    private func apply(_ snapshot: LocalSnapshot) {
        scheduleEnabled = snapshot.schedule.enabled
        savedScheduleTime = snapshot.schedule.time
        scheduleDate = Self.date(from: snapshot.schedule.time)
        runtimeStatus = snapshot.runtimeStatus
        logText = snapshot.logText
    }

    private static func date(from time: String) -> Date {
        let fields = time.split(separator: ":")
        let hour = fields.first.flatMap { Int($0) } ?? 9
        let minute = fields.count > 1 ? Int(fields[1]) ?? 0 : 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
