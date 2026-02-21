## Purpose

版本检查器负责检测 Volta 管理的工具的当前安装版本，并从 npm registry 获取最新可用版本，以便判断是否需要更新。

## ADDED Requirements

### Requirement: 检测已安装工具版本
系统 SHALL 能够检测 Volta 管理的 codex、claude-code 和 gemini-cli 的当前安装版本。

**实现约束：**
- MUST 使用 `volta list all` 命令获取已安装工具列表
- MUST 使用精确包名匹配：`grep '^package @openai/codex@'` 避免子串误匹配
- MUST 使用 sed 提取版本号：`sed 's/.*@\([0-9.]\+\).*/\1/'`
- 如果 grep 找不到包名，MUST 返回状态 `NOT_INSTALLED`
- 如果找到包名但无法解析版本，MUST 返回状态 `UNKNOWN`

#### Scenario: 成功检测所有工具版本
- **WHEN** 脚本执行版本检查
- **THEN** 系统应返回三个工具的当前版本号（格式：x.y.z）

#### Scenario: 工具未安装
- **WHEN** 某个工具未通过 Volta 安装
- **THEN** 系统应标记该工具为"NOT_INSTALLED"状态

#### Scenario: 版本解析失败
- **WHEN** volta list all 输出格式异常
- **THEN** 系统应标记该工具为"UNKNOWN"状态

### Requirement: 获取 npm registry 最新版本
系统 SHALL 能够从 npm registry 查询每个包的最新发布版本。

**实现约束：**
- MUST 使用 curl 命令：`curl -fsSL --connect-timeout 5 --max-time 10 --retry 2 --retry-delay 1`
- MUST 查询 URL：`https://registry.npmjs.org/<package>/latest`（scoped 包使用 `@scope/name` 格式，无需 URL 编码）
- MUST 使用 grep + sed 解析 JSON：`grep '"version"' | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'`
- 如果 curl 失败（非零退出码），MUST 返回状态 `NETWORK_ERROR`
- 如果 JSON 解析失败（grep 无匹配），MUST 返回状态 `PARSE_ERROR`
- 总网络调用次数 MUST ≤ 3 × |packages| = 9（每个包最多 3 次尝试）

#### Scenario: 成功获取最新版本
- **WHEN** 查询 npm registry API（https://registry.npmjs.org/<package>/latest）
- **THEN** 系统应解析 JSON 响应并提取 version 字段

#### Scenario: 网络请求失败
- **WHEN** npm registry 无法访问或请求超时
- **THEN** 系统应返回 NETWORK_ERROR 状态并跳过该包的更新检查

#### Scenario: JSON 解析失败
- **WHEN** API 返回非预期格式或不包含 version 字段
- **THEN** 系统应返回 PARSE_ERROR 状态并跳过该包的更新检查

### Requirement: 版本比较
系统 SHALL 能够比较当前版本和最新版本，判断是否需要更新。

**实现约束：**
- MUST 使用简单字符串不等比较：`if [ "$current" != "$latest" ]; then update; fi`
- 不进行语义化版本排序（即 1.10.0 vs 1.9.0 按字符串比较）
- 如果 current > latest（字符串比较），仍然会尝试更新（用户可能在使用预发布版本）
- 版本字符串 MUST 保持原样，不进行规范化（保留前导零、v 前缀等）

#### Scenario: 版本一致
- **WHEN** 当前版本等于最新版本（字符串相等）
- **THEN** 系统应标记该工具为"最新"状态

#### Scenario: 版本不一致
- **WHEN** 当前版本不等于最新版本（字符串不等）
- **THEN** 系统应标记该工具为"需要更新"状态，并记录两个版本号

#### Scenario: 当前版本高于最新版本
- **WHEN** 当前版本字符串 > 最新版本字符串（如 2.0.0 vs 1.9.9）
- **THEN** 系统仍应标记为"需要更新"（因为使用字符串不等比较）

## Property-Based Testing Properties

### Invariant 1: Round-trip 版本提取正确性
- **属性：** 对于任何包含 `"version":"X"` 的 JSON 文本 J，提取函数 extract_version(J) = X
- **反例生成策略：** 生成包含额外空格、换行符、嵌套 version 字段、转义引号的 JSON 变体

### Invariant 2: Volta 输出精确匹配
- **属性：** 给定包含包名 p 的 Volta 输出，解析器返回对应版本 I(p)，且不会与包含 p 作为子串的其他包混淆
- **反例生成策略：** 生成相似包名（@scope/tool, @scope/toolkit, tool, tool2）的 volta list 输出

### Invariant 3: 版本比较确定性
- **属性：** 更新决策仅依赖字符串不等：update(p) ⇔ (I(p)≠⊥ ∧ L(p)≠⊥ ∧ I(p) != L(p))
- **反例生成策略：** 生成语义等价但文本不同的版本表示（1.0.0 vs 1.0.0 , v1.0.0, 01.0.0）

### Invariant 4: 网络调用边界
- **属性：** 每个包的 registry 检查 ≤ 3 次 curl 调用（1 次初始 + 2 次重试）
- **反例生成策略：** 模拟 curl 失败模式，记录调用次数，确保不超过边界
