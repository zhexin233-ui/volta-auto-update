import AppKit
import Foundation

enum AppServiceError: LocalizedError {
    case missingResource(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingResource(name):
            "App 资源缺失：\(name)"
        case let .commandFailed(message):
            message
        }
    }
}

enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in newValue }
        }

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

enum RuntimeLocator {
    static let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Volta Auto Update", isDirectory: true)
    static let runtimeDirectory = dataDirectory.appendingPathComponent("Runtime", isDirectory: true)
    static let logsDirectory = dataDirectory.appendingPathComponent("Logs", isDirectory: true)
    static let statusFile = dataDirectory.appendingPathComponent("status.json")
    static let updateLog = logsDirectory.appendingPathComponent("update.log")
    static let toolsFile = dataDirectory.appendingPathComponent("tools.tsv")

    static var bundledRuntimeDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Runtime", isDirectory: true)
    }

    static var scheduleManager: URL? {
        bundledRuntimeDirectory?.appendingPathComponent("schedule-manager.sh")
    }

    static var installedRunner: URL {
        runtimeDirectory.appendingPathComponent("scheduled-update.sh")
    }
}

enum SchedulerService {
    private static func runManager(_ arguments: [String]) throws -> CommandResult {
        guard let manager = RuntimeLocator.scheduleManager,
              FileManager.default.fileExists(atPath: manager.path)
        else {
            throw AppServiceError.missingResource("schedule-manager.sh")
        }

        return try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/bash"),
            arguments: [manager.path] + arguments
        )
    }

    static func syncRuntime() throws {
        let result = try runManager(["sync"])
        guard result.exitCode == 0 else {
            throw AppServiceError.commandFailed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func setSchedule(enabled: Bool, time: String) throws {
        let arguments = enabled ? ["enable", time] : ["disable"]
        let result = try runManager(arguments)
        guard result.exitCode == 0 else {
            throw AppServiceError.commandFailed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func setScheduleTime(_ time: String) throws {
        let result = try runManager(["set-time", time])
        guard result.exitCode == 0 else {
            throw AppServiceError.commandFailed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func scheduleConfiguration() -> ScheduleConfiguration {
        guard let result = try? runManager(["status"]), result.exitCode == 0 else {
            return ScheduleConfiguration(enabled: false, time: "09:00")
        }

        let fields = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|", maxSplits: 1)
        guard fields.count == 2 else {
            return ScheduleConfiguration(enabled: false, time: "09:00")
        }
        return ScheduleConfiguration(enabled: fields[0] == "enabled", time: String(fields[1]))
    }

    static func runManualUpdate() throws -> CommandResult {
        try syncRuntime()
        guard FileManager.default.fileExists(atPath: RuntimeLocator.installedRunner.path) else {
            throw AppServiceError.missingResource("scheduled-update.sh")
        }

        return try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/bash"),
            arguments: [RuntimeLocator.installedRunner.path, "manual"]
        )
    }

    static func loadSnapshot() -> LocalSnapshot {
        let status: RuntimeStatus?
        if let data = try? Data(contentsOf: RuntimeLocator.statusFile) {
            status = try? JSONDecoder().decode(RuntimeStatus.self, from: data)
        } else {
            status = nil
        }

        let logText: String
        if let data = try? Data(contentsOf: RuntimeLocator.updateLog) {
            let tail = data.suffix(80_000)
            logText = String(data: tail, encoding: .utf8) ?? ""
        } else {
            logText = "暂无运行日志。"
        }

        return LocalSnapshot(
            schedule: scheduleConfiguration(),
            runtimeStatus: status,
            logText: logText
        )
    }
}

enum ToolConfigurationStore {
    static let defaultDefinitions = [
        ToolDefinition(package: "@openai/codex", name: "Codex"),
        ToolDefinition(package: "@anthropic-ai/claude-code", name: "Claude Code"),
        ToolDefinition(package: "opencode-ai", name: "opencode")
    ]

    static func load() throws -> [ToolDefinition] {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: RuntimeLocator.toolsFile.path) {
            try save(defaultDefinitions)
            return defaultDefinitions
        }

        let contents = try String(contentsOf: RuntimeLocator.toolsFile, encoding: .utf8)
        var definitions: [ToolDefinition] = []
        var seenPackages: Set<String> = []

        for (offset, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            if line.isEmpty { continue }

            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2 else {
                throw AppServiceError.commandFailed("工具配置第 \(offset + 1) 行格式无效。")
            }

            let package = String(fields[0])
            let name = String(fields[1])
            if let validationError = validate(package: package, name: name) {
                throw AppServiceError.commandFailed("工具配置第 \(offset + 1) 行：\(validationError)")
            }
            guard seenPackages.insert(package).inserted else {
                throw AppServiceError.commandFailed("工具配置包含重复包名：\(package)")
            }
            definitions.append(ToolDefinition(package: package, name: name))
        }

        return definitions
    }

    static func save(_ definitions: [ToolDefinition]) throws {
        try FileManager.default.createDirectory(
            at: RuntimeLocator.dataDirectory,
            withIntermediateDirectories: true
        )

        var seenPackages: Set<String> = []
        for definition in definitions {
            if let validationError = validate(package: definition.package, name: definition.name) {
                throw AppServiceError.commandFailed(validationError)
            }
            guard seenPackages.insert(definition.package).inserted else {
                throw AppServiceError.commandFailed("包名已存在：\(definition.package)")
            }
        }

        let contents = definitions
            .map { "\($0.package)\t\($0.name)" }
            .joined(separator: "\n") + (definitions.isEmpty ? "" : "\n")
        try contents.data(using: .utf8)?.write(to: RuntimeLocator.toolsFile, options: .atomic)
    }

    static func validate(package: String, name: String) -> String? {
        let packagePattern = #"^(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$"#
        if package.range(of: packagePattern, options: .regularExpression) == nil {
            return "请输入有效的 npm 包名。"
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName.count > 60 || name.contains("\t") || name.contains("\n") || name.contains("\r") {
            return "显示名需为 1–60 个字符，且不能包含换行或制表符。"
        }
        return nil
    }
}

enum ToolVersionParser {
    static func parse(_ output: String, definitions: [ToolDefinition]) -> [String: String] {
        var versions: [String: String] = [:]

        for line in output.components(separatedBy: .newlines) {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count >= 2, fields[0] == "package" else { continue }
            let entry = String(fields[1])

            for definition in definitions {
                let prefix = "\(definition.package)@"
                guard entry.hasPrefix(prefix) else { continue }
                let version = String(entry.dropFirst(prefix.count))
                if !version.isEmpty {
                    versions[definition.package] = version
                }
            }
        }

        return versions
    }
}

enum VersionService {
    private struct RegistryResponse: Decodable {
        let version: String
    }

    private static func locateVolta() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []

        if let voltaHome = environment["VOLTA_HOME"], !voltaHome.isEmpty {
            candidates.append(URL(fileURLWithPath: voltaHome).appendingPathComponent("bin/volta"))
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent(".volta/bin/volta"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/volta"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/volta"))

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func currentVersions(definitions: [ToolDefinition]) -> [String: String] {
        guard let volta = locateVolta(),
              let result = try? ProcessRunner.run(executable: volta, arguments: ["list", "all"]),
              result.exitCode == 0
        else {
            return [:]
        }

        return ToolVersionParser.parse(result.output, definitions: definitions)
    }

    private static func latestVersion(for package: String) async -> String? {
        guard let url = URL(string: "https://registry.npmjs.org/\(package)/latest") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode)
            else {
                return nil
            }
            return try JSONDecoder().decode(RegistryResponse.self, from: data).version
        } catch {
            return nil
        }
    }

    static func loadStatuses(definitions: [ToolDefinition]) async -> [ToolStatus] {
        let current = await Task.detached(priority: .userInitiated) {
            currentVersions(definitions: definitions)
        }.value

        var results: [ToolStatus] = []
        for definition in definitions {
            let latest = await latestVersion(for: definition.package)
            let installed = current[definition.package]
            let state: ToolVersionState

            if installed == nil {
                state = .notInstalled
            } else if latest == nil {
                state = .unavailable
            } else if installed == latest {
                state = .latest
            } else {
                state = .updateAvailable
            }

            results.append(
                ToolStatus(
                    definition: definition,
                    currentVersion: installed,
                    latestVersion: latest,
                    state: state
                )
            )
        }

        return results
    }
}
