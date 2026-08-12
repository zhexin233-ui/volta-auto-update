## 1. 环境检查与初始化

- [x] 1.1 实现 Volta 可用性检查（使用 command -v volta）
- [x] 1.2 实现并发实例检测（使用 pgrep 检查其他运行实例）
- [x] 1.3 定义工具列表数组（codex、claude-code、opencode 的包名和显示名）
- [x] 1.4 初始化计数器变量（成功、失败、跳过）

## 2. 版本检查功能

- [x] 2.1 实现 check_installed_version 函数（使用 volta list all + 精确包名匹配 + 版本字段提取）
- [x] 2.2 实现 check_latest_version 函数（使用 curl 查询 npm registry API）
- [x] 2.3 实现 JSON 解析逻辑（使用 grep + sed 提取 version 字段）
- [x] 2.4 实现版本比较逻辑（字符串不等比较）
- [x] 2.5 处理版本检查错误状态（NOT_INSTALLED、NETWORK_ERROR、PARSE_ERROR）

## 3. 命令行界面输出

- [x] 3.1 实现欢迎信息和开始检查提示
- [x] 3.2 实现版本对比表格输出（使用 printf 格式化）
- [x] 3.3 实现检查进度显示（使用 emoji 标记：🔍、✓、✗、⚠️）
- [x] 3.4 实现结构化错误消息输出到 stderr
- [x] 3.5 实现最终摘要显示（成功、失败、跳过计数）

## 4. 自动更新功能

- [x] 4.1 实现 update_tool 函数（执行 volta install <package>@latest）
- [x] 4.2 实现更新前的版本状态检查（跳过最新版本和错误状态）
- [x] 4.3 实现更新进度显示（开始、成功、失败消息）
- [x] 4.4 实现更新结果验证（检查 volta install 退出码）
- [x] 4.5 实现 fail-soft 错误处理（单个工具失败不影响其他工具）

## 5. 主流程控制

- [x] 5.1 实现 main 函数（协调版本检查和更新流程）
- [x] 5.2 实现版本检查循环（遍历所有工具）
- [x] 5.3 实现更新循环（仅更新需要更新的工具）
- [x] 5.4 实现退出码策略（0 表示正常，1 表示致命错误）

## 6. macOS 双击执行支持

- [x] 6.1 创建 update-volta-tools.sh 主脚本文件
- [x] 6.2 创建 update-volta-tools.command 文件（添加按键等待逻辑）
- [x] 6.3 设置脚本可执行权限（chmod +x）
- [x] 6.4 添加 shebang 行（#!/bin/bash）

## 7. 错误处理与边界情况

- [x] 7.1 实现 curl 超时和重试配置（--connect-timeout 5 --max-time 10 --retry 2）
- [x] 7.2 处理所有工具已是最新版本的情况
- [x] 7.3 处理网络请求失败的情况
- [x] 7.4 处理 JSON 解析失败的情况
- [x] 7.5 处理 volta install 失败的情况

## 8. 测试与验证

- [x] 8.1 测试正常更新流程（有工具需要更新）
- [x] 8.2 测试所有工具已是最新版本的情况
- [x] 8.3 测试网络错误处理
- [x] 8.4 测试工具未安装的情况
- [x] 8.5 测试并发实例检测
- [x] 8.6 测试 .command 文件双击执行
- [x] 8.7 验证输出格式和 emoji 显示
- [x] 8.8 验证错误消息输出到 stderr
