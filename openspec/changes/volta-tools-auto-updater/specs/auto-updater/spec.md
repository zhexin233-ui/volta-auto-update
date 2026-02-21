## Purpose

自动更新器负责执行实际的工具更新操作，使用 Volta 的 install 命令将过期的工具升级到最新版本。

## ADDED Requirements

### Requirement: 执行 Volta 安装命令
系统 SHALL 能够为需要更新的工具执行 `volta install <package>@latest` 命令。

**实现约束：**
- MUST 使用命令格式：`volta install <package>@latest`（例如：`volta install @openai/codex@latest`）
- MUST 按顺序更新工具，不并行执行（避免 Volta 冲突）
- MUST 在执行前检查 L(p) ≠ ⊥（最新版本已知），否则跳过该工具
- 不需要用户确认，自动执行所有更新

#### Scenario: 成功更新单个工具
- **WHEN** 检测到 codex 需要从 0.89.0 更新到 0.92.0
- **THEN** 系统应执行 `volta install @openai/codex@latest` 并显示更新进度

#### Scenario: 批量更新多个工具
- **WHEN** 检测到多个工具需要更新
- **THEN** 系统应按顺序更新每个工具，并在每次更新后显示结果

#### Scenario: 最新版本未知时跳过
- **WHEN** 某个工具的最新版本状态为 NETWORK_ERROR 或 PARSE_ERROR
- **THEN** 系统 MUST NOT 执行 volta install，应跳过该工具

### Requirement: 更新结果验证
系统 SHALL 在更新完成后验证新版本是否安装成功。

**实现约束：**
- MUST 检查 volta install 的退出码（$?）
- 退出码 0 表示成功，非 0 表示失败
- 失败时 MUST 捕获 stderr 输出并记录到错误消息
- 可选：成功后再次运行 volta list all 验证版本（但不强制要求）

#### Scenario: 更新成功验证
- **WHEN** volta install 命令执行成功（退出码 0）
- **THEN** 系统应标记该工具更新成功

#### Scenario: 更新失败处理
- **WHEN** volta install 命令执行失败（退出码非 0）
- **THEN** 系统应输出结构化错误消息到 stderr，记录失败原因，并继续处理下一个工具

### Requirement: 跳过最新工具
系统 SHALL 跳过已经是最新版本的工具，不执行不必要的安装操作。

**实现约束：**
- MUST 仅对满足 `I(p) != L(p)` 的工具执行更新
- 如果所有工具都满足 `I(p) == L(p)`，MUST 显示"所有工具已是最新版本"消息
- volta install 调用次数 MUST 等于需要更新的工具数量

#### Scenario: 所有工具已是最新
- **WHEN** 所有工具的当前版本都等于最新版本
- **THEN** 系统应显示"所有工具已是最新版本"消息，不执行任何安装命令

#### Scenario: 部分工具已是最新
- **WHEN** 部分工具已是最新版本，部分需要更新
- **THEN** 系统应仅更新需要更新的工具，跳过已是最新的工具

## Property-Based Testing Properties

### Invariant 1: 包隔离性
- **属性：** 对于任何包 p，检查或更新 p 的失败不改变包 q (q≠p) 的更新决策或结果
- **反例生成策略：** 注入一个包的 volta install 失败，验证其他包仍正常更新

### Invariant 2: Fail-soft 错误路由
- **属性：** 任何非致命错误输出结构化消息到 stderr，脚本继续处理剩余包，stdout 保留给正常输出
- **反例生成策略：** 注入多种错误类型（curl 失败、volta install 失败），验证 stderr 包含错误标记且脚本继续

### Invariant 3: 无部分更新
- **属性：** 如果 L(p) = ⊥（最新版本未知），则 MUST NOT 调用 volta install
- **反例生成策略：** 模拟 JSON 解析返回空字符串或 null，验证不执行安装

### Invariant 4: 幂等性
- **属性：** 如果所有工具满足 I(p) = L(p)，运行脚本两次不产生任何 volta install 调用
- **反例生成策略：** 设置所有工具版本相等，运行两次，验证零安装调用

### Invariant 5: 单调副作用
- **属性：** volta install 调用次数 = |{p : I(p)≠⊥ ∧ L(p)≠⊥ ∧ I(p) != L(p)}|
- **反例生成策略：** 生成混合状态（部分需要更新、部分最新、部分失败），验证调用次数匹配
