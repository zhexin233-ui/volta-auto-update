## Purpose

命令行界面负责提供友好的用户交互体验，显示检查和更新过程的进度、结果和错误信息。

## ADDED Requirements

### Requirement: 环境前置检查
系统 SHALL 在脚本启动时检查必要的前置条件。

**实现约束：**
- MUST 检查 volta 命令是否可用：`command -v volta >/dev/null 2>&1`
- MUST 检查是否有其他实例正在运行：`pgrep -f "update-volta-tools" | grep -v $$`
- 如果 volta 不可用，MUST 输出错误到 stderr 并以退出码 1 退出（致命错误）
- 如果检测到并发实例，MUST 输出错误到 stderr 并以退出码 1 退出（致命错误）
- 不检查 curl（假设 macOS 默认包含）
- 不检查 Bash 版本（假设 macOS 默认 Bash >= 3.2）

#### Scenario: Volta 未安装
- **WHEN** 系统中未安装 volta 命令
- **THEN** 系统应输出 "[ERROR] Volta 未安装，请先安装 Volta" 到 stderr 并退出（退出码 1）

#### Scenario: 检测到并发实例
- **WHEN** 已有另一个 update-volta-tools 进程正在运行
- **THEN** 系统应输出 "[ERROR] 检测到其他实例正在运行，请稍后再试" 到 stderr 并退出（退出码 1）

### Requirement: 显示检查进度
系统 SHALL 在检查版本时显示清晰的进度信息。

**实现约束：**
- 输出语言：中文
- 使用 emoji 标记状态：✓（成功）、✗（失败）、⚠️（警告）、🔍（检查中）
- 所有正常输出到 stdout，错误输出到 stderr

#### Scenario: 开始检查提示
- **WHEN** 脚本开始执行
- **THEN** 系统应显示欢迎信息和正在检查的工具列表

#### Scenario: 逐个工具检查反馈
- **WHEN** 检查每个工具的版本
- **THEN** 系统应显示"🔍 正在检查 <工具名>..."消息

### Requirement: 显示版本对比结果
系统 SHALL 以固定宽度表格形式显示每个工具的当前版本和最新版本。

**实现约束：**
- MUST 使用 printf 格式化输出
- 列宽定义：工具名（20字符）、当前版本（12字符）、最新版本（12字符）、状态（15字符）
- 表头格式：`printf "%-20s %-12s %-12s %-15s\n" "工具名" "当前版本" "最新版本" "状态"`
- 数据行格式：`printf "%-20s %-12s %-12s %-15s\n" "$tool" "$current" "$latest" "$status"`
- 状态值：
  * "✓ 最新" - 当前版本 == 最新版本
  * "⚠️ 需要更新" - 当前版本 != 最新版本
  * "✗ 未安装" - 工具未安装
  * "✗ 检查失败" - 网络或解析错误

#### Scenario: 版本对比表格
- **WHEN** 完成所有工具的版本检查
- **THEN** 系统应显示包含工具名、当前版本、最新版本和状态的固定宽度表格

#### Scenario: 高亮需要更新的工具
- **WHEN** 某个工具需要更新
- **THEN** 系统应使用 ⚠️ emoji 标记该工具状态

### Requirement: 显示更新进度
系统 SHALL 在执行更新时显示实时进度。

**实现约束：**
- 更新开始消息格式：`echo "🔄 正在更新 $tool 从 $current 到 $latest..."`
- 更新成功消息格式：`echo "✓ $tool 已更新到 $latest"`
- 更新失败消息格式：`echo "[ERROR] tool=$tool action=update reason=$error_msg" >&2`

#### Scenario: 更新开始提示
- **WHEN** 开始更新某个工具
- **THEN** 系统应显示"🔄 正在更新 <工具名> 从 <旧版本> 到 <新版本>..."

#### Scenario: 更新完成反馈
- **WHEN** 工具更新成功
- **THEN** 系统应显示"✓ <工具名> 已更新到 <新版本>"

#### Scenario: 更新失败反馈
- **WHEN** 工具更新失败
- **THEN** 系统应输出结构化错误消息到 stderr："[ERROR] tool=<工具名> action=update reason=<错误信息>"

### Requirement: 显示最终摘要
系统 SHALL 在所有操作完成后显示摘要信息。

**实现约束：**
- 摘要格式：
  ```
  ========================================
  更新完成！
  成功：<count> 个工具
  失败：<count> 个工具
  跳过：<count> 个工具
  ========================================
  ```
- 如果有失败的工具，MUST 列出失败工具名称

#### Scenario: 成功摘要
- **WHEN** 所有需要更新的工具都成功更新
- **THEN** 系统应显示"所有工具已更新完成！"和更新的工具数量

#### Scenario: 部分失败摘要
- **WHEN** 部分工具更新失败
- **THEN** 系统应显示成功和失败的工具列表

### Requirement: macOS 双击执行支持
系统 SHALL 支持在 macOS 上通过双击 .command 文件执行。

**实现约束：**
- MUST 创建独立的 `update-volta-tools.command` 文件
- .command 文件内容与 .sh 文件相同，但在末尾添加：
  ```bash
  echo ""
  read -p "按任意键关闭..." -n1
  ```
- MUST 设置可执行权限：`chmod +x update-volta-tools.command`
- .command 文件始终暂停等待用户按键，无需检测双击

#### Scenario: 双击执行
- **WHEN** 用户双击 .command 文件
- **THEN** 系统应在终端窗口中打开并执行脚本

#### Scenario: 执行完成后保持窗口
- **WHEN** 脚本执行完成
- **THEN** 终端窗口应保持打开状态，显示"按任意键关闭..."提示，等待用户按键后关闭

### Requirement: 错误消息格式
系统 SHALL 使用结构化格式输出错误消息。

**实现约束：**
- 所有错误 MUST 输出到 stderr
- 错误消息格式：`[ERROR] tool=<工具名> action=<check|update> reason=<错误描述>`
- 示例：`[ERROR] tool=@openai/codex action=check reason=网络超时`
- 致命错误格式：`[ERROR] <错误描述>`（无 tool 和 action 字段）

#### Scenario: 网络错误消息
- **WHEN** curl 请求失败
- **THEN** 系统应输出 "[ERROR] tool=<工具名> action=check reason=网络请求失败" 到 stderr

#### Scenario: 解析错误消息
- **WHEN** JSON 解析失败
- **THEN** 系统应输出 "[ERROR] tool=<工具名> action=check reason=JSON 解析失败" 到 stderr

### Requirement: 退出码策略
系统 SHALL 根据执行结果返回适当的退出码。

**实现约束：**
- 退出码 0：正常执行完成（即使部分工具更新失败）
- 退出码 1：致命错误（Volta 未安装或检测到并发实例）
- 部分工具更新失败不影响退出码（仍返回 0）

#### Scenario: 正常完成
- **WHEN** 脚本正常执行完成（无致命错误）
- **THEN** 系统应返回退出码 0

#### Scenario: 致命错误
- **WHEN** Volta 未安装或检测到并发实例
- **THEN** 系统应返回退出码 1

## Property-Based Testing Properties

### Invariant 1: 输出编码安全
- **属性：** 输出是纯文本（无二进制控制字节），包含中文和 emoji，错误消息始终到 stderr
- **反例生成策略：** 在模拟命令输出中注入控制字符（\r, \x1b, null），验证脚本不输出不安全序列

### Invariant 2: 表格宽度边界
- **属性：** 每个表格行由固定宽度 printf 生成，列数恒定，每列占用定义宽度
- **反例生成策略：** 生成超长包名/版本、CJK 字符、emoji，检查对齐和截断

### Invariant 3: 退出码边界
- **属性：** 退出码始终为 0（正常）或 1（致命错误），非致命失败不改变退出码
- **反例生成策略：** 随机生成失败模式（curl 失败、volta install 失败），在 Volta 可用且无并发时验证退出码为 0

### Invariant 4: 非交互保证
- **属性：** 脚本从不读取 stdin（.command 文件除外），从不阻塞等待用户确认
- **反例生成策略：** 用永不关闭的管道作为 stdin 运行 .sh 文件，验证脚本不挂起

### Invariant 5: 环境门控
- **属性：** 如果 Volta 不可用，脚本不执行任何网络调用或安装，输出错误并终止
- **反例生成策略：** 在 PATH 中移除 volta，用模拟 curl 记录调用，验证 curl 从未被调用
