## Why

用户需要一个便捷的方式来保持 Volta 管理的开发工具（codex、claude-code、gemini-cli）始终处于最新版本。手动检查和更新这些工具既耗时又容易遗漏，自动化这个过程可以确保开发环境始终使用最新的功能和安全补丁。

## What Changes

- 创建一个可执行的 shell 脚本 `update-volta-tools.sh`，用于自动检查和更新 Volta 管理的工具
- 脚本支持检查三个包的当前版本和 npm registry 上的最新版本
- 当检测到版本不一致时，自动执行 `volta install` 命令进行更新
- 提供清晰的命令行输出，显示检查和更新过程
- 支持 macOS 系统，可通过双击 `.command` 文件或终端直接执行

## Capabilities

### New Capabilities
- `version-checker`: 检查 Volta 管理的工具的当前版本和 npm registry 上的最新版本
- `auto-updater`: 自动更新过期的工具到最新版本
- `cli-interface`: 提供友好的命令行界面，显示检查和更新进度

### Modified Capabilities
<!-- 无现有能力需要修改 -->

## Impact

- 新增文件：`update-volta-tools.sh`（主脚本）
- 可选新增：`update-volta-tools.command`（macOS 双击执行版本）
- 无现有代码受影响
- 依赖：需要系统已安装 volta、curl/wget（用于查询 npm registry）
- 用户体验：提供一键更新所有工具的便捷方式
