import Foundation

struct ToolDefinition: Identifiable, Hashable, Sendable {
    let package: String
    let name: String
    let symbol: String

    var id: String { package }

    init(package: String, name: String, symbol: String? = nil) {
        self.package = package
        self.name = name
        self.symbol = symbol ?? Self.defaultSymbol(for: package)
    }

    private static func defaultSymbol(for package: String) -> String {
        switch package {
        case "@openai/codex": "terminal.fill"
        case "@anthropic-ai/claude-code": "sparkles"
        case "opencode-ai": "chevron.left.forwardslash.chevron.right"
        default: "shippingbox.fill"
        }
    }
}

enum ToolVersionState: String, Sendable {
    case latest
    case updateAvailable
    case notInstalled
    case unavailable

    var title: String {
        switch self {
        case .latest: "已是最新"
        case .updateAvailable: "可以更新"
        case .notInstalled: "未安装"
        case .unavailable: "检查失败"
        }
    }
}

struct ToolStatus: Identifiable, Sendable {
    let definition: ToolDefinition
    let currentVersion: String?
    let latestVersion: String?
    let state: ToolVersionState

    var id: String { definition.id }
}

struct RuntimeStatus: Codable, Sendable {
    let schemaVersion: Int
    let state: String
    let mode: String
    let startedAt: String
    let finishedAt: String
    let exitCode: Int?
    let reason: String
    let pid: Int
    let logPath: String

    var stateTitle: String {
        switch state {
        case "running": "正在更新"
        case "success": "更新完成"
        case "failed": "更新失败"
        default: "尚未运行"
        }
    }

    var modeTitle: String {
        mode == "manual" ? "手动执行" : "自动调度"
    }
}

struct CommandResult: Sendable {
    let exitCode: Int32
    let output: String
}

struct LocalSnapshot: Sendable {
    let schedule: ScheduleConfiguration
    let runtimeStatus: RuntimeStatus?
    let logText: String
}

struct ScheduleConfiguration: Sendable {
    let enabled: Bool
    let time: String
}

struct OperationOutcome: Sendable {
    let succeeded: Bool
    let message: String
}
