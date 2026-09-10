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
- 用户权威工程与纯净 Agent 工作区始终位于两个互不包含的真实目录中。
- Agent 默认只读用户权威工程，在工作区受管副本中开发、构建和验证。
- 不要求用户工程采用固定源码结构，也不重组 IDE 生成的工程。
- 多个对话可以通过独立 workstream 并行工作。
- 后续出现新 MCU 工程时自动登记并纳入对应源组私有 Git。
- Agent 与用户工程通过用户同步基线进行三方比较，仅在用户明确表达发布意图时写回。
- 普通 Agent 即使没有专门的日常开发 Skill，也能通过根 `AGENTS.md` 正常工作。
- 工作区提供独立的参考工程目录，供 Agent 按需查阅和比较，但不参与用户工程同步。
- 工作区提供持久项目知识层，区分产品定义、当前方案、开发路径、版本边界和任务过程。
- 已初始化工作区能够受控进化：项目事实自动适配，规则和结构只在用户确认具体计划后迁移。
- 工作区根目录保持整洁，所有工具、脚本、日志和其他产物分类存放并具有说明。
- 工作区使用 Agent 管理 Git、源组私有 Git 和可选的用户工程 Git 分离管理不同内容。
- 根目录生成面向用户的中文使用手册，隐藏内部复杂度。

## 不做的事情

- 不规定 `bsp/`、`drivers/`、`middleware/`、`app/` 等源码布局。
- 不将现有工程转换为 CMake、PlatformIO 或其他构建体系。
- 不为了统一管理而移动、重命名或重组用户工程。
- 不在用户权威工程内部建立 Agent 工作区，也不提供兼容模式。
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

用户日常使用 IDE 和其他编辑器维护的原始工程。它始终位于纯净 Agent 工作区之外，可以包含一个或多个分散路径。Agent 默认只读，只有明确的发布流程，或用户另行确认的用户 Git 初始化流程，才可以写入。

### 权威源组

需要保持相对路径、共享代码或共同生成配置的一组用户工程路径。每个源组使用稳定的 `source-id`。

### 目标

一个可识别、构建或验证的 MCU 工程，使用稳定且人类可读的 `target-id`。一个源组可以包含多个目标；相同 MCU 型号也可以有多个目标。

### 集成副本

`sources/<source-id>/integration/` 中的 Agent 受管副本。它保持用户源组必要的目录拓扑，并由源组私有 Git 管理。

### Workstream

一个逻辑开发任务及其独立工作副本，位于 `work/<workstream-id>/`。一个 workstream 可以同时涉及多个目标、模块和源组；对话绑定仅用于辅助续接，不作为识别 workstream 的硬依赖。

### 用户同步基线

用户权威工程与源组私有 Git 中最后一次内容一致的完整受管状态，由可取回内容的不可变提交表示。它用于比较“用户同步基线、用户当前工程、Agent 当前 workstream”并检测冲突，与构建是否成功无关。

### Workstream Git 基线

- `user_baseline_commit`：当前 workstream 用于三方比较的用户同步基线。
- `task_base_commit`：workstream 分支实际创建点，可以包含已声明的其他 workstream 依赖。
- `head_commit`：发布前冻结的当前 workstream 状态。

发布范围由 `task_base_commit` 到 `head_commit` 的差异和显式依赖闭包确定；三方冲突判断使用 `user_baseline_commit` 中的用户内容。

### 构建基线

每个目标和构建配置最近一次实际构建成功的提交和证据，记录在 `build_baselines` 中。没有成功构建过时对应值为 `null`。构建基线只说明验证状态，不能代替用户同步基线，也不能决定三方同步是否可用。

### 参考工程

放在 `reference-projects/` 中、仅供阅读、比较和借鉴的工程快照。参考工程不是用户权威工程、受管源组、构建目标或发布对象，Agent 不在其中直接开发。

### 管理根目录

独立纯净 Agent 工作区的根目录，也是 Codex 日常任务唯一允许打开的项目入口。固定记录为 `layout_mode: pure` 和 `managed_root: .`。

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
$embedded-workspace-init 检查当前已有工程并制定外部纯净 Agent 工作区初始化方案；确认前不要修改任何内容。
```

添加参考工程示例：

```text
$embedded-workspace-init 将 <path-or-url> 导入为参考工程，仅供 Agent 查阅，不作为开发或发布目标。
```

## 强制纯净布局与迁移

同一个 Skill 支持首次初始化、中途初始化、重新扫描和受控升级，但只支持独立的纯净 Agent 工作区：

```yaml
layout_mode: pure
managed_root: .
```

初始化前解析 Agent 工作区、所有用户源路径、符号链接和 junction 的真实路径，并强制满足：

- Agent 工作区不能位于任何用户权威工程内部。
- 用户权威工程不能位于 Agent 工作区内部。
- 二者不能通过符号链接、junction 或路径映射形成直接或间接包含关系。
- 用户权威工程不能直接充当 `sources/<source-id>/integration/`。
- Codex 日常任务必须打开纯净 Agent 工作区根目录，不能直接把用户工程、`integration/` 或 linked worktree 添加为 Codex 项目。

任何一项无法证明满足时，只报告解析结果并停止，不创建目录、配置、Git、备份或构建输出。

### 初始化路由

- 当前目录是全新空目录：用户明确调用初始化后可以直接建立纯净 Agent 工作区。
- 当前目录是已有效初始化的纯净 Agent 工作区：沿用 `workspace.yaml`，只执行请求范围内的幂等刷新或受控升级。
- 当前目录是非空且未初始化的候选 Agent 工作区或旧 Agent 工作区：先只读盘点并展示迁移计划，确认前零写入。
- 当前目录是用户权威工程或包含任一用户权威路径：不得在其中创建 Agent 管理子目录；只读盘点后建议一个外部空目录作为新的纯净 Agent 工作区，展示路径和完整计划并等待确认。

建议的外部路径只是计划的一部分，不能自行假定固定盘符或父目录。目标目录必须是全新空目录，或已经由本 Skill 有效初始化的纯净 Agent 工作区；其他非空目录只能先进入迁移计划流程。

为当前用户工程建立外部 Agent 工作区时：

1. 只读盘点用户工程和候选 Agent 工作区。
2. 展示外部 Agent 工作区路径、源组、可逆映射、过滤项、三套 Git 边界、验证和回滚方法，然后停止等待用户确认。
3. 用户确认完整计划后重新检查状态；发生实质变化时更新计划并再次确认。
4. 在外部空目录创建纯净 Agent 工作区，将用户已保存内容导入各源组集成副本。
5. 创建 Agent 管理 Git、源组私有 Git、用户同步基线及必要配置。
6. 验证副本、映射、Git 边界、配置和安全构建入口，并确认用户工程没有因布局初始化被修改。
7. 要求用户以后从新的纯净 Agent 工作区根目录启动 Codex 任务。

布局初始化不得在用户权威工程中新增 `AGENTS.md`、`README.md`、`USER_GUIDE.md`、`.gitignore`、Agent 副本或其他管理文件。用户另行确认“为用户工程启用 Git”时，才允许通过独立的用户 Git 流程创建 `.git` 和必要 `.gitignore`，不得把这项写入夹带进布局初始化。

### 非空 Agent 工作区迁移

非空候选或旧 Agent 工作区采用“外部完整快照、分类重建、验证后启用”：

1. 只读盘点现有文件、目录、Git、未提交状态、工程入口、链接和说明文件。
2. 展示预计备份位置、分类映射、排除项、Git 边界、将创建、移动、归档或保留的内容、验证和回滚方法，然后停止等待用户确认。
3. 用户未回应、拒绝或取消时零写入结束；只确认部分内容时先生成新计划，不自行实施部分迁移。
4. 用户确认完整计划后重新检查当前状态；发生实质变化时更新计划并再次确认。
5. 提醒用户保存相关编辑器内容，并在迁移期间暂停写入当前 Agent 工作区。
6. 在当前工作区之外创建完整恢复备份，保留原目录结构并生成文件数量、大小和 SHA-256 清单。
7. 在同级临时目录建立新的标准结构，从已验证备份按明确分类映射复制内容。
8. 无法可靠分类的内容进入迁移待确认清单，不擅自删除、改名或归类。
9. 检查文件清单、Git 边界、相对路径、敏感内容、工程识别和可用构建入口。
10. 验证通过后启用新结构，并要求重新打开工作区以加载唯一的根规则。
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
- `snapshot/` 使用 `recovery-backup` 复制策略，尽量原样保存现有内容，包括 `.git`、敏感文件、缓存和本机状态；它不应用 Agent 导入时的过滤规则，也不得进入任何 Agent Git。
- 备份不跟随符号链接或 junction 展开外部目录，而是在清单中记录链接及解析目标；尽可能保留文件属性和权限信息。
- 无法获得一致、完整且校验通过的恢复快照时，将备份标记为 `partial`，不得替换或重组原工作区。
- 新工作区的 `workspace-management/migration/initialization-report.md` 记录备份位置、校验结果、迁移映射、保留项和未执行事项。
- 根 `USER_GUIDE.md` 记录通用备份原则，但不把备份登记为权威源、参考工程或目标。
- 创建并验证备份后只提醒用户一次：`初始化备份位于 <path>。请勿将其添加为 Codex 工作区，也不要用于同步或构建。确认新工作区正常后，它仅作为人工恢复点保留，是否删除由你决定。`
- 每次备份使用唯一 `backup_id`。提醒完成后将 `workspace.yaml` 中的 `migration.last_notified_backup_id` 更新为当前 ID；后续正常任务不重复提醒，新建另一份备份时则对新 ID 再提醒一次。

### 旧规则归档

纯净 Agent 工作区只保留一个生效的根 `AGENTS.md`，不在 `integration/` 或 linked worktree 中额外生成 `AGENTS.md` 或 `AGENTS.override.md`。用户工程本身已有的同名文件作为用户内容原样导入和保护，但不得据此从副本目录单独启动 Codex。

迁移旧 Agent 工作区时：

- 将旧 `AGENTS.md`、`AGENTS.override.md` 和当前配置列出的 fallback 指令文件逐字节复制到 `workspace-management/history/legacy-instructions/`，不得在原文中插入元数据。
- 归档文件名包含原类型、时间戳和短哈希，避免重名；独立 `manifest.yaml` 记录原路径、归档路径、归档日期、完整 SHA-256 和原文件是否曾生效。
- 归档名称必须再次检查，不得等于任何当前有效的 fallback 指令文件名。
- 新根 `AGENTS.md` 只记录归档位置和“仅供迁移审计、不再作为指令、除非用户明确要求否则不要加载”，不复制旧规则正文。
- 先验证归档和新规则，再以可回滚方式替换旧根规则；不得出现旧 override 继续覆盖新规则的状态。
- 外部用户权威工程中的 `AGENTS.md`、`AGENTS.override.md` 或 fallback 文件保持原路径和内容，不移动、不改名、不修改。

外部恢复备份根目录可以保留保护性的 `AGENTS.override.md`，但它只是误打开备份根时的辅助警示，不是安全边界；`backup-manifest.json` 和管理脚本的整树排除才是确定性保护。直接打开备份内的嵌套 Git 或 `snapshot/` 子目录可能绕过外层提示，因此用户手册必须明确禁止这样做。

### 已有工作区通用保护

- 初始化已开发到一半的工程时，将当前已保存内容视为导入基线，不把编译失败视为初始化失败。
- 不自动认领或提交用户已有改动，不为了验证重新生成或修复业务源码。
- `sources/`、`work/`、`reference-projects/`、`project-docs/` 或 `workspace-management/` 已有其他用途时，不得自动认领或覆盖。
- 已有 Git 只识别和保护，不创建错误嵌套仓库、不改写历史、不夹带既有修改。
- 已初始化工作区再次调用时保持幂等，只修复缺失内容、刷新事实或执行经过确认的迁移。

## 多权威源和源组判断

- 多个 MCU 工程位于同一个合理产品目录时，整体建立一个源组副本。
- 分散且相互独立的工程分别登记为不同源组并分别建立副本。
- 分散目录存在共享代码、相对路径依赖或共同生成器配置时，优先保持原有相对拓扑并作为同一逻辑源组处理。
- 如果维持相对关系需要复制一个包含大量无关内容的上级目录，使用多个路径映射复刻必要拓扑，不复制整个无关父目录。
- 不为管理方便改变用户原有路径、目录名或工程关系。
- 每个映射使用稳定 `mapping-id`。可移植的 `mapping-id`、`integration-subpath`、类型和映射版本写入 `targets.yaml`；对应的用户绝对 `source-path` 只写入被 Agent 管理 Git 忽略的 `targets.local.yaml`。
- 第一版只支持目录映射。单文件映射只有出现真实需求后再扩展。
- 初始化、导入和发布前校验所有真实源路径、集成路径和映射目标互不递归包含；同一源组内的 `integration-subpath` 不得重叠，任一集成文件必须能唯一反向解析到一个 `mapping-id` 和用户相对路径。
- 映射变化时递增 `mapping_revision` 并更新摘要；旧 workstream 或发布事务引用其他版本时停止发布，先执行经过确认的映射迁移。
- 副本路径优先使用较短、纯 ASCII、无特殊字符的路径，以兼容旧工具链。

正式源组还应区分来源：

- `user-imported`：存在外部用户权威源，使用可逆映射和三方同步。
- `agent-created`：由 Agent 在纯净工作区内新建，`user_source: none`、`sync_strategy: none`，不执行用户导入、发布或用户 Git 询问。
- `reference-promoted`：由参考工程明确提升而来；是否存在用户权威源由 `user_source` 独立表达。

用户以后为 Agent 自建工程指定权威路径时，必须经过受控配置迁移、建立映射和首次用户同步基线后，才能启用导入或发布。

## 初始化流程

1. 检查当前目录、候选 Agent 工作区、所有用户路径、规则文件、Git 和未提交状态。
2. 获取用户提供的权威工程路径；不递归扫描整台电脑寻找工程。
3. 解析真实路径并验证强制纯净布局；当前目录属于用户工程时只提出外部 Agent 工作区方案。
4. 首次接入非空目录或需要策略、结构、映射或 schema 迁移时只读展示具体计划；用户确认后才写入。纯事实重新扫描不走迁移流程。
5. 识别源组、可逆映射、三套 Git 边界、共享路径和嵌套仓库。
6. 扫描疑似敏感文件、授权凭据和应排除的可重建缓存。
7. 创建或确认 Agent 管理 Git；按源组创建集成副本并保持必要拓扑。
8. 为每个源组自动建立或确认源组私有 Git；`user-imported` 源组创建可取回内容的首次用户同步基线，其他正式源组创建初始代码基线。
9. 发现 MCU 工程，生成稳定 `target-id` 并写入目标配置和最小字段元数据。
10. 识别或导入用户明确提供的参考工程，并与开发源严格区分。
11. 识别 IDE、生成器、构建配置、工具链、产物和可用验证入口。
12. 在安全条件满足时尝试一次普通初始构建验证，单独记录构建结果和构建基线。
13. 独立询问用户是否为没有 Git 的权威工程创建用户 Git；未确认时不修改用户工程，也不阻塞 Agent 工作区初始化。
14. 生成唯一根规则、概览、用户手册、项目知识层、分类目录和确定性管理脚本。
15. 验证配置可读、三套 Git 边界有效、分类结构正确、根规则唯一且用户工程未被意外修改。

## 后续新 MCU 工程

源组私有 Git 是持续约束，不是初始化时的一次性动作。

触发规则：

- Agent 创建、导入或复制新 MCU 工程后立即识别来源并登记。
- 用户在已登记源路径中通过 IDE 创建新工程后，下一次 Agent 任务开始时自动发现并登记。
- 新工程位于未登记的外部路径时，Agent 只有在用户提供该路径或任务明确访问该路径后才能发现；不得扫描整块磁盘。
- 用户可以随时显式调用重新扫描作为兜底。

自动处理：

- 新工程属于已有用户源组：通过既有映射纳入集成副本和源组私有 Git，不创建嵌套 `.git`。
- 新工程位于新的外部用户路径：只有用户提供或任务明确访问该路径后才建立候选映射；路径关系明确时创建 `user-imported` 源组和私有 Git。
- Agent 在工作区内新建的正式工程：创建或纳入 `agent-created` 源组和源组私有 Git，不虚构用户权威路径。
- 新工程与已有目录共享依赖：保持相对拓扑后纳入同一源组。
- Agent 根据工程名称或用途生成稳定且人类可读的 `target-id`，重名时追加最小可用序号。
- `target-id` 写入后不随目录重命名自动变化；显示名称可以更新。
- 用户导入工程创建首次用户同步基线后再允许 Agent 修改；Agent 自建工程创建初始私有 Git 基线后再修改。

存在下列歧义时，只建立待确认候选，不正式登记：

- 无法判断是新工程、备份、复制品还是厂商示例。
- 存在嵌套工程入口或嵌套 Git。
- 已登记工程疑似移动、拆分或合并。
- 新扫描结果与已确认的 MCU、构建命令或生成代码边界冲突。
- 无法唯一确定源组来源、映射或是否存在用户权威源。

## 幂等要求

- 已存在的文件、目录和私有 Git 不重复初始化。
- 已登记且没有变化的目标不重写配置、不创建空提交。
- 已确认或已验证字段不被启发式结果静默覆盖。
- 新扫描只补充缺失信息或追加新对象。
- 消失或移动的工程标记为待确认，不直接删除记录。
- 构建命令、工具链或其依赖变化时保留旧信息、将相关验证状态标为 `stale` 并报告差异。
- 映射内容没有变化时不递增 `mapping_revision`；映射变化必须保留旧版本引用并走受控迁移。
- 人工维护的配置发生并发变化时重新读取，不能覆盖。

## 三套 Git 必须分离

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

### Agent 管理 Git

纯净 Agent 工作区根目录自动建立一个 Agent 管理 Git，不再单独询问用户。它只管理工作区规则和元数据：

- 根 `AGENTS.md`、`README.md` 和 `USER_GUIDE.md`。
- `project-docs/`、参考工程包装说明和索引。
- 可移植配置、管理工具、模板、迁移历史、workstream 的 `README.md` 与 `workstream.yaml`。

它必须忽略由其他仓库或本机状态负责的内容：

- `sources/*/integration/`。
- `work/*/sources/` 和 `work/*/reference-copies/`。
- `reference-projects/*/project/`。
- `targets.local.yaml`、`sync-state/`、`evidence/`、`recovery/` 和 IDE workspace 状态。
- 构建产物、下载内容、大型日志及明确的任务临时文件。

有长期价值的小型任务脚本可以纳入管理 Git；临时生成物不得借此进入历史。管理 Git 不配置可写推送流程，不包含用户权威工程或源组代码。

### 源组私有 Git

源组私有 Git 是强制且自动维护的工作区内部机制，不再单独询问用户。

- 每个受管源组始终必须由独立的源组私有 Git 覆盖。
- 用户源组对应单个 Git 仓库时，优先建立不共享对象库的独立本地 clone，并导入用户当前已保存的 dirty 和必要 untracked 内容。
- 用户源组没有 Git，或由多个路径映射组成时，在保持拓扑的集成副本内初始化私有 Git。
- `user-imported` 源组自动创建用户同步基线、稳定基线 ref 和必要检查点；没有用户权威源的源组只创建初始代码基线和任务检查点。
- 自动为不同 workstream 创建分支和 linked worktree，固定放在 `work/<workstream-id>/sources/<source-id>/`。
- 不配置可写推送流程，不把内部提交推送或写入用户工程 Git。
- 新增 MCU 工程时自动纳入相应私有 Git并创建导入提交。
- 源组私有 Git 只承诺恢复已纳管、已导入且未被过滤的内容，不能替代用户工程自身的完整版本保障。
- 可修改的任务参考副本可以使用同类的临时私有 Git，但不属于任何用户源组，也不参与发布。

推荐配置语义：

```yaml
git:
  user_source:
    status: deferred
    auto_commit: false
  management:
    status: enabled
    push: disabled
  source_copy:
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
    -> work/<workstream-id>/sources/<source-id>/
```

- 每个独立逻辑任务使用独立 workstream、私有 Git 分支、worktree 和构建输出。
- 新逻辑任务默认创建新 workstream；用户明确续接已有任务，或运行环境能够唯一识别已有绑定时才复用。
- 一个 workstream 可以同时挂载多个源组的 worktree。
- 不同 workstream 不直接写同一物理源码文件。
- 新任务、范围扩大、构建前和发布前读取其他活动或仍有未处置改动的 workstream；写入路径范围重叠时先协调。
- 同一对话中的子 Agent 由主 Agent 分配边界，同一文件同时只能有一个写入者。
- workstream 可以合入集成副本进行汇总验证，但集成副本不能作为发布差异来源；发布必须绑定明确的 workstream 提交和依赖闭包。
- 不使用容易因异常退出而遗留的手工锁文件。
- 所有 Codex 任务必须从纯净 Agent 工作区根启动。`integration/` 和 linked worktree 不得单独添加、保存或打开为 Codex 项目；进入子目录修改或构建不改变任务启动时已加载的根规则。
- 初始化系统不在 `integration/` 或 worktree 中额外生成规则文件。用户工程原有的 `AGENTS.md` 等同名文件作为工程内容原样保护，但不属于本系统的生效规则。

## Workstream 状态记录

每个 workstream 使用机器清单和人类状态快照，不采用不断追加的聊天流水日志：

```text
work/<workstream-id>/
|-- workstream.yaml
|-- README.md
|-- sources/
|   `-- <source-id>/
|-- reference-copies/
|-- tools/
`-- artifacts/
```

`workstream.yaml` 是唯一机器事实源，至少记录：

```yaml
schema: 1
id: 20260910-motor-stall-a13f
status: active
title: motor stall protection
conversation:
  primary: null
scope:
  - source_id: motor-product
    targets: [motor-controller]
    paths:
      - path: firmware/motor-controller
        access: write
agent:
  refs:
    motor-product:
      branch: workstream/20260910-motor-stall-a13f
      worktree: work/20260910-motor-stall-a13f/sources/motor-product
      user_baseline_commit: <commit>
      task_base_commit: <commit>
      head_commit: null
dependencies: []
has_unresolved_changes: false
updated_at: 2026-09-10T00:00:00+08:00
```

- 当前运行环境能够稳定提供 `host_id` 和 `thread_id` 时，可以写入 `conversation.primary`；这些字段始终可选，不能成为创建或使用 workstream 的前提。
- 对话标题和目录名不能代替稳定 ID。用户明确说“继续某任务”时按 `workstream-id` 或唯一匹配绑定；无法唯一判断时才询问。
- 一个对话同一时刻只绑定一个活动 workstream。切换任务时更新状态或解绑，不覆盖历史关系。
- `scope` 使用 `source-id + 规范化相对路径 + access`；Windows 路径比较不区分大小写，拒绝 `..` 和真实路径越界。
- 范围先按任务需要粗粒度登记，只在扩大写入范围或发布前更新，不要求每次编辑都改清单。
- 不同源组只有在真实路径也不重叠时才可视为独立；只读范围通常不阻塞其他任务写入，高影响生成器、链接脚本和 IDE 元数据的并发写入始终报告。
- `completed` 或 `abandoned` 只有在 `has_unresolved_changes: false` 时才退出冲突检测。

`README.md` 只供人阅读和交接，推荐结构：

```text
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

不记录完整聊天、每条命令、完整构建输出或无关浏览过程。Git 记录“改了什么”，`README.md` 记录“为什么、当前状态和下一步”。全局状态直接读取各 `workstream.yaml`，不维护重复的 `workspace-management/workstreams/` 手写索引。

## 用户工程导入与发布

只定义三个方向明确的操作：

- `inspect`：只读检查用户工程。
- `import`：用户工程到 Agent 集成副本或当前 workstream。
- `publish`：当前 Agent workstream 到用户权威工程。

### 任务开始导入

每次开发任务开始时先执行不落盘的轻量检查：

- 有 Git 时比较提交和工作区差异。
- 无 Git 时先比较文件清单、大小和修改时间，只对变化候选计算哈希。
- 只扫描已登记源路径，不扫描整台电脑。
- 用户明确要求“只检查”“只读”或“不更新任何状态”时，检查结束后只报告结果，不执行导入或任何事实更新。
- 用户变化、Agent 未修改相同位置时自动导入。
- 双方修改不同文件或文本文件不同区域时可以三方合并。
- 同一位置、删除与修改、二进制、生成代码或 IDE 元数据冲突时停止该文件同步并报告。
- 长任务在构建前和发布前再次检查相关文件。

每次成功导入都在对应源组私有 Git 中创建可取回受管内容的不可变用户同步基线提交，并使用稳定 ref 保持可达。哈希用于快速检测变化，Git 提交用于取回基线实际内容，两者不能互相替代。扫描不完整、文件不可读或路径被过滤时，不得把“未发现”判定为删除。

活动 workstream 安全导入新的用户变化后，必须先冻结任务检查点，再将任务自己的提交重放到新的用户同步基线和已声明依赖之上，同时更新 `user_baseline_commit` 与 `task_base_commit`。用户来源的变化不得留在 `task_base_commit..head_commit` 的任务差异中；重放产生冲突时停止并报告，不自动改写任务意图。

### 同步状态模型

动态状态位于被 Agent 管理 Git 忽略的 `workspace-management/sync-state/`：

```text
sync-state/
|-- sources/
|   `-- <source-id>.yaml
|-- indexes/
|   `-- <source-id>.jsonl
|-- workstreams/
|   `-- <workstream-id>/
|       `-- <source-id>.yaml
`-- transactions/
    `-- <publish-id>.yaml
```

`user-imported` 源组的 `sources/<source-id>.yaml` 至少记录：

```yaml
source_id: motor-product
mapping_revision: 3
mapping_digest: <sha256>
user_baseline_id: baseline-20260910-001
user_baseline_commit: <private-git-commit>
user_baseline_ref: refs/agent/user-baselines/baseline-20260910-001
captured_at: <timestamp>
scan_complete: true
file_index: ../indexes/motor-product.jsonl
build_baselines:
  motor-controller/Debug:
    last_successful_build_commit: <commit-or-null>
    evidence_ref: ../../evidence/build-motor-controller-debug.yaml
```

文件索引至少记录 `mapping-id`、相对路径、类型、大小、修改时间和 SHA-256。它只覆盖实际纳管的文件；敏感文件和明确过滤项不伪装成可由私有 Git 恢复的内容。

workstream 的身份、范围、`user_baseline_commit`、`task_base_commit`、`head_commit` 和依赖以 `work/<workstream-id>/workstream.yaml` 为准。`sync-state/workstreams/` 只保存可重建的每源比较缓存，不复制一份互相竞争的权威状态。

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
2. 冻结当前 workstream 的 `head_commit`，校验 `user_baseline_commit`、`task_base_commit`、依赖闭包和 `mapping_revision`。
3. 重新扫描用户权威工程，避免覆盖刚保存的修改；扫描必须完整且所有路径可唯一映射。
4. 使用 `user_baseline_commit`、用户当前内容和冻结的 `head_commit` 做三方比较；发布内容只来自 `task_base_commit..head_commit` 及显式依赖闭包，不能从整个集成分支推断。
5. 生成并冻结逐文件发布清单。每项包含 `source-id`、`mapping-id`、相对路径、显式 `add|modify|delete`、基线/用户/Agent/预期结果的 blob 或 SHA-256。
6. 对所有相关源完成统一 dry-run；任何三方冲突、映射歧义、范围外修改或不完整扫描都以零写入结束。
7. 为所有相关权威源创建恢复快照和 SHA-256 清单，排除已确认可重建的缓存和构建产物。
8. 禁止目录镜像覆盖、`/MIR`、`--delete` 或基于时间戳盲目覆盖；路径必须位于映射对应的权威根内，拒绝绝对路径注入、`..` 和链接越界。
9. 逐文件应用清单；删除先移动到恢复区，不立即永久删除。
10. 校验实际文件结果与冻结清单一致，再在安全可用时构建用户工程。
11. 文件和构建结果按下述事务规则处理，最后才更新用户同步基线或构建基线。

多个权威源无法形成严格的文件系统原子事务，应采用“全部预检、全部备份、逐源应用、统一校验”。

发布事务写入 `transactions/<publish-id>.yaml`，正常状态为：

```text
planned -> backed_up -> applying -> applied -> file_verified -> completed
```

异常处理：

- `conflicted`：写入前发现冲突，用户工程零写入结束。
- `apply_failed`：路径、补丁应用或文件校验失败，自动回滚本事务已经应用的所有源；回滚成功后标记 `rolled_back`，用户同步基线不变。
- `verification_failed`：文件已经正确发布，但用户工程构建失败。保留现场、发布差异、构建日志和恢复快照，停止自动修改、重试或重新生成，等待用户明确选择保留现状或回滚。
- 用户选择回滚构建失败的发布时，恢复所有相关源并验证，用户同步基线保持不变。
- 用户明确接受构建失败后的内容时，可以将该内容登记为新的用户同步基线，但对应目标和配置的 `last_successful_build_commit` 保持原值或 `null`，不得声称构建通过。
- 构建入口不可用或不能安全执行时，可以在文件校验成功后完成发布并推进用户同步基线，但必须记录“用户工程未完成构建验证”，构建基线不变。
- `recovery_required`：任何自动回滚失败后立即停止并报告，禁止开始新的导入或发布，直到恢复状态经过人工处理和验证。

只有文件应用和校验成功，且不存在待用户决定的 `verification_failed`，才能进入 `completed` 并推进用户同步基线。只有实际构建成功才更新 `last_successful_build_commit`。

## 软隔离和代码保护

- 用户明确要求只读、只检查或不更新状态时，本次任务进入最高优先级 `read-only` 模式：只允许不落盘的读取和计算，不创建或修改配置、目录、workstream、日志、备份、Git 提交或构建输出，也不运行已知会写文件的 IDE、生成器或构建命令。该要求同时覆盖普通事实刷新和初始化 Skill。
- 每次任务开始的轻量变化检查本身始终只读；只有不处于 `read-only` 模式的普通任务才能按既有规则自动导入和更新事实。
- 工作副本是强制默认架构，不能取消。
- 用户权威工程默认只读使用，所有普通开发、构建和生成操作在当前 workstream 副本内进行。
- 写文件和运行工具前解析真实路径，确认写入位置属于当前 workstream 或明确允许的工作区管理目录。
- 日常 Codex 项目的根目录只能是独立纯净 Agent 工作区，用户权威工程不属于普通可写 workspace root。
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

### 构建命令与结果状态

构建命令本身的可信状态与某次工程构建结果分开记录：

- `candidate`：根据证据生成，但尚未成功验证。
- `verified`：该命令曾成功运行并生成或更新预期 ELF、HEX 或 BIN。
- `unavailable`：当前缺少工具链、依赖或授权凭据，无法执行。
- `unconfirmed`：命令存在潜在副作用，不能安全运行。
- `stale`：命令、工程路径、工具版本或关键依赖已经变化，需要重新验证。

每次构建结果单独使用 `passed`、`failed`、`unavailable` 或 `not-run`。源码错误导致当前构建失败时，保留此前已经验证的命令状态，只把本次结果记为 `failed`；只有命令或依赖本身变化才标为 `stale`。对应目标和构建配置的 `last_successful_build_commit` 只在实际构建成功并取得产物证据时更新。

### 安全初始构建条件

- 工具存在且版本查询成功。
- 工程、目标、配置、工作目录和输出目录明确。
- 构建只在 Agent 副本内写入。
- 不需要重新生成源码。
- 已检查构建钩子，不包含烧录、擦除或未知外部写入。
- 不与正在运行的 IDE 争用同一 IDE workspace。

初始化阶段不得执行 `clean`、`rebuild`、删除构建目录、自动安装工具、转换工程系统或为了让构建通过而修改业务源码。退出码成功但产物未产生或未更新，不能把命令或本次结果标记为 `verified`、`passed`。

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

本节规则适用于把用户工程或外部参考导入 Agent 工作区的 `agent-import`，不适用于纯净 Agent 工作区迁移前的 `recovery-backup`。恢复备份按前述要求尽量原样保存，导入副本才执行以下过滤：

- 默认不复制 `.git` 元数据、IDE workspace 元数据、可重建缓存和普通构建产物。
- 确定性识别的私钥、令牌、凭据、生产签名文件、工具链授权文件、激活凭据、许可证密钥和设备转储只列出，不复制。
- `LICENSE`、`NOTICE`、`COPYING`、`COPYRIGHT` 和第三方版权清单属于法律合规资料，随源码或参考工程保留并记录来源；不得按文件名中的 `license` 或单一扩展名笼统排除。
- 无法判断是法律说明还是授权凭据时标记为待确认，不复制、不删除原文件，也不从网络补全或臆造许可证。
- 高熵检测只产生警告，不能据此排除所有二进制，因为预编译库和固件可能天然高熵。
- 构建需要的秘密或授权材料优先通过环境变量、许可证服务器或外部只读路径引用。
- 明确允许复制的敏感文件或授权材料必须确认许可条款允许复制，且不得进入 Agent 管理 Git、源组私有 Git 或任务参考副本 Git。
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
    |-- manifest.json
    `-- project/
```

用途和边界：

- 用于存放用户提供、从外部路径导入或从公开仓库取得的参考工程快照。
- 每个参考工程使用稳定、简短的 `reference-id`。
- `<reference-id>/README.md` 至少记录来源、获取日期、版本或提交、参考用途、适用目标、许可证、已知差异和是否经过构建验证。
- `<reference-id>/manifest.json` 记录导入时的受管文件清单和 SHA-256，由 Agent 管理 Git 跟踪，用于确认未纳入管理 Git 的 `project/` 快照没有变化。
- `project/` 保持参考工程自身目录结构；包装层 README 不覆盖项目原有 README。
- `reference-projects/README.md` 维护简短索引，帮助 Agent 只读取与当前任务有关的参考工程，禁止默认加载全部参考代码。
- 参考工程默认只读，不直接修改、不创建 workstream 分支、不进入 Agent 到用户工程的同步或发布流程。
- Agent 不得把参考工程自动识别为 MCU 开发目标或权威源，即使其中存在 `.ioc`、`.uvprojx`、`.ewp`、Makefile 等工程标志。
- 需要试改、构建或验证参考工程时，将所需快照复制到 `work/<workstream-id>/reference-copies/<reference-id>/project/`；在其外层创建 `README.md` 记录来源快照、快照哈希或版本、用途、创建时间、所属 workstream、构建状态和清理条件，不得覆盖参考工程自带说明或污染原参考快照。
- 每个可修改的参考工程副本自动建立独立的临时私有 Git 和导入基线，不纳入用户工程发布、不推送；只有对应 workstream 已完成且不存在未保留成果时才可以清理。
- 参考工程正文由内容清单和来源版本保证不可变，默认不进入 Agent 管理 Git；包装说明和索引由管理 Git 跟踪。来源不可重新取得且快照不可替代时先向用户报告，不自行改变 Git 边界。
- 需要将参考工程正式转为开发工程时，必须由用户明确表达提升意图，再登记为 `reference-promoted` 源组，执行敏感检查并建立源组私有 Git 基线；是否建立用户权威映射由用户另行决定。
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

所有分类都相对于固定的纯净 Agent 工作区根目录 `managed_root: .`：

```text
.git/                       # Agent 管理 Git
.gitignore                  # 管理 Git边界和本机状态排除
project-docs/
`-- README.md
reference-projects/
|-- README.md
`-- <reference-id>/
    |-- README.md
    |-- manifest.json
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
    |-- workstream.yaml
    |-- sources/
    |   `-- <source-id>/
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
|-- evidence/
|   `-- README.md
|-- recovery/
|   `-- README.md
|-- migration/
|   |-- README.md
|   `-- initialization-report.md
|-- history/
|   |-- README.md
|   `-- legacy-instructions/
|       |-- README.md
|       `-- manifest.yaml
`-- ide-workspaces/
    `-- README.md
```

规则：

- 纯净 Agent 工作区根目录只允许 Agent 管理 Git元数据、管理 `.gitignore`、三个入口文档和一级分类目录；用户权威工程永远不位于其中。
- 项目级长期事实进入 `project-docs/`，不与单个 workstream 的过程状态混写。
- 参考工程只进入 `reference-projects/<reference-id>/project/`，不得混入 `sources/` 或正式 workstream 工程。
- 正式源码保留在 `work/<workstream-id>/sources/<source-id>/` 内对应工程的原有相对位置。
- 参考工程的试改或构建副本进入 `work/<workstream-id>/reference-copies/<reference-id>/project/`。
- 一次性任务脚本进入 `work/<workstream-id>/tools/`。
- 可复用工作区工具进入 `workspace-management/tools/<purpose>/`。
- 后续普通 Agent 需要的本地模板进入 `workspace-management/templates/`；不得依赖初始化 Skill 安装目录中的隐藏资源。
- 分析报告、日志摘要和导出物进入当前 workstream 的 `artifacts/`。
- 同步状态进入 `workspace-management/sync-state/`。
- 构建和验证证据进入 `workspace-management/evidence/`；配置中只保存简短引用。
- 发布恢复快照进入 `workspace-management/recovery/<publish-id>/`。
- IDE 独立 workspace 元数据进入 `workspace-management/ide-workspaces/`，不与用户 IDE workspace 混用。
- 每个职责边界目录必须包含 `README.md`，说明用途、所有权、Git 状态和清理规则。
- 不要求 MCU 工程内部每个源码子目录都创建说明文件。
- IDE 或构建系统强制位于工程根目录的文件和输出路径属于例外，不能为了分类破坏工程。
- Agent 不得把脚本、日志、下载文件、测试产物或临时文件直接放在工作区根目录。
- Agent 管理 Git只跟踪规则、模板、可移植配置、项目知识和任务元数据，并按“三套 Git 必须分离”中的清单忽略其他内容。

### 运行期工具与模板

初始化完成后，将日常任务需要的确定性脚本部署到 `workspace-management/tools/`：

- `detect-targets.ps1`：轻量发现新增或变化的 MCU 工程。
- `import-sources.ps1`：按可逆映射导入用户已保存变化并维护用户同步基线。
- `import-reference.ps1`：导入只读参考工程及其来源信息。
- `create-reference-copy.ps1`：创建带独立私有 Git 基线的任务参考副本。
- `new-workstream.ps1`：创建或明确复用 workstream、分支、linked worktree 和机器清单。
- `publish-workstream.ps1`：冻结任务提交，执行映射校验、三方预检、事务备份和受控发布。

`init-workspace.ps1`、`plan-migration.ps1`、`backup-workspace.ps1`、`apply-migration.ps1` 和 `refresh-workspace.ps1` 仅由显式初始化 Skill 使用，不复制成普通任务可随意调用的日常入口。

`workspace-management/templates/project-docs/` 保存 PRODUCT、SOLUTION、ROADMAP、decision 和 version 的本地格式说明或模板，使没有日常开发 Skill 的普通 Agent 也能按一致格式创建后续文档。模板只定义职责和必要字段，不包含虚构项目内容。

## 配置建议

### `workspace.yaml`

保存工作区格式和策略版本，用于幂等刷新与受控迁移：

```yaml
workspace_schema: 1
policy_version: 1
layout_mode: pure
managed_root: .
initializer: embedded-workspace-init
initialized_at: 2026-09-10T00:00:00+08:00
migration:
  last_backup_id: null
  last_notified_backup_id: null
```

- `workspace_schema` 表示目录和配置数据结构版本。
- `policy_version` 表示 Agent 行为规则版本。
- `layout_mode` 固定为 `pure`，`managed_root` 固定为 `.`；其他值视为需要迁移的旧格式，不能继续日常写入。
- `last_backup_id` 记录最近创建的迁移备份，`last_notified_backup_id` 记录已经向用户提示过的备份；两者不相等时显示一次处置提醒。
- Skill 自身升级不会自动迁移已有工作区；只有显式刷新并确认具体计划后才改变结构或策略版本。

### `targets.yaml`

只保存可移植、可共享的工程事实，不保存绝对本机路径或秘密。

```yaml
schema: 1

sources:
  motor-product:
    origin: user-imported
    user_source: configured
    integration_path: sources/motor-product/integration
    write_policy: explicit-publish-only
    sync_strategy: three-way
    mapping_revision: 1
    mappings:
      - mapping_id: motor-firmware
        integration_subpath: firmware/motor-controller
        kind: directory
      - mapping_id: shared-protocol
        integration_subpath: shared/protocol
        kind: directory

  sensor-node:
    origin: agent-created
    user_source: none
    integration_path: sources/sensor-node/integration
    sync_strategy: none
    mapping_revision: 0
    mappings: []

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
      command_state: verified
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

field_metadata:
  /targets/motor-controller/mcu:
    provenance: detected
    freshness: current
    evidence_ref: workspace-management/evidence/mcu-motor-controller.yaml
  /targets/motor-controller/build/command:
    provenance: detected
    verification: verified
    freshness: current
    evidence_ref: workspace-management/evidence/build-motor-controller.yaml
  /targets/motor-controller/generated/policy:
    provenance: confirmed
    verification: unverified
    freshness: current
```

普通值保持紧凑；只有目标身份、路径、MCU、工程入口、构建命令、生成代码策略等需要保护或追溯的重要字段，才在 `field_metadata` 中按稳定 YAML 路径记录元数据。无需为每个字段包装完整对象。

- `provenance` 使用 `detected|confirmed|imported`，表示值来自扫描、用户确认或既有配置导入。
- `verification` 使用 `unverified|verified|failed`，只表示该字段是否经过实际验证。
- `freshness` 使用 `current|stale|conflicted`，表示字段与当前工程和环境是否一致。
- 自动扫描只允许增加缺失值或更新 `provenance: detected` 的值；`confirmed` 值不得静默覆盖，新候选写入动态状态并报告。
- `verified` 只能由实际证据产生。工程路径、工具版本、命令或关键依赖变化时保留原值并标为 `stale`。
- 用户明确修改值时将 `provenance` 设为 `confirmed`，同时清除不再适用的旧验证状态。
- 构建失败保留命令配置并记录本次失败证据，不能把源码失败误报成命令配置失效。

详细证据进入 `workspace-management/evidence/`，配置只保存简短引用。未知信息省略或使用 `null`，不能猜测。

### `targets.local.yaml`

保存本机易变信息，并加入 Agent 管理 Git 和所有代码私有 Git 的忽略规则：

```yaml
schema: 1

sources:
  motor-product:
    mappings:
      motor-firmware:
        source_path: D:/Projects/MotorController
      shared-protocol:
        source_path: D:/Shared/ProductProtocol

tools:
  cubeide: C:/Tools/STM32CubeIDE/stm32cubeide.exe

hardware:
  motor-controller:
    probe: st-link
    probe_serial: null
    serial_port: null
```

不得在其中存放密钥。

`mapping-id` 必须与 `targets.yaml` 一一对应。映射关系固定为 `source_path/<relative-path> <-> integration_path/integration_subpath/<relative-path>`，发布时按同一关系反向解析；任何无法唯一映射的文件直接停止。动态文件哈希、用户同步基线、构建基线和发布事务写入 `workspace-management/sync-state/`，不要频繁改写人工配置。

## 根目录文档职责

### `AGENTS.md`

纯净 Agent 工作区只保留一个系统生成并生效的根 `AGENTS.md`，不创建根 `AGENTS.override.md` 或其他 fallback 指令文件。文件保持短而明确，并验证不超过当前 Codex 指令发现容量。至少约束：

- 所有新任务从纯净 Agent 工作区根启动，不把 `sources/`、`integration/` 或 `work/` 中的代码副本单独添加为 Codex 项目。
- 用户工程自带的同名规则文件作为工程内容保护，不是本工作区的生效规则；初始化系统不向代码副本额外生成规则文件。
- 读取目标和本机配置。
- 按当前任务需要读取参考工程索引和相关参考项目，不默认遍历全部参考工程。
- 参考工程原快照保持只读，试改和构建只能在 `work/<workstream-id>/reference-copies/` 中进行。
- 读取 `project-docs/` 中与当前任务有关的产品边界、当前方案和开发路径；未确认的 workstream 结论不得自动提升为项目事实。
- 任务开始执行轻量目标与源变化检测。
- 新 MCU 工程自动识别来源并纳入对应源组私有 Git；Agent 自建工程不虚构用户源。
- 用户工程默认只读，普通写入只发生在 workstream 副本。
- 创建或明确复用 workstream，读取机器清单并检查其他活动任务的写入范围。
- 优先使用已验证构建命令并执行最小充分验证。
- 保护 IDE 生成代码和用户已有修改。
- 分类存放所有新文件。
- 更新 workstream 状态。
- 发布必须识别明确的 Agent 到用户工程意图并执行三方检查和备份。
- 用户同步基线与构建基线分开；发布只能来自冻结 workstream 提交和显式依赖闭包。
- 用户工程 Git 提交只在明确要求时执行。
- 普通任务不得自行修改受管策略、目录模式和迁移工具；发现不适配时只提出调整方案。
- 使用初始化 Skill 更新已有约束时，展示计划后必须停止；用户确认前连日常事实登记也不得写入。
- 用户要求只读或只检查时，禁止一切落盘事实刷新、构建、备份和 Git 操作。
- 旧规则归档只供迁移审计，除非用户明确要求，否则不作为指令加载。

### 根 `README.md`

提供一屏可读的工作区概览、核心目录入口和当前管理状态，不复制完整使用手册。第一屏明确写明唯一 Codex 项目入口是当前根目录，不得单独打开 `sources/` 或 `work/` 中的副本。

### `USER_GUIDE.md`

初始化后必须在根目录生成 UTF-8 中文用户手册，面向用户而非 Agent。内容至少包括：

1. 60 秒快速开始。
2. 用户权威工程、集成副本和 workstream 的区别。
3. 自动执行事项和需要用户明确表达的事项。
4. 用户工程 Git、Agent 管理 Git 和源组私有 Git 的区别。
5. 导入和发布的方向及自然语言示例。
6. 多 MCU、多权威源和多对话并行的使用方式。
7. `reference-projects/` 只读快照与 `work/<workstream-id>/reference-copies/` 任务副本的区别、实际位置、私有 Git 和清理条件。
8. 产品定义、方案记录、开发路线、决策和版本资料分别存放在哪里。
9. 如何从已有用户工程建立外部纯净 Agent 工作区，以及如何迁移非空旧 Agent 工作区。
10. 工作区规则如何提出升级计划、等待一次确认、验证、记录和回滚。
11. 外部初始化备份的用途、恢复方式、禁止作为 Codex 工作区或构建源的规则。
12. 工作区目录说明。
13. 用户同步基线与构建基线的区别，以及发布失败、发布后构建失败、同步冲突和恢复方法。
14. 未保存缓冲区、软隔离和板卡共享等已知边界。
15. 唯一根 `AGENTS.md`、旧规则归档和禁止单独打开 worktree 的要求。

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
将 <reference-id> 提升为正式开发工程；先作为 reference-promoted 源组，不建立用户发布映射。
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

完成初始化、当前没有待确认的约束迁移且用户没有要求 `read-only` 时，普通 Agent 可以幂等更新：

- 新源组、MCU 目标和稳定 ID。
- 工具链位置、候选构建命令及其验证状态。
- 参考工程索引和 workstream 当前状态。
- 用户已保存内容与 Agent 副本之间的同步事实。

这些更新不得改变根 `AGENTS.md`、固定纯净布局、同步策略、Git 策略、安全门槛或迁移工具。普通 Agent 发现现有规则反复不适配时，只在回复或当前 workstream 中说明问题并提出候选方案，不自行“优化”约束。

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
2. 创建 Agent 管理 Git 检查点、受影响源组私有 Git 检查点和管理文件快照。
3. 需要替换根 `AGENTS.md` 时，先按“旧规则归档”保存上一版本及清单，再整体写入唯一的新规则文件；不使用受管区和用户自定义区拼接。随后执行幂等结构或配置迁移，保留稳定 ID、确认字段、已有副本和未提交改动。
4. 验证 YAML、路径引用、唯一根规则、fallback 排除、检测脚本、工作副本、三套 Git 和分类结构；能安全构建时再执行初始构建验证。
5. 成功后更新版本、必要的 `USER_GUIDE.md`，并在 `workspace-management/history/YYYY-MM-DD-policy-vN-to-vM.md` 记录原因、计划、批准、差异、归档清单、验证和回滚方法。
6. 验证失败时恢复管理文件和结构、验证回滚结果，并记录失败及已回滚的迁移尝试；不得触碰用户业务源码或隐式发布到用户工程。

根 `AGENTS.md` 由初始化系统整体管理，活跃工作区中只保留这一份生效规则。旧规则原文和元数据只进入历史归档，不复制到新规则；更新后的指令从下一次任务或重新打开工作区开始使用最可靠。

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
|   |-- workstream.yaml
|   |-- legacy-instructions-manifest.yaml
|   |-- source-sync-state.yaml
|   |-- publish-transaction.yaml
|   |-- workspace.yaml
|   `-- targets.yaml
|-- references/
|   |-- source-and-target-detection.md
|   |-- build-discovery.md
|   |-- existing-workspace-migration.md
|   |-- project-knowledge.md
|   |-- reference-projects.md
|   |-- synchronization.md
|   |-- git-ownership.md
|   |-- workstreams.md
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

1. 全新空目录能初始化完整的纯净 Agent 工作区、Agent 管理 Git 和三份根入口文档。
2. 当前打开目录是用户工程时，Skill 只读建议外部空目录，确认前不在任一位置写入。
3. Agent 工作区与所有用户源的真实路径互不包含；符号链接、junction 或映射造成的间接包含会阻止初始化。
4. 非空且未初始化的候选 Agent 工作区在确认具体迁移计划前保持零写入。
5. 旧 Agent 工作区迁移前在外部建立并验证完整恢复备份，再从快照分类重建。
6. 配置只允许 `layout_mode: pure` 和 `managed_root: .`，不产生兼容模式或 `agent-workspace/`。
7. 布局初始化不会在外部用户工程增加规则、说明、`.gitignore` 或 Agent 管理文件。
8. 用户另行确认启用用户 Git时，才允许独立创建 `.git` 和必要 `.gitignore`。
9. 活跃 Agent 工作区只有一个系统生成的根 `AGENTS.md`，没有根 override 或 fallback 规则。
10. 旧 Agent 规则逐字节归档，独立清单保存原路径、时间和 SHA-256，归档文件不再被 Codex 发现。
11. 外部用户工程原有的 `AGENTS.md`、override 和 fallback 文件保持原样。
12. 初始化系统不向 integration 或 linked worktree 添加规则文件；所有任务从纯净根目录启动。
13. 外部备份的 override 只作为警示，机器标记和管理脚本会排除整个备份树。
14. 单 MCU 与多 MCU 使用同一套源组和目标模型。
15. 分散权威源通过多个稳定映射保持必要相对拓扑，不复制无关父目录。
16. 映射便携结构位于 `targets.yaml`，本机绝对路径只位于被忽略的 `targets.local.yaml`。
17. 每个集成文件都能唯一反向映射；目标重叠、路径越界或映射歧义会停止导入和发布。
18. 映射实际变化才递增版本；旧 workstream 或事务引用旧版本时不能发布。
19. Agent 自建工程使用 `origin: agent-created`、`user_source: none` 和 `sync_strategy: none`。
20. 参考工程提升后使用 `origin: reference-promoted`，不会自动虚构用户权威源。
21. 后续新增 MCU 工程能够识别来源、稳定登记并纳入对应源组私有 Git。
22. 重复扫描不会重复目标、重写确认字段、递增未变化映射或创建空提交。
23. 稀疏 `field_metadata` 能区分来源、验证和新鲜度，扫描不会覆盖用户确认值。
24. 工程或工具依赖变化后，相关已验证字段会变为 `stale` 而不是伪装仍然有效。
25. 用户工程 Git、Agent 管理 Git 和源组私有 Git 的边界互不混淆。
26. Agent 管理 Git只跟踪规则、可移植配置、项目知识、工具、模板、历史和任务元数据。
27. Agent 管理 Git会忽略代码仓库、参考正文、本机配置、同步状态、证据、恢复数据和 IDE 状态。
28. 用户工程有 Git时不会自动提交或推送；无 Git时同意、拒绝和无回应进入正确状态。
29. 每个源组自动拥有独立私有 Git 和必要检查点；每个 `user-imported` 源组另有稳定用户基线 ref，所有私有 Git 均不向用户仓库推送。
30. 用户源为单 Git仓库时，私有 clone仍能导入已保存的 dirty 和必要 untracked 内容。
31. 每个 workstream 使用固定 `work/<id>/sources/<source-id>/` linked worktree，不直接写公共集成副本。
32. `workstream.yaml` 是任务身份、范围、Git 基线和依赖的唯一机器事实源，README 只做人类交接。
33. 对话 ID不可用时仍能创建 workstream；新任务默认新建，明确续接且唯一匹配时才复用。
34. 范围使用 `source-id + 相对路径 + access`，扩大写范围和发布前都会检查冲突。
35. 已完成但仍有未处置修改的 workstream 继续参与冲突检测。
36. 多个 workstream 可以独立修改和构建，重叠写入或高影响文件并发会被报告。
37. 汇总集成分支可以用于验证，但不会被直接用作发布差异来源。
38. 用户同步基线与构建基线相互独立；从未成功构建的工程仍能进行三方同步。
39. `user_baseline_commit`、`task_base_commit` 和 `head_commit` 分别表达共同基线、任务起点和冻结结果。
40. 用户同步基线提交由稳定 ref 保持可达，能够取回所有实际纳管且未过滤的基线内容。
41. 文件索引记录映射、路径、类型、大小、时间和哈希，不把不完整扫描误判为删除。
42. 活动 workstream 导入新的用户变化后会重建用户和任务基点，用户来源的内容不会混入任务发布差异。
43. 发布只包含 `task_base_commit..head_commit` 和显式依赖闭包，不夹带其他 workstream。
44. 冻结发布清单逐文件记录映射、操作、基线、用户、Agent 和预期结果哈希。
45. 用户与 Agent 修改同一位置、映射变化或扫描不完整时，发布在写入前停止。
46. 发布不会使用整目录镜像覆盖；删除显式登记并先移入恢复区。
47. 多源发布先全部预检和备份，再逐源应用并统一校验。
48. 路径、补丁应用或文件校验失败会自动整体回滚，用户同步基线保持不变。
49. 文件正确发布但用户工程构建失败时保留现场和快照，等待用户选择保留或回滚。
50. 用户接受构建失败内容时只推进用户同步基线，不更新构建基线或宣称构建成功。
51. 构建不可用时可在文件校验成功后完成发布，但明确记录用户工程未完成构建验证。
52. 自动回滚失败会进入 `recovery_required`，阻止新的导入和发布。
53. 所有语义等价的 Agent 到用户工程表达触发同一发布流程，方向不清才询问。
54. 构建命令状态与单次构建结果分开；只有成功生成预期产物才建立验证证据。
55. 副本不复用旧缓存，并使用独立 IDE workspace 完成安全初始构建。
56. `read-only` 是最高优先级模式，不创建配置、目录、日志、备份、Git 提交或构建输出。
57. 导入保留法律和版权说明，过滤授权凭据；用途不明确的文件进入待确认清单。
58. 疑似秘密不会自动复制或进入任何 Agent Git，高熵二进制不会被笼统排除。
59. 脚本、日志、下载和测试产物不会出现在根目录，职责边界目录具有准确 README。
60. 参考工程按独立包装和内容清单导入，不会自动成为目标、源组或发布对象，原快照保持不变。
61. 任务参考副本具有来源、临时私有 Git 基线和清理条件，且不会参与用户工程发布。
62. Agent 只按任务需要读取相关参考工程，不因参考目录增大而加载全部代码。
63. 产品定义、当前方案、开发路线、决策和版本边界进入职责明确的 `project-docs/`。
64. 未确认的 workstream 结论不会成为项目事实，新决策替代旧决策时保留关系。
65. 约束升级展示只读计划；未确认、拒绝、取消或部分确认时整个操作零写入。
66. 确认后的规则升级归档旧根规则，并为 Agent 管理 Git 和受影响的源组私有 Git 创建检查点；用户 Git 不会被自动提交。
67. 日常事实更新不会夹带进待确认迁移，也不会在用户明确只读时发生。
68. 仅刷新事实的重新扫描保持幂等；发现结构、策略、映射或 schema 迁移时整次转入计划模式。
69. `recovery-backup` 原样保存本机状态，`agent-import` 才过滤缓存和敏感内容，两种策略不混用。
70. 每份迁移备份有唯一 ID，通过 `last_notified_backup_id` 每份只提醒一次且永不自动删除。
71. `USER_GUIDE.md` 能在不了解内部脚本的情况下解释唯一工作区入口、三套 Git、双基线、同步和恢复。
72. 没有日常开发 Skill 时，普通 Agent 仍能找到运行期脚本、配置、项目文档模板和任务状态。
73. 初始化不会修改业务源码、修复基线错误、安装工具、烧录硬件或强制完整测试体系。
74. 没有真实内容时不会生成空的 PRODUCT、SOLUTION 或 ROADMAP 正文。

## 已明确删除或暂缓的设计

- 不使用专用账户、ACL、虚拟机或独立高权限 Publisher 做强隔离。
- 不承诺 Agent 在技术上绝对无法写用户工程。
- 不提供把 Agent 管理内容嵌入用户工程的兼容模式。
- 不把 integration 或 linked worktree 单独作为 Codex 项目，也不向其中额外生成 Agent 规则文件。
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
- 用户工程与纯净 Agent 工作区始终是两个互不包含的真实目录；Codex 日常任务只从 Agent 工作区根启动。
- 用户日常交互可以压缩为“提出任务、Agent 在副本工作、明确要求时发布”。
- 用户工程 Git、Agent 管理 Git、源组私有 Git、workstream 和同步方向始终不会在文档或实现中混淆。
- 多权威源、多 MCU 和多对话并行均能被同一模型表达。
- 已有用户工程可以无损导入外部 Agent 工作区，旧 Agent 工作区可以经确认迁移；参考工程与权威源、集成副本和 workstream 的职责始终清晰分离。
- 未确认的已有工作区迁移或约束升级不会产生任何写入；确认后的变化可验证、可审计、可回滚。
- 用户同步基线、workstream 任务基线和构建基线职责分离，发布只包含冻结任务提交和显式依赖。
- 活跃 Agent 工作区只保留一个根 `AGENTS.md`；旧规则可追溯但不再生效。
- 复杂机械操作由已验证脚本完成，规则文档保持精简。
- 发生冲突时停止覆盖；发生可恢复故障时存在基线或快照。
- 所有事实性成功声明都有对应验证证据。
- 实际 Skill 使用 `quick_validate.py` 通过结构与元数据检查。
