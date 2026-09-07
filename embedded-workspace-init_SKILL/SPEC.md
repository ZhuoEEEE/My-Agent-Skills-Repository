# embedded-workspace-init Skill 设计交接

## 状态

- 本目录保存已经讨论确认的 Skill 设计，不是已安装或可直接调用的 Skill。
- 实际 Skill 后续应使用 `skill-creator` 创建、验证和安装。
- 建议 Skill 名称：`embedded-workspace-init`。
- 建议调用方式：仅显式调用，关闭隐式调用。
- 本 Skill 负责初始化和刷新工作区，不负责日常功能开发。

建议在实际 Skill 的 `agents/openai.yaml` 中设置：

```yaml
policy:
  allow_implicit_invocation: false
```

## 目标

为一个可能包含单个或多个 MCU、多个 IDE 工程、公共代码、理论资料和验证内容的嵌入式产品建立 Agent 工作区。

初始化后应达到以下结果：

- 用户继续在原有 IDE 和编辑器中维护自己的权威工程。
- Agent 默认只读用户权威工程，在工作区受管副本中开发、构建和验证。
- 不要求用户工程采用固定源码结构，也不重组 IDE 生成的工程。
- 多个对话可以通过独立 workstream 并行工作。
- 后续出现新 MCU 工程时自动登记并纳入 Agent 私有 Git。
- Agent 与用户工程通过同步基线进行三方比较，仅在用户明确表达发布意图时写回。
- 普通 Agent 即使没有专门的日常开发 Skill，也能通过根 `AGENTS.md` 正常工作。
- 工作区提供独立的参考工程目录，供 Agent 按需查阅和比较，但不参与用户工程同步。
- 工作区提供持久项目知识层，区分产品定义、当前方案、开发路径、版本边界和任务过程。
- 已初始化工作区能够受控进化：项目事实自动适配，规则和结构只在用户确认具体计划后迁移。
- 工作区根目录保持整洁，所有工具、脚本、日志和其他产物分类存放并具有说明。
- 根目录生成面向用户的中文使用手册，隐藏内部复杂度。

## 不做的事情

- 不规定 `bsp/`、`drivers/`、`middleware/`、`app/` 等源码布局。
- 不将现有工程转换为 CMake、PlatformIO 或其他构建体系。
- 不为了统一管理而移动、重命名或重组用户工程。
- 不自动修复初始化时发现的源码或构建错误。
- 不自动安装或升级 IDE、工具链、SDK、Pack、许可证或依赖。
- 不在初始化阶段烧录、擦除、调试或操作板卡。
- 不提供后台实时文件监控；自动响应发生在下一次 Agent 任务中。
- 不创建专用 Windows 账户、NTFS ACL、虚拟机或独立 Publisher。
- 不承诺操作系统级绝对隔离；采用工作副本、路径检查、Git 和备份形成软隔离。
- 不实现板卡资源锁或持久化硬件租约。
- 不强制完整分层测试流水线，不为了形式引入测试框架或模拟器。
- 不创建专用 Git 提交 Skill；提交规则由 `AGENTS.md` 约束。

## 核心术语

### 用户权威工程

用户日常使用 IDE 和其他编辑器维护的原始工程。它可能位于工作区之外，也可能有多个分散路径。Agent 默认只读，只有明确的发布流程可以写入；兼容模式下，经用户确认的初始化或规则迁移可以仅修改具体计划列出的根管理文档，这是唯一的窄例外，不得借此修改业务工程文件。

### 权威源组

需要保持相对路径、共享代码或共同生成配置的一组用户工程路径。每个源组使用稳定的 `source-id`。

### 目标

一个可识别、构建或验证的 MCU 工程，使用稳定且人类可读的 `target-id`。一个源组可以包含多个目标；相同 MCU 型号也可以有多个目标。

### 集成副本

`sources/<source-id>/integration/` 中的 Agent 受管副本。它保持用户源组必要的目录拓扑，并由 Agent 私有 Git 管理。

### Workstream

一个逻辑开发任务及其独立工作副本。通常一个对话对应一个 workstream；一个 workstream 可以同时涉及多个目标、模块和源组。

### 同步基线

用户权威工程与 Agent 集成副本最后一次一致时的状态，用于比较“基线、用户当前工程、Agent 当前 workstream”并检测冲突。

### 参考工程

放在 `reference-projects/` 中、仅供阅读、比较和借鉴的工程快照。参考工程不是用户权威工程、受管源组、构建目标或发布对象，Agent 不在其中直接开发。

### 管理根目录

Skill 创建和维护分类结构的逻辑根目录。纯净工作区模式使用当前工作区根目录 `.`；兼容模式使用当前工作区下的 `agent-workspace/`，分别记录为 `managed_root: .` 和 `managed_root: agent-workspace`。

## 建议调用

首次初始化示例：

```text
$embedded-workspace-init 使用这些用户工程路径初始化当前嵌入式工作区：<paths>。保持原有 IDE 工程结构不变。
```

显式重新扫描示例：

```text
$embedded-workspace-init 重新扫描并补充登记新增的 MCU 工程，保留已有确认信息。
```

增加外部分散工程示例：

```text
$embedded-workspace-init 将 <path> 作为新的用户权威源加入当前工作区。
```

初始化已有工作区示例：

```text
$embedded-workspace-init 检查这个已有工作区并制定初始化方案；确认前不要修改任何内容。
```

添加参考工程示例：

```text
$embedded-workspace-init 将 <path-or-url> 导入为参考工程，仅供 Agent 查阅，不作为开发或发布目标。
```

## 初始化与迁移模式

同一个 Skill 支持首次初始化、中途初始化、重新扫描和受控升级。首次接入尚未初始化的工作区时，先解析当前工作区与所有用户权威工程的真实路径，再选择布局模式：

- 所有用户权威工程都位于当前工作区之外时，使用默认的纯净工作区模式。
- 任一用户权威工程位于当前工作区内部或正好就是工作区根目录时，使用兼容模式。
- 符号链接、junction、路径映射或嵌套仓库导致归属无法可靠判断时，不猜测模式，只展示检测结果并等待用户决定。
- 已存在有效 `workspace.yaml` 时始终沿用其中记录的 `layout_mode` 和 `managed_root`；后续源路径变化导致现状与模式不再匹配时只提出迁移方案，不自动切换模式。

对空工作区的明确初始化调用可以直接执行。首次接入非空工作区、改变布局/规则/结构或进行 schema 迁移时，确认具体计划前都只能只读盘点；不得创建备份、目录、配置、私有 Git 或运行会产生输出的构建。已经初始化且不改变策略、布局或结构的纯事实重新扫描可以按幂等规则直接更新；如果同一次调用还发现需要迁移的内容，则整次调用转入零写入计划模式。

### 纯净工作区模式

配置为：

```yaml
layout_mode: pure
managed_root: .
```

空工作区直接创建标准结构。非空工作区采用“外部完整快照、分类重建、验证后启用”：

1. 只读盘点现有文件、目录、Git、未提交状态、工程入口、链接和说明文件。
2. 在对话中展示模式、预计备份位置、分类映射、排除项、Git 边界、将创建或移动的内容、验证和回滚方法，然后停止等待用户确认。
3. 用户未回应、拒绝或取消时零写入结束；只确认部分内容时先生成新计划，不自行实施部分迁移。
4. 用户确认完整计划后，重新检查当前状态；发生实质变化时更新计划并再次确认。
5. 提醒用户保存相关 IDE 和编辑器内容，并在迁移期间暂停写入当前工作区。
6. 在当前工作区之外的同级目录创建完整恢复备份，保留原目录结构并生成文件数量、大小和 SHA-256 清单。
7. 在同级临时目录建立新的标准结构，从已验证备份按明确分类映射复制内容，不把备份本身当作迁移源之外的活跃工程。
8. 无法可靠分类的内容进入迁移待确认清单，不擅自删除、改名或归类。
9. 检查文件清单、Git 边界、相对路径、敏感内容、工程识别和可用构建入口。
10. 验证通过后启用新结构，并要求重新打开工作区以加载新规则。
11. 备份继续保留为人工恢复点，初始化系统不自动删除。

外部备份使用包装目录，快照内容放在 `snapshot/` 中：

```text
<workspace>.pre-init-backup-YYYYMMDD-HHMMSS/
|-- AGENTS.override.md
|-- README.md
|-- backup-manifest.json
`-- snapshot/
```

- `README.md` 记录来源工作区、创建时间、原路径、恢复方法和人工删除责任，并醒目标注：不要再添加为 Codex 工作区，不参与后续同步和构建。
- `AGENTS.override.md` 要求误进入该备份根目录的 Agent 只允许检查和恢复，不得修改、构建、登记、同步或发布。
- `backup-manifest.json` 是扫描器的机器可读排除标记；目标发现、参考工程发现、构建和同步工具必须跳过整个备份树。
- `snapshot/` 使用 `recovery-backup` 复制策略，尽量原样保存现有内容，包括 `.git`、敏感文件、缓存和本机状态；它不应用 Agent 导入时的过滤规则，也不得进入 Agent 私有 Git。
- 备份不跟随符号链接或 junction 展开外部目录，而是在清单中记录链接及解析目标；尽可能保留文件属性和权限信息。
- 无法获得一致、完整且校验通过的恢复快照时，将备份标记为 `partial`，不得替换或重组原工作区。
- 新工作区的 `workspace-management/migration/initialization-report.md` 记录备份位置、校验结果、迁移映射、保留项和未执行事项。
- 根 `USER_GUIDE.md` 记录通用备份原则，但不把备份登记为权威源、参考工程或目标。
- 创建并验证备份后只提醒用户一次：`初始化备份位于 <path>。请勿将其添加为 Codex 工作区，也不要用于同步或构建。确认新工作区正常后，它仅作为人工恢复点保留，是否删除由你决定。`
- 每次备份使用唯一 `backup_id`。提醒完成后将 `workspace.yaml` 中的 `migration.last_notified_backup_id` 更新为当前 ID；后续正常任务不重复提醒，新建另一份备份时则对新 ID 再提醒一次。

### 兼容模式

仅在检测到用户权威工程位于当前工作区内时启用：

```yaml
layout_mode: compatibility
managed_root: agent-workspace
```

- 用户权威工程和其他既有内容保持原路径，不移动、不重组、不重新格式化。
- 根目录保留既有工程结构，只最小合并必要的 `AGENTS.md` 和入口说明；Agent 管理内容集中到 `agent-workspace/`。
- `sources/`、`work/`、`reference-projects/`、`project-docs/` 和 `workspace-management/` 均位于 `agent-workspace/` 下。
- 导入用户工程时使用显式包含和排除清单，始终排除 `agent-workspace/`，防止递归复制和 IDE 重复索引。
- 当前权威工程不能直接被认作 Agent 集成副本，仍需建立独立副本和私有 Git。
- 根目录已有 `AGENTS.md`、`README.md` 或其他说明时不整文件覆盖；兼容内容最小合并，实质冲突先展示方案。
- 用户确认具体初始化或迁移计划后，只允许修改计划逐项列出的根 `AGENTS.md`、入口 `README.md` 和 `USER_GUIDE.md` 等管理文档；这是 publish 之外唯一允许写入权威工程根的场景，业务源码、工程配置和现有资料仍不得修改、移动或重命名。

### 已有工作区通用保护

- 初始化已开发到一半的工程时，将当前已保存内容视为导入基线，不把编译失败视为初始化失败。
- 不自动认领或提交用户已有改动，不为了验证重新生成或修复业务源码。
- `sources/`、`work/`、`reference-projects/`、`project-docs/`、`agent-workspace/` 或 `workspace-management/` 已有其他用途时，不得自动认领或覆盖。
- 已有 Git 只识别和保护，不创建错误嵌套仓库、不改写历史、不夹带既有修改。
- 已初始化工作区再次调用时保持幂等，只修复缺失内容、刷新事实或执行经过确认的迁移。

## 多权威源和源组判断

- 多个 MCU 工程位于同一个合理产品目录时，整体建立一个源组副本。
- 分散且相互独立的工程分别登记为不同源组并分别建立副本。
- 分散目录存在共享代码、相对路径依赖或共同生成器配置时，优先保持原有相对拓扑并作为同一逻辑源组处理。
- 如果维持相对关系需要复制一个包含大量无关内容的上级目录，使用多个路径映射复刻必要拓扑，不复制整个无关父目录。
- 不为管理方便改变用户原有路径、目录名或工程关系。
- 初始化前校验用户源路径和 Agent 副本路径解析后的真实位置不会形成递归包含。
- 副本路径优先使用较短、纯 ASCII、无特殊字符的路径，以兼容旧工具链。

用户工程的绝对路径属于本机信息，只写入被 Agent 私有 Git 忽略的 `targets.local.yaml`。

## 初始化流程

1. 检查工作区现有文件、目录、`AGENTS.md`、Git 和未提交状态。
2. 获取用户提供的权威工程路径；不递归扫描整台电脑寻找工程。
3. 尚未初始化时解析真实路径并选择模式；已初始化时读取并沿用 `workspace.yaml` 中记录的模式。
4. 首次接入非空工作区或需要策略/结构迁移时先以只读方式展示具体计划；用户确认后才建立备份、创建目录或迁移内容。纯事实重新扫描不走迁移流程。
5. 识别源组、Git 边界、共享路径和嵌套仓库。
6. 扫描疑似敏感文件和应排除的可重建缓存。
7. 按源组创建集成副本，保持必要拓扑。
8. 为每个源组自动建立或确认 Agent 私有 Git，并创建导入基线。
9. 发现 MCU 工程，生成稳定 `target-id` 并写入目标配置。
10. 识别或导入用户明确提供的参考工程，并与开发源严格区分。
11. 识别 IDE、生成器、构建配置、工具链、产物和可用验证入口。
12. 在安全条件满足时尝试一次普通基线构建。
13. 询问用户是否为没有 Git 的权威工程创建 Git。
14. 生成规则、概览、用户手册、项目知识层、分类目录和确定性管理脚本。
15. 验证配置可读、私有 Git 有效、分类结构正确且用户工程未被意外修改。

## 后续新 MCU 工程

Agent 私有 Git 是持续约束，不是初始化时的一次性动作。

触发规则：

- Agent 创建、导入或复制新 MCU 工程后立即识别和登记。
- 用户在已登记源路径中通过 IDE 创建新工程后，下一次 Agent 任务开始时自动发现并登记。
- 新工程位于未登记的外部路径时，Agent 只有在用户提供该路径或任务明确访问该路径后才能发现；不得扫描整块磁盘。
- 用户可以随时显式调用重新扫描作为兜底。

自动处理：

- 新工程属于已有源组：纳入已有集成副本和该源组的 Agent 私有 Git，不创建嵌套 `.git`。
- 新工程属于全新独立源组：自动创建新的集成副本和 Agent 私有 Git。
- 新工程与已有目录共享依赖：保持相对拓扑后纳入同一源组。
- Agent 根据工程名称或用途生成稳定且人类可读的 `target-id`，重名时追加最小可用序号。
- `target-id` 写入后不随目录重命名自动变化；显示名称可以更新。
- 创建导入基线提交后再允许 Agent 修改该工程。

存在下列歧义时，只建立待确认候选，不正式登记：

- 无法判断是新工程、备份、复制品还是厂商示例。
- 存在嵌套工程入口或嵌套 Git。
- 已登记工程疑似移动、拆分或合并。
- 新扫描结果与已确认的 MCU、构建命令或生成代码边界冲突。

## 幂等要求

- 已存在的文件、目录和私有 Git 不重复初始化。
- 已登记且没有变化的目标不重写配置、不创建空提交。
- 已确认或已验证字段不被启发式结果静默覆盖。
- 新扫描只补充缺失信息或追加新对象。
- 消失或移动的工程标记为待确认，不直接删除记录。
- 构建命令或工具链变化时保留旧信息并报告差异。
- 人工维护的配置发生并发变化时重新读取，不能覆盖。

## 两套 Git 必须分离

### 用户权威工程 Git

用户工程 Git 是可选的，由用户决定是否创建以及何时提交。

- 已存在 Git：识别并保护现状，不自动提交普通开发改动。
- 不存在 Git：展示建议的仓库边界，并询问一次是否初始化和创建首次基线。
- 用户同意：创建针对实际 IDE 的 `.gitignore`，检查纳入范围，并创建首次基线提交。
- 用户拒绝：记录 `user_git: disabled`。
- 用户未回应：记录 `user_git: deferred`，继续其余初始化，不阻塞。
- 后续用户要求启用时，重新扫描后只补 Git 部分。
- 用户工程 Git 为 `deferred` 时，只有实际修改或发布到用户工程的任务结束后提醒：`Git 已暂缓，当前没有完整版本回退保障。`
- 纯读取、理论讨论或只修改 Agent 副本时不提示。
- 发布到用户工程默认只改变工作树，不自动提交；只有用户明确要求提交时才提交。

初始化用户 Git 前必须检查：

- 嵌套 `.git`、submodule、worktree 和 Git LFS。
- 合理的仓库根目录，不能为了多 MCU 建立覆盖大量无关文件的上层仓库。
- IDE 缓存、构建产物、本机状态和敏感内容。
- 将纳入和排除的内容摘要。

发现仓库边界歧义时暂停用户 Git 部分，不影响其他初始化。

首次基线提交建议：

```text
chore: establish embedded project baseline
```

它只表示当前已保存工程状态，不表示功能完成。

### Agent 私有 Git

Agent 私有 Git 是强制且自动维护的工作区内部机制，不再单独询问用户。

- 每个受管源组始终必须由 Agent 私有 Git 覆盖。
- 用户源组对应单个 Git 仓库时，优先建立不共享对象库的独立本地 clone，并导入用户当前已保存的 dirty 和必要 untracked 内容。
- 用户源组没有 Git，或由多个路径映射组成时，在保持拓扑的集成副本内初始化私有 Git。
- 自动创建导入基线和必要的内部检查点提交。
- 自动为不同 workstream 创建分支和 worktree。
- 不配置可写推送流程，不把内部提交推送或写入用户工程 Git。
- 新增 MCU 工程时自动纳入相应私有 Git并创建导入提交。
- Agent 私有 Git 只能恢复已经导入的状态，不能替代用户工程自身的完整版本保障。

推荐配置语义：

```yaml
git:
  user_source:
    status: deferred
    auto_commit: false
  agent_copy:
    status: enabled
    auto_baseline: true
    auto_checkpoints: true
    push: disabled
```

## 多对话并行

一个公共集成副本只用于汇总，不直接作为所有对话的共同写入目录。

```text
用户权威源
    -> sources/<source-id>/integration/
    -> work/<workstream-id>/<source-id>/
```

- 每个独立逻辑任务使用独立 workstream、私有 Git 分支、worktree 和构建输出。
- 一个对话通常复用一个 workstream，不因多轮对话重复创建。
- 一个 workstream 可以同时挂载多个源组的 worktree。
- 不同 workstream 不直接写同一物理源码文件。
- 新任务开始前读取所有 `active` workstream 的目标和路径范围；范围重叠时先协调。
- 同一对话中的子 Agent 由主 Agent 分配边界，同一文件同时只能有一个写入者。
- workstream 先合入 Agent 集成副本，解决冲突后才能发布到用户权威工程。
- 不使用容易因异常退出而遗留的手工锁文件。

## Workstream 状态记录

日志采用“每个逻辑任务一份最新状态快照”，不采用不断追加的聊天流水日志。

推荐位置：

```text
work/<workstream-id>/README.md
```

建议最小结构：

```markdown
---
id: 20260906-motor-stall-a13f
status: active
updated: 2026-09-06
targets: [motor-controller]
scope: [Motor/Core, Shared/Protocol]
---

## Goal

## Current state

## Decisions

## Changes

## Verification

## Next
```

只在下列时机更新：

- 开始修改工程或产生需要交接的长期决策时。
- 目标、范围或关键方案变化时。
- 完成一组有意义的修改和验证时。
- 暂停、阻塞、交接或完成前。

不记录完整聊天、每条命令、完整构建输出或无关浏览过程。Git 记录“改了什么”，workstream 记录“为什么、当前状态和下一步”。全局活动状态通过读取各 workstream 文件头动态生成，不维护容易过期的手写状态索引。

## 用户工程导入与发布

只定义三个方向明确的操作：

- `inspect`：只读检查用户工程。
- `import`：用户工程到 Agent 集成副本或当前 workstream。
- `publish`：当前 Agent workstream 到用户权威工程。

### 任务开始导入

每次开发任务开始时执行轻量三方检查：

- 有 Git 时比较提交和工作区差异。
- 无 Git 时先比较文件清单、大小和修改时间，只对变化候选计算哈希。
- 只扫描已登记源路径，不扫描整台电脑。
- 用户变化、Agent 未修改相同位置时自动导入。
- 双方修改不同文件或文本文件不同区域时可以三方合并。
- 同一位置、删除与修改、二进制、生成代码或 IDE 元数据冲突时停止该文件同步并报告。
- 长任务在构建前和发布前再次检查相关文件。

### 发布意图

推荐表达：

```text
将工作区中的 Agent 工程同步到我的工程中。
```

不得将其实现为固定口令。所有明确表达“Agent 工作副本到用户权威工程”的同步、合并、应用或发布意图都触发相同流程，例如：

- 把 Agent 工程同步回我的工程。
- 将工作副本修改合并到原工程。
- 把当前 workstream 的改动应用到用户工程。
- 用工作区中的版本更新我的工程。

反方向表达属于 `import`。只说“同步工程”且方向或 workstream 不明确时询问一次。

### 发布流程

1. 提醒用户一次：保存相关 IDE 和编辑器文件；第一版不处理未保存缓冲区。
2. 重新读取用户权威工程，避免覆盖刚保存的修改。
3. 计算“同步基线、用户当前工程、当前 workstream”的三方差异。
4. 只选择能够明确归属当前 workstream 的修改。
5. 对所有相关源先完成 dry-run；任何冲突在写入前报告。
6. 发布前创建相关权威源组的恢复快照和 SHA-256 清单，排除确认可重建的缓存和构建产物。
7. 禁止目录镜像覆盖、`/MIR`、`--delete` 或基于时间戳盲目覆盖。
8. 路径必须位于登记的权威根内；拒绝绝对路径注入、`..` 和链接越界。
9. 逐文件应用清单中的新增或修改；删除优先移动到恢复区，不立即永久删除。
10. 发布后校验实际差异与清单一致。
11. 能安全执行时在用户工程重新构建；否则明确说明只验证了 Agent 副本。
12. 成功后更新同步基线；机械应用失败时使用恢复快照回退。

多个权威源无法形成严格的文件系统原子事务，应采用“全部预检、全部备份、逐源应用、统一校验”。

## 软隔离和代码保护

- 工作副本是强制默认架构，不能取消。
- 用户权威工程默认只读使用，所有普通开发、构建和生成操作在当前 workstream 副本内进行。
- 写文件和运行工具前解析真实路径，确认写入位置属于当前 workstream 或明确允许的工作区管理目录。
- 不使用 Full Access 作为推荐工作模式；优先使用仅允许写工作区的沙箱配置。
- 这属于软隔离和行为约束，不能承诺操作系统层面的绝对不可写。
- 不自动执行 `stash`、`reset --hard`、覆盖式 checkout、`clean -fdx`、全局格式化或其他破坏性命令。
- 修改前重新读取文件；检测到同一位置的并发变化时停止该文件修改。
- Agent 只能看到已保存到磁盘的内容；未保存缓冲区第一版不处理。

最重要的残余风险是副本过期、发布冲突、IDE 未保存内容、生成器覆盖和构建钩子写错目录，而不是普通单文件编辑。

## IDE 和生成代码

- 副本作为新工程重新导入和 Build，不复用旧对象文件、依赖文件、ELF 或普通构建缓存。
- Eclipse 系 IDE 不复制 `.metadata`，为 Agent 副本使用独立 IDE workspace。
- 重新生成的 ELF 必须对应副本路径，避免调试信息跳回用户源码。
- 初始化时识别 `.ioc`、MCC、Harmony 等生成器配置、版本和输出范围。
- 默认不重新生成代码；需要生成时只在副本执行。
- 识别 `USER CODE BEGIN/END` 等保护区，默认只修改允许的用户区域。
- 生成前建立检查点和受影响文件快照，生成后审查差异并确认用户区仍存在。
- 用户已有修改位于生成器拥有区时必须说明覆盖风险。
- 检查 `.project`、`.cproject`、`.uvprojx`、`.ewp`、链接资源、路径变量和构建脚本中的绝对路径。
- 检查 pre/post-build 是否包含外部写入、签名、版本文件修改或自动烧录。
- 外部 SDK、Pack 和工具链可以保持外部只读引用，但不得通过构建反向修改用户权威工程。

## 构建命令自动发现

用户第一次通常不需要提供构建命令。Agent 按证据优先级自行发现：

1. 项目已有构建脚本、CI、README 和编辑器任务。
2. IDE 构建日志、历史命令、Makefile、CMake preset 或 Ninja 文件。
3. IDE 工程元数据中的目标、配置和输出目录。
4. 根据工程类型和本机安装工具生成的标准 CLI 候选。
5. 无证据的启发式推断只能标为 `candidate`。

应识别的常见工程入口包括但不限于：

- `Makefile`、`CMakeLists.txt`、`CMakePresets.json`。
- `.project`、`.cproject`。
- `.uvprojx`。
- `.ewp`。
- `nbproject/`。
- `sdkconfig`、`idf_component.yml`。
- `west.yml`、Zephyr 工程特征。
- `platformio.ini`。
- Arduino CLI 相关配置。

Windows 工具发现顺序：

1. `PATH` 和 `Get-Command`。
2. 项目脚本、IDE 配置和环境初始化脚本。
3. 厂商环境变量。
4. Windows 软件安装注册信息。
5. `Program Files` 下已知厂商位置。
6. 开始菜单快捷方式的真实目标。

不递归扫描整块磁盘。工具绝对路径和易变本机信息写入 `targets.local.yaml`。

候选命令示例：

```powershell
make -C Debug -j8
cmake --build build --config Debug
UV4.exe -b Project.uvprojx -t Debug
IarBuild.exe Project.ewp -build Debug
idf.py -C Project build
west build
pio run -d Project
arduino-cli compile ...
```

Eclipse 系厂商 IDE 的 headless 参数必须依据具体版本和工程元数据生成，不能写死。

### 构建命令状态

- `candidate`：根据证据生成，但没有运行。
- `verified`：命令成功且预期 ELF、HEX 或 BIN 确实生成或更新。
- `failed`：命令能够运行，但当前工程基线失败。
- `unavailable`：缺少工具链、依赖或许可证。
- `unconfirmed`：命令存在潜在副作用，不能安全运行。

### 安全基线构建条件

- 工具存在且版本查询成功。
- 工程、目标、配置、工作目录和输出目录明确。
- 构建只在 Agent 副本内写入。
- 不需要重新生成源码。
- 已检查构建钩子，不包含烧录、擦除或未知外部写入。
- 不与正在运行的 IDE 争用同一 IDE workspace。

初始化阶段不得执行 `clean`、`rebuild`、删除构建目录、自动安装工具、转换工程系统或为了让构建通过而修改业务源码。退出码成功但产物未产生或未更新，不能标记为 `verified`。

## 验证策略

使用“验证能力清单 + 最小充分验证”，不强制完整分层闭环。

| 验证能力 | 使用条件 |
| --- | --- |
| 构建 | CLI 工具链、许可证、依赖和配置可用 |
| 软件测试 | 项目已有测试入口，或逻辑可以脱离硬件运行 |
| 仿真 | 模拟器支持对应 MCU、板卡和相关外设 |
| 板级验证 | 板卡、探针、驱动、供电和端口映射明确 |
| HIL | 另有可控电源、仪器、夹具和自动断言接口 |

初始化阶段：

- 识别现有验证入口。
- 条件满足时验证一次普通构建。
- 不主动增加测试框架、模拟器或 HIL 系统。

日常规则：

- 修改源码后通常执行已验证的构建命令。
- 现有软件测试与改动相关时才运行。
- 现有模拟器确实覆盖当前行为时才运行。
- 行为依赖真实外设、电气、时序或多板通信时说明需要板级验证。
- 明确区分“构建通过”“软件行为通过”和“实物硬件通过”。

最终验证报告保持简短，例如：

```text
验证：MotorController Debug 构建通过；无现成软件测试；未进行板级验证。
```

## 硬件风险规则

- 初始化 Skill 不执行硬件操作。
- 用户已经明确要求烧录或调试指定目标后，不反复询问普通烧录、复位和串口操作。
- 探针或串口被占用时不强行抢占。
- 电机或高功率输出首次动作前提醒一次，本轮不重复。
- OTP、eFuse、永久读保护、不可逆锁定、Option Bytes、Bootloader 区和包含重要数据的全片擦除，每次必须确认。
- 不创建硬件资源锁、租约文件或后台协调服务。

## 敏感文件和复制策略

本节规则适用于把用户工程或外部参考导入 Agent 工作区的 `agent-import`，不适用于纯净模式迁移前的 `recovery-backup`。恢复备份按前述要求尽量原样保存，导入副本才执行以下过滤：

- 默认不复制 `.git` 元数据、IDE workspace 元数据、可重建缓存和普通构建产物。
- 确定性识别的私钥、令牌、凭据、生产签名文件、许可证文件和设备转储只列出，不复制。
- 高熵检测只产生警告，不能据此排除所有二进制，因为预编译库和固件可能天然高熵。
- 构建需要的秘密优先通过环境变量或外部只读路径引用。
- 明确允许复制的敏感文件不得进入 Agent 私有 Git。
- 预编译库、固件 blob、启动文件和链接脚本不能按扩展名笼统排除。
- 符号链接、junction 和外部 SDK 必须解析真实目标；不能默默展开为大目录或形成对用户工程的写回路径。
- 复制过程中检测源文件是否变化；变化时重试或报告快照不一致。

## 参考工程目录

管理根目录必须提供：

```text
reference-projects/
|-- README.md
`-- <reference-id>/
    |-- README.md
    `-- project/
```

用途和边界：

- 用于存放用户提供、从外部路径导入或从公开仓库取得的参考工程快照。
- 每个参考工程使用稳定、简短的 `reference-id`。
- `<reference-id>/README.md` 至少记录来源、获取日期、版本或提交、参考用途、适用目标、许可证、已知差异和是否经过构建验证。
- `project/` 保持参考工程自身目录结构；包装层 README 不覆盖项目原有 README。
- `reference-projects/README.md` 维护简短索引，帮助 Agent 只读取与当前任务有关的参考工程，禁止默认加载全部参考代码。
- 参考工程默认只读，不直接修改、不创建 workstream 分支、不进入 Agent 到用户工程的同步或发布流程。
- Agent 不得把参考工程自动识别为 MCU 开发目标或权威源，即使其中存在 `.ioc`、`.uvprojx`、`.ewp`、Makefile 等工程标志。
- 需要试改、构建或验证参考工程时，将所需快照复制到 `<managed_root>/work/<workstream-id>/reference-copies/<reference-id>/project/`；在其外层创建 `README.md` 记录来源快照、快照哈希或版本、用途、创建时间、所属 workstream、构建状态和清理条件，不得覆盖参考工程自带说明或污染原参考快照。
- 每个可修改的参考工程副本自动建立独立 Agent 私有 Git 和导入基线，不纳入用户工程发布、不推送；只有对应 workstream 已完成且不存在未保留成果时才可以清理。
- 需要将参考工程正式转为开发工程时，必须由用户明确表达提升意图，再按新权威源或新 Agent 工程完成登记、敏感检查和私有 Git 基线。
- 导入参考工程时沿用敏感文件过滤规则，默认排除 `.git` 元数据、可重建缓存、构建产物和本机状态；保留并记录 LICENSE、NOTICE、版权说明、启动文件、链接脚本及必要预编译库。
- 公共仓库参考应记录精确提交或版本，避免仅记录可能变化的分支名。
- 引用或移植参考代码时，在当前 workstream 记录来源和适用许可证，不因“仅供参考”忽略授权条件。

用户手工放入 `reference-projects/` 的新内容在下一次 Agent 任务中进行轻量识别；无法确认包装边界、来源或敏感内容时先登记为待整理项，不擅自移动或重写。

## 持久项目知识和开发路径

跨 workstream 长期有效的产品定义、方案结论和开发路线统一进入 `project-docs/`，不把聊天流水或尚未确认的讨论直接当成项目事实。

```text
project-docs/
|-- README.md
|-- PRODUCT.md
|-- SOLUTION.md
|-- ROADMAP.md
|-- decisions/
|   `-- README.md
`-- versions/
    `-- README.md
```

职责边界：

- `project-docs/README.md` 提供当前阶段、权威文档入口和下一项关键决策的一屏索引。
- `PRODUCT.md` 记录最终产品目标、用户、使用场景和长期能力边界，不混入某一开发版本的暂时限制。
- `SOLUTION.md` 记录当前有效的统一方案、系统划分和关键约束，不保留已经失效的方案正文。
- `ROADMAP.md` 记录开发阶段、依赖顺序、当前状态和下一步；每个阶段至少包含目标、依赖、范围和退出条件。
- `decisions/YYYY-MM-DD-topic.md` 记录跨任务的重要选择、备选方案、取舍、证据、状态及来源 workstream。
- `versions/V<序号>-topic.md` 记录该版本目标、包含范围、明确不包含、完成标准和验证要求。

信息流转规则：

- 进行中的方案讨论、候选结论和任务证据先记录在 `work/<workstream-id>/README.md`。
- 普通 Agent 不得因一次讨论自动修改 `PRODUCT.md`、`SOLUTION.md` 或 `ROADMAP.md` 中的项目事实。
- 用户确认跨任务有效的结论后，才将其提升到 `SOLUTION.md` 或独立 decision；来源 workstream 和确认日期必须可追溯。
- 与旧结论冲突时，将旧 decision 标记为 `已替代` 并指向新 decision，不静默删除历史。
- 统一使用 `待确认`、`已确认`、`已推迟`、`已替代` 四种方案状态。
- Git 是项目演进的时间线；workstream 和项目文档不重复抄写完整变更历史。
- Markdown 是项目知识的单一事实源；XMind、图表和其他可视化只作为可选派生视图，不强制多份文档同步维护。
- `PRODUCT.md`、`SOLUTION.md`、`ROADMAP.md` 仅在能够填入真实内容时创建，不生成空正文占位文件。
- `decisions/` 和 `versions/` 的说明目录在首次需要相应内容时创建，避免空层级泛滥。

出现多个目标间的稳定通信协议时，可以按需增加 `project-docs/interfaces/`；验证矩阵变复杂时可以按需增加 `project-docs/verification/`。这些是项目发展后再启用的能力，不是每个工作区的固定空目录。

阶段成果归档保持可选。只有用户明确要求且阶段退出条件已经验证时，才生成不可覆盖旧版本的自包含快照；归档位置和独立 Git 策略在实际需要时另行登记，不作为第一版初始化的强制内容。

## 工作区根目录和分类

三个入口文档始终位于实际 Codex 工作区根目录，保证启动任务时能够发现规则和用户说明：

```text
AGENTS.md
README.md
USER_GUIDE.md
```

其余分类相对于 `managed_root`；纯净模式的 `managed_root` 是工作区根目录，兼容模式则是 `agent-workspace/`：

```text
project-docs/
`-- README.md
reference-projects/
|-- README.md
`-- <reference-id>/
    |-- README.md
    `-- project/
sources/
|-- README.md
`-- <source-id>/
    |-- README.md
    `-- integration/
work/
|-- README.md
`-- <workstream-id>/
    |-- README.md
    |-- <source-id>/
    |-- reference-copies/
    |   |-- README.md
    |   `-- <reference-id>/
    |       |-- README.md
    |       `-- project/
    |-- tools/
    |   `-- README.md
    `-- artifacts/
        `-- README.md
workspace-management/
|-- README.md
|-- config/
|   |-- README.md
|   |-- workspace.yaml
|   |-- targets.yaml
|   `-- targets.local.yaml
|-- tools/
|   `-- README.md
|-- templates/
|   |-- README.md
|   `-- project-docs/
|       `-- README.md
|-- sync-state/
|   `-- README.md
|-- recovery/
|   `-- README.md
|-- migration/
|   |-- README.md
|   `-- initialization-report.md
|-- history/
|   `-- README.md
`-- ide-workspaces/
    `-- README.md
```

规则：

- 纯净模式的工作区根目录只允许三个入口文档和一级分类目录。
- 兼容模式保留根目录原有用户工程和必要文件；Agent 新产物必须进入 `agent-workspace/`，不得继续散落在根目录。
- 项目级长期事实进入 `project-docs/`，不与单个 workstream 的过程状态混写。
- 参考工程只进入 `reference-projects/<reference-id>/project/`，不得混入 `sources/` 或正式 workstream 工程。
- 正式源码保留在当前 workstream 内对应工程的原有位置。
- 参考工程的试改或构建副本进入 `<managed_root>/work/<workstream-id>/reference-copies/<reference-id>/project/`。
- 一次性任务脚本进入 `work/<workstream-id>/tools/`。
- 可复用工作区工具进入 `workspace-management/tools/<purpose>/`。
- 后续普通 Agent 需要的本地模板进入 `workspace-management/templates/`；不得依赖初始化 Skill 安装目录中的隐藏资源。
- 分析报告、日志摘要和导出物进入当前 workstream 的 `artifacts/`。
- 同步状态进入 `workspace-management/sync-state/`。
- 恢复快照进入 `workspace-management/recovery/<workstream-id>/`。
- IDE 独立 workspace 元数据进入 `workspace-management/ide-workspaces/`，不与用户 IDE workspace 混用。
- 每个职责边界目录必须包含 `README.md`，说明用途、所有权、Git 状态和清理规则。
- 不要求 MCU 工程内部每个源码子目录都创建说明文件。
- IDE 或构建系统强制位于工程根目录的文件和输出路径属于例外，不能为了分类破坏工程。
- Agent 不得把脚本、日志、下载文件、测试产物或临时文件直接放在工作区根目录。

### 运行期工具与模板

初始化完成后，将日常任务需要的确定性脚本部署到 `<managed_root>/workspace-management/tools/`：

- `detect-targets.ps1`：轻量发现新增或变化的 MCU 工程。
- `import-sources.ps1`：从用户权威工程导入已保存变化并维护同步基线。
- `import-reference.ps1`：导入只读参考工程及其来源信息。
- `create-reference-copy.ps1`：创建带独立私有 Git 基线的任务参考副本。
- `new-workstream.ps1`：创建或复用 workstream、分支和 worktree。
- `publish-workstream.ps1`：执行三方预检、备份和受控发布。

`init-workspace.ps1`、`plan-migration.ps1`、`backup-workspace.ps1`、`apply-migration.ps1` 和 `refresh-workspace.ps1` 仅由显式初始化 Skill 使用，不复制成普通任务可随意调用的日常入口。

`<managed_root>/workspace-management/templates/project-docs/` 保存 PRODUCT、SOLUTION、ROADMAP、decision 和 version 的本地格式说明或模板，使没有日常开发 Skill 的普通 Agent 也能按一致格式创建后续文档。模板只定义职责和必要字段，不包含虚构项目内容。

## 配置建议

### `workspace.yaml`

保存工作区格式和策略版本，用于幂等刷新与受控迁移：

```yaml
workspace_schema: 1
policy_version: 1
layout_mode: pure
managed_root: .
initializer: embedded-workspace-init
initialized_at: 2026-09-07T00:00:00+08:00
migration:
  last_backup_id: null
  last_notified_backup_id: null
```

- `workspace_schema` 表示目录和配置数据结构版本。
- `policy_version` 表示 Agent 行为规则版本。
- `layout_mode` 只能为 `pure` 或 `compatibility`。
- `managed_root` 必须与布局模式一致，不从目录外观盲目推断。
- `last_backup_id` 记录最近创建的迁移备份，`last_notified_backup_id` 记录已经向用户提示过的备份；两者不相等时显示一次处置提醒。
- Skill 自身升级不会自动迁移已有工作区；只有显式刷新并确认具体计划后才改变结构或策略版本。

### `targets.yaml`

只保存可移植、可共享的工程事实，不保存绝对本机路径或秘密。

```yaml
schema: 1

targets:
  motor-controller:
    source: motor-product
    path: firmware/motor-controller
    mcu: STM32G0B1CBT6

    project:
      type: stm32cubeide
      entry: .project
      generator: motor.ioc

    build:
      cwd: firmware/motor-controller
      configuration: Debug
      command: make -C Debug -j8
      status: verified
      outputs:
        - Debug/motor-controller.elf
        - Debug/motor-controller.hex

    generated:
      policy: edit-user-sections-only
      config:
        - motor.ioc

    verification:
      test_command: null
      simulator_command: null

    hardware:
      warnings:
        - motor
```

字段可信状态应区分：

- `detected`：从文件或环境识别。
- `confirmed`：由用户确认。
- `verified`：实际执行并取得证据。

未知信息省略或使用 `null`，不能猜测。

### `targets.local.yaml`

保存本机易变信息，并加入 Agent 私有 Git 忽略：

```yaml
sources:
  motor-product:
    source_paths:
      - D:/Projects/MotorController
    integration_path: sources/motor-product/integration
    write_policy: explicit-publish-only
    sync_strategy: three-way

tools:
  cubeide: C:/Tools/STM32CubeIDE/stm32cubeide.exe

hardware:
  motor-controller:
    probe: st-link
    probe_serial: null
    serial_port: null
```

不得在其中存放密钥。

动态文件哈希和同步基线写入 `workspace-management/sync-state/`，不要频繁改写人工配置。

## 根目录文档职责

### `AGENTS.md`

供后续 Agent 自动读取，保持短而明确。至少约束：

- 读取目标和本机配置。
- 按当前任务需要读取参考工程索引和相关参考项目，不默认遍历全部参考工程。
- 参考工程原快照保持只读，试改和构建只能在 `<managed_root>/work/<workstream-id>/reference-copies/` 中进行。
- 读取 `project-docs/` 中与当前任务有关的产品边界、当前方案和开发路径；未确认的 workstream 结论不得自动提升为项目事实。
- 任务开始执行轻量目标与源变化检测。
- 新 MCU 工程自动登记并纳入 Agent 私有 Git。
- 用户工程默认只读，普通写入只发生在 workstream 副本。
- 创建或复用 workstream，检查其他活动任务的范围。
- 优先使用已验证构建命令并执行最小充分验证。
- 保护 IDE 生成代码和用户已有修改。
- 分类存放所有新文件。
- 更新 workstream 状态。
- 发布必须识别明确的 Agent 到用户工程意图并执行三方检查和备份。
- 用户工程 Git 提交只在明确要求时执行。
- 普通任务不得自行修改受管策略、目录模式和迁移工具；发现不适配时只提出调整方案。
- 使用初始化 Skill 更新已有约束时，展示计划后必须停止；用户确认前连日常事实登记也不得写入。

### 根 `README.md`

提供一屏可读的工作区概览、核心目录入口和当前管理状态，不复制完整使用手册。

### `USER_GUIDE.md`

初始化后必须在根目录生成 UTF-8 中文用户手册，面向用户而非 Agent。内容至少包括：

1. 60 秒快速开始。
2. 用户权威工程、集成副本和 workstream 的区别。
3. 自动执行事项和需要用户明确表达的事项。
4. 用户 Git 与 Agent 私有 Git 的区别。
5. 导入和发布的方向及自然语言示例。
6. 多 MCU、多权威源和多对话并行的使用方式。
7. `reference-projects/` 只读快照与 `<managed_root>/work/<workstream-id>/reference-copies/` 任务副本的区别、实际位置、私有 Git 和清理条件；同时说明纯净模式 `managed_root=.`、兼容模式 `managed_root=agent-workspace`。
8. 产品定义、方案记录、开发路线、决策和版本资料分别存放在哪里。
9. 如何对已有工作区执行纯净迁移或兼容初始化。
10. 工作区规则如何提出升级计划、等待一次确认、验证、记录和回滚。
11. 外部初始化备份的用途、恢复方式、禁止作为 Codex 工作区或构建源的规则。
12. 工作区目录说明。
13. 构建失败、同步冲突和恢复方法。
14. 未保存缓冲区、软隔离和板卡共享等已知边界。

常用自然语言示例：

```text
把我的工程最新修改导入 Agent 工作区。
将工作区中的 Agent 工程同步到我的工程中。
重新扫描并登记新增 MCU 工程。
构建 motor-controller。
查看当前正在进行的任务。
继续之前的电机堵转保护任务。
为用户工程启用 Git。
恢复同步前的工程副本。
将 <path-or-url> 添加为参考工程。
参考 <reference-id> 分析当前驱动，但不要修改参考工程。
把 <reference-id> 复制到当前任务中供试改和构建。
将 <reference-id> 提升为正式开发工程并登记为新的权威源或 Agent 工程。
更新已有工作区约束，先只展示迁移计划。
```

这些是示例，不是固定口令。

用户手册仅在以下情况下自动更新：

- 首次初始化。
- 工作区一级目录结构发生变化。
- 同步、Git、并行或恢复规则发生变化。
- 经用户确认的 Skill 升级或策略迁移改变用户使用方式。

新增普通目标、构建命令或 workstream 时不重写整份手册；当前事实以配置文件为准，避免重复信息过期。

## 受控进化和规则升级

工作区可以随项目推进持续适配，但必须区分“项目事实”和“管理策略”。

### 正常任务中的事实更新

完成初始化且当前没有待确认的约束迁移时，普通 Agent 可以幂等更新：

- 新源组、MCU 目标和稳定 ID。
- 工具链位置、候选构建命令及其验证状态。
- 参考工程索引和 workstream 当前状态。
- 用户已保存内容与 Agent 副本之间的同步事实。

这些更新不得改变 `AGENTS.md` 核心规则、布局模式、同步策略、Git 策略、安全门槛或迁移工具。普通 Agent 发现现有规则反复不适配时，只在回复或当前 workstream 中说明问题并提出候选方案，不自行“优化”约束。

### 项目知识进化

- 新结论先留在 workstream，只有用户确认其跨任务有效后才提升到 `project-docs/`。
- 新增 MCU 或工具链不自动改变产品目标和开发阶段。
- 阶段切换必须满足已记录的退出条件，并由用户确认；完成状态不能仅凭 Agent 推断。
- 多目标出现稳定通信关系时可以提议增加接口文档；验证需求实际变复杂时可以提议增加验证矩阵。
- 旧决策被替代时保留可追溯关系，不直接改写成仿佛旧方案从未存在。

### 使用 Skill 更新已有工作区约束

显式调用 `$embedded-workspace-init` 更新规则、结构或策略时，采用严格的两阶段事务。

确认前只能执行只读审计和 dry-run，并在对话中展示：

- 当前和目标 `workspace_schema`、`policy_version`。
- 将创建、修改、移动或保留的文件和目录。
- 布局模式、源组、复制映射、排除项和 Git 边界变化。
- 对现有 workstream、项目文档、构建与同步的影响。
- 执行前备份、应用后验证和失败回滚方法。

展示具体计划后必须停止并等待用户明确确认。确认前不得：

- 创建或修改任何工作区文件、目录、备份或 Git 检查点。
- 更新 `targets.yaml`、构建状态、参考工程索引或 workstream。
- 改变版本号、写迁移历史或运行会产生输出的构建。
- 将正常任务中的自动事实更新夹带进本次升级操作。

用户未回应、明确拒绝或取消时，本次更新以零写入结束。用户只确认部分内容时，先生成删减后的新计划并再次等待确认，不能自行实施部分迁移。

用户确认完整计划后：

1. 重新读取当前状态；若相对计划发生实质变化，重新展示计划并再次确认。
2. 创建 Agent 私有 Git 检查点和管理文件快照。
3. 只修改 `AGENTS.md` 的受管区域并执行幂等结构或配置迁移，保留用户自定义区域、稳定 ID、人工字段、已有副本和未提交改动。
4. 验证 YAML、路径引用、关键规则、检测脚本、工作副本、私有 Git 和分类结构；能安全构建时再执行基线构建。
5. 成功后更新版本、必要的 `USER_GUIDE.md`，并在 `workspace-management/history/YYYY-MM-DD-policy-vN-to-vM.md` 记录原因、计划、批准、差异、验证和回滚方法。
6. 验证失败时恢复管理文件和结构、验证回滚结果，并记录失败及已回滚的迁移尝试；不得触碰用户业务源码或隐式发布到用户工程。

根 `AGENTS.md` 应使用清晰的受管区标记和用户自定义区。规则迁移只替换受管区，不整文件覆盖。更新后的指令从下一次任务或重新打开工作区开始使用最可靠。

## 无日常开发 Skill 时的运行方式

短期内不需要另建日常开发 Skill。职责关系为：

```text
$embedded-workspace-init
    -> 部署规则、配置、工作副本和确定性脚本

根 AGENTS.md
    -> 约束后续任务

普通 Agent
    -> 按规则开发、构建、验证、交接和按需发布
```

只有从该项目作用域启动且支持 `AGENTS.md` 的 Agent 才能自动遵守这些规则。其他 IDE 插件或工具不一定遵守。未来只有出现稳定、频繁且仅靠 `AGENTS.md` 难以完成的日常工作流时，才考虑创建日常开发 Skill。

## 实际 Skill 建议结构

```text
embedded-workspace-init/
|-- SKILL.md
|-- agents/
|   `-- openai.yaml
|-- assets/
|   |-- AGENTS.md
|   |-- README.md
|   |-- USER_GUIDE.md
|   |-- directory-README.md
|   |-- backup-AGENTS.override.md
|   |-- backup-README.md
|   |-- initialization-report.md
|   |-- project-docs-README.md
|   |-- product.md
|   |-- solution.md
|   |-- roadmap.md
|   |-- decision.md
|   |-- version.md
|   |-- reference-project-README.md
|   |-- reference-copy-README.md
|   |-- workstream-README.md
|   |-- workspace.yaml
|   `-- targets.yaml
|-- references/
|   |-- source-and-target-detection.md
|   |-- build-discovery.md
|   |-- existing-workspace-migration.md
|   |-- project-knowledge.md
|   |-- reference-projects.md
|   |-- synchronization.md
|   |-- controlled-evolution.md
|   `-- configuration-schema.md
`-- scripts/
    |-- init-workspace.ps1
    |-- plan-migration.ps1
    |-- backup-workspace.ps1
    |-- apply-migration.ps1
    |-- refresh-workspace.ps1
    |-- detect-targets.ps1
    |-- import-reference.ps1
    |-- create-reference-copy.ps1
    |-- import-sources.ps1
    |-- new-workstream.ps1
    `-- publish-workstream.ps1
```

- `SKILL.md` 只保留触发边界、初始化路由和关键安全约束。
- 大段条件规则进入按需读取的 references。
- 稳定生成内容放入 assets。
- 目录创建、哈希、复制、Git 基线、差异检测和发布预检使用确定性脚本。
- 备份包装文件、分类映射、迁移计划和规则版本由脚本生成并验证，避免依靠临时自然语言操作。
- `initialization-report.md` 可以从模板生成；实际路径、清单哈希和结果必须由脚本填入，不能保留占位值。
- 不为目录完整而创建没有实际用途的占位资源。

## 验收场景

实际 Skill 创建后至少验证：

1. 空工作区能初始化完整结构和三份根目录文档。
2. 已开发到一半且有未提交文件的工程能无损导入。
3. 单 MCU 与多 MCU 使用同一套源组和目标模型。
4. 分散权威源能够分别镜像，存在共享相对路径时保持原拓扑。
5. 用户工程有 Git 时不会自动提交或推送。
6. 用户工程无 Git 时会询问；同意、拒绝和无回应分别进入正确状态。
7. 每个源组都自动拥有 Agent 私有 Git 和导入基线。
8. 后续新增 MCU 工程能够自动登记并纳入私有 Git，不产生错误嵌套仓库。
9. 重复扫描不会重复目标、重写确认字段或创建空提交。
10. 能从工程和本机环境发现候选构建命令。
11. 只有实际成功并生成预期产物的命令才标为 `verified`。
12. 复制来的缓存不参与基线构建，独立 IDE workspace 可用。
13. 多个 workstream 可以在独立 worktree 并行修改和构建。
14. 活动 workstream 范围重叠时能够检测并提示。
15. 用户改变、Agent 未改变时可以安全导入。
16. 用户与 Agent 修改同一位置时不会自动覆盖任何一方。
17. 所有 Agent 到用户工程的等价发布表达触发同一受控流程。
18. 发布前执行三方比较、dry-run、恢复快照和路径检查。
19. 发布不会使用整目录镜像覆盖，删除可以恢复。
20. 疑似敏感文件不会自动复制或进入 Agent 私有 Git。
21. 脚本、日志、下载和测试产物不会出现在根目录。
22. 分类目录均有准确的 `README.md`。
23. `USER_GUIDE.md` 能让用户在不了解内部脚本的情况下完成日常流程。
24. 没有日常开发 Skill 时，普通 Agent 仍能按根 `AGENTS.md` 工作。
25. 初始化不会修改业务源码、烧录硬件或修复基线错误。
26. 非空工作区迁移在用户确认具体方案前保持零写入，不创建备份、目录、Git 或状态记录。
27. 所有用户权威工程位于工作区外时默认选择纯净模式，并使用 `managed_root: .`。
28. 用户权威工程位于当前工作区内时选择兼容模式，保留原路径并使用 `managed_root: agent-workspace`。
29. 模式判断存在路径或链接歧义时不会自行选择或开始迁移。
30. 纯净模式迁移先在工作区外建立并验证完整备份，再从快照分类重建。
31. 备份根包含人类说明、Agent 覆盖规则和机器标记，且不会被扫描、构建、登记或同步。
32. 初始化后只提醒一次备份位置和人工处置责任，Skill 永不自动删除备份。
33. 当前工作区包含用户工程时，不会递归复制新建的 `agent-workspace/` 管理目录。
34. 已有目录名与预定分类冲突时不会被自动认领或覆盖。
35. 参考工程能够按独立包装目录导入，并保留来源、版本、许可证和用途说明。
36. 参考工程不会被自动登记为目标、源组或发布对象。
37. 试改或构建参考工程时使用 `reference-copies/<reference-id>/project/`，原参考快照保持不变。
38. Agent 只按任务需要读取相关参考工程，不因参考目录增大而加载全部内容。
39. 产品定义、当前方案、开发路线、重要决策和版本边界能够进入职责明确的 `project-docs/`。
40. 未确认的 workstream 结论不会自动成为项目事实；确认后的结论保留来源和状态。
41. 新决策替代旧决策时保留 `已替代` 关系，Git 继续承担演进时间线。
42. 约束升级只展示只读计划；用户未回应、拒绝或取消时整个操作零写入结束。
43. 升级计划发生实质变化或只获得部分确认时不会执行旧计划或自行部分迁移。
44. 确认后的迁移具有检查点、验证、历史记录和失败回滚，并且不会隐式发布用户工程。
45. `AGENTS.md` 规则升级只替换受管区，不覆盖用户自定义区。
46. 日常事实自动更新只发生在独立的正常任务中，不会夹带进待确认的约束升级。
47. 已初始化工作区重新扫描时沿用 `workspace.yaml` 的模式，现状不匹配只产生迁移建议。
48. 仅刷新事实的重新扫描可以幂等执行；同一次调用包含策略或结构迁移时整体进入零写入计划模式。
49. `recovery-backup` 原样保存 `.git`、敏感内容和本机状态，`agent-import` 才执行过滤，两套复制策略不会混用。
50. 每份迁移备份都有唯一 ID，并通过 `last_notified_backup_id` 保证每份只提醒一次。
51. 兼容模式的初始化写入只限确认计划中的根管理文档，不会修改、移动或重命名业务工程文件。
52. `USER_GUIDE.md` 能根据布局模式展示参考快照和任务参考副本的真实路径。
53. 每个任务参考副本具有来源说明、独立私有 Git 基线和清理条件，且不会参与用户工程发布。
54. 没有日常开发 Skill 时，普通 Agent 仍能在工作区内找到所需运行期脚本和项目文档模板。
55. 没有真实内容时不会生成空的 PRODUCT、SOLUTION 或 ROADMAP 正文。

## 已明确删除或暂缓的设计

- 不使用专用账户、ACL、虚拟机或独立高权限 Publisher 做强隔离。
- 不承诺 Agent 在技术上绝对无法写用户工程。
- 不实现硬件资源锁；只在资源占用时不抢占。
- 不处理编辑器未保存缓冲区；发布前只提醒保存一次。
- 不强制完整分层测试闭环。
- 不创建专用 Git 提交 Skill。
- 不创建日常开发 Skill，等实际重复需求出现后再决定。
- 不使用固定同步口令。
- 不进行后台实时监控。

## 成功标准

- Skill 仅在用户显式调用时初始化或刷新工作区。
- 用户无需改变原有 MCU、IDE、编辑器或目录组织方式。
- 用户日常交互可以压缩为“提出任务、Agent 在副本工作、明确要求时发布”。
- 用户工程、Agent 私有 Git、workstream 和同步方向始终不会在文档或实现中混淆。
- 多权威源、多 MCU 和多对话并行均能被同一模型表达。
- 已有工作区可以无损增量接入；参考工程与权威源、集成副本和 workstream 的职责始终清晰分离。
- 未确认的已有工作区迁移或约束升级不会产生任何写入；确认后的变化可验证、可审计、可回滚。
- 复杂机械操作由已验证脚本完成，规则文档保持精简。
- 发生冲突时停止覆盖；发生可恢复故障时存在基线或快照。
- 所有事实性成功声明都有对应验证证据。
- 实际 Skill 使用 `quick_validate.py` 通过结构与元数据检查。
