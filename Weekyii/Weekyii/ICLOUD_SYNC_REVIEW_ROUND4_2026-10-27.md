# Weekyii iCloud 同步能力审查（第四轮）

审查日期：2026-10-27
基线：`28149dd`（`notion-claude/feat-in-app-purchase`），工作区含未提交的主题改动（与本审查无关）
方式：**只读**。未改任何源码。所有判定以代码行号为据；文档只用于确定"要求是什么"。
上一轮审查（`ICLOUD_SYNC_REVIEW_ROUND3_2026-09-20.md`）的结论**已整体作废** —— persistence 层已被重写，旧的 `StoreMode` 四态、`syncedWritesAllowed` 闸门、`cloudDetached` 只读副本、SwiftData↔CloudKit 镜像全部不存在了。

---

## 0. 结论摘要

**架构换对了，主干是干净的。** 现在只有一条同步路径：SwiftData 本地库（`cloudKitDatabase: .none`）+ 显式 CKSyncEngine 复制层 + VIP 门禁。产品不变量 R1（本地永远可写）、R2（单一 store）、R3（SwiftData 永久 local-only）、R4（默认关闭）、R5（资格与意图分离）、R10（同步状态不得成为写闸门）在代码里逐条能对上，且比上一版严格。

**但"能不能同步"和"同步本身对不对"是两件事。** 本轮找到 4 项高、6 项中、6 项低的问题，集中在四个面：

1. **同步会永久卡死，且没有出口**：一条读不懂的远端记录（版本不一致/字段畸形）或一条"远端已删、本机改过"的冲突记录，会把整个同步 latch 成终止失败；手动"立即同步"会重复同一条失败，永远出不来。
2. **本地恢复/归档导入与同步完全没协调**：用归档"完整替换"数据后，下一次同步会把云端多余记录**全删**，而 UI 只提示"导入不会合并数据"，没有任何 iCloud 相关警告。
3. **性能随附件量线性爆炸**：一次 reconcile 对每个"远端获胜"实体都重读一遍**整库快照（含全部附件字节）**，千级实体 + 百 MB 附件就是 GB 级内存搬运。
4. **习惯任务跨设备会重复**：习惯"日记录"有语义收敛（`(habitId, dayId)` 去重），但由它生成的 `TaskItem` 没有 —— 两台设备同日各自物化，合并后用户看到两条一样的习惯任务。

用户状态覆盖是**完整**的：无账号、受限、无空间、离线、账号切换、订阅到期/退款、Beta、双设备并发、新设备首同步都有明确分支与文案。**只有"资格到期"缺一个续订入口，"首次开启待决策"在首页不可见。**

---

## 1. 当前架构（事实）

| 项 | 实现 | 证据 |
|---|---|---|
| 本地库 | 唯一 `Application Support/Weekyii/Weekyii.store` | `WeekyiiPersistence.swift:148-153` |
| SwiftData ↔ CloudKit | 永久 `.none` | `WeekyiiPersistence.swift:118-126`、`:135` |
| StoreMode | 只剩 `.persistent` / `.inMemory` | `WeekyiiPersistence.swift:6-9` |
| 同步层 | 显式 `CKSyncEngine`，自动调度关闭 | `CKSyncEngineTransport.swift:6-7`、`:56-69` |
| 云结构 | 私有库固定 zone `WeekyiiSyncZoneV1`、recordType `WYEntityV1` | `CloudRecordCodec.swift:136-137` |
| 记录身份 | `SHA256(kind,businessId)` → `wy1_<hex>`，与 SwiftData 解耦 | `CloudRecordCodec.swift:49-66` |
| 同步默认 | 关闭（旧 `cloudSyncEnabled` 不迁移成开启） | `UserSettings.swift:269-279` |
| 资格 | StoreKit 2 已验证交易，每次现查 | `CloudSyncEntitlementService.swift:10-14` |
| 写闸门 | 业务层不再查询任何同步状态 | 全仓无 `syncedWritesAllowed`（grep 零命中） |

**强项（不建议动）：**
- 失败即闭（fail-closed）：`entitlementState` 初始 `.entitled` 只影响一帧；`handle` 每次重查资格（`CloudSyncCoordinator.swift:583-589`）。
- 身份切换用**设备本地日志（journal）+ generation** 双保险，且 journal 只存哈希（`CloudSyncMetadataStore.swift:175-211`）。
- 元数据原子写 + `flock` 账户级事务（`:252-265`、`:297-309`）。
- 引擎游标与 reconcile 游标分离的**持久 inbox**（`:329-403`），解决"引擎提交了但没消费"的丢事件问题。
- 远端获胜前**逐条重读本地**再应用，避免覆盖同步期间的编辑（`CloudSyncReconciler.swift:136-172`）。

---

## 2. 用户状态矩阵

判定口径：**本地可用**=无需任何云条件即可写；**同步**=该状态下同步的实际行为。

| # | 用户状态 | 本地可用 | 同步行为 | 用户看到 | 证据 | 判定 |
|---|---|---|---|---|---|---|
| 1 | 新装、未开同步（默认） | ✅ | 完全不入云，不查账号 | 设置页"已关闭" | `UserSettings.swift:269-279`；`CloudSyncCoordinator.swift:508-511` | ✅ 符合 R4 |
| 2 | 有 VIP、未开同步 | ✅ | 同上 | 同上 | 同上 | ✅ |
| 3 | 无 VIP / 已过期 / 退款 / 收据校验失败 | ✅ | 开关被 paywall 拦；协调器二次拒绝 | "同步已暂停：VIP 未开通或已到期" | `SettingsView.swift:905-913`；`CloudSyncCoordinator.swift:449-452`、`:479-481` | ⚠️ 缺续订入口（见 M5） |
| 4 | 未登录 iCloud | ✅ | `.accountUnavailable`，不上传不下载 | 首页横幅"账户暂不可用，同步已暂停" | `CloudSyncCoordinator.swift:604-616`；`ContentView.swift:197` | ✅ |
| 5 | iCloud 受限（MDM / 家长控制） | ✅ | 同上（`restricted`） | 同上 | `:607-609` | ✅ |
| 6 | iCloud 空间不足 | ✅ | `.quotaExceeded` + latch | "iCloud 空间不足。本机数据仍正常保存。" | `:1709-1710`；catalog `settings.icloud.banner.quota` | ✅ 符合 R6 |
| 7 | 离线 | ✅ | `.offline` + latch；恢复网络自动重试一次 | "本机数据正常保存；iCloud 同步暂时不可用。" | `:1707-1708`、`:1829-1840`；`CloudSyncNetworkMonitor.swift:97-118` | ✅ 符合 R7 |
| 8 | `couldNotDetermine` 临时不可用 | ✅ | 归入 `.accountUnavailable` | 与"未登录"同文案 | `:610-612` | ⚠️ 语义混同（L3） |
| 9 | 同步开启时换 Apple ID | ✅ | 先停云 → 存 journal → 弹四选 | "iCloud 账户已更改…" | `:598-601`、`:1322-1382`；`ContentView.swift:318-364` | ⚠️ 默认按钮会清空新账户云端（M4） |
| 10 | 同步关闭时换 Apple ID | ✅ | 零影响，不查账号 | 无任何提示 | `:508-511`（先判 requested） | ✅ 符合 R8 |
| 11 | 首台设备首次开启（云端空） | ✅ | 上传本机 | 询问"上传/取消" | `:1176-1183`；`SettingsView.swift:190-194` | ✅ |
| 12 | 新设备（云端非空） | ✅ | 四选：本机/云/合并/取消 | 数量对比 + 空云端警告 | `:714-742`；`SettingsView.swift:195-199` | ✅ |
| 13 | 订阅中途到期 | ✅ | 会话失效，本地/云端都不动，意图保留 | "同步已暂停…" | `:468-482` | ⚠️ 无端到端测试、无续订按钮 |
| 14 | 订阅续费/恢复 | ✅ | `.entitlementRestored` 恢复一次 | 状态回到已同步 | `:473-478` | ✅ |
| 15 | 双设备并发编辑同一实体 | ✅ | 本机优先，冲突计数但不上报 | 无提示 | `CloudSyncReconciler.swift:399-432` | ⚠️ 静默丢远端编辑（L5） |
| 16 | 从恢复点/归档恢复 | ✅ | **不暂停**，下次同步按本地为权威推平云端 | 仅"恢复完成" | `DataArchiveService.swift:186-218`；`SettingsView.swift:1110-1126` | ❌ 高危（H2） |
| 17 | 后台静默推送唤醒 | ✅ | 冷启动无 scene 时不执行，只记 pending | 无 | `WeekyiiAppDelegate.swift:23-43`；`WeekyiiApp.swift:694-707` | ⚠️ 后台不生效（M6） |
| 18 | 从旧版本升级（曾开过同步） | ✅ | 同步变关闭，需重新开启 | 无迁移提示 | `UserSettings.swift:274-279` | ⚠️ 静默降级（L4） |
| 19 | 两台设备 App 版本不一致 | ✅ | **旧版本永久卡死** | "同步已暂停" | 见 H1 | ❌ 高危 |
| 20 | 一台设备删除、另一台离线编辑 | ✅ | 可能永久 latch | "同步已暂停" | 见 H1 | ❌ 高危 |

---

## 3. 高优先级问题

### H1【高】一条异常记录可以让同步永久卡死，且没有出口

三条路径都落到同一个结果：`latchFailure` → `automaticRetrySuppressed = true` → 只有手动同步能清 → 手动同步重复同一失败。

**(a) 前向不兼容。** `CloudRecordCodec.decode` 强制 `record.payloadVersion == payloadVersion(for: kind)`（`CloudRecordCodec.swift:238-240`），而当前所有 kind 都固定为 `1`（`:139-152`）。旧版本 App 读到新版本写的 v2 记录 → 抛 `unsupportedPayloadVersion` → `CloudKitRecordAdapter.decode` 抛 `malformedField` → `CKSyncEngineTransport.handleEvent` 把 `fetchFailure` 置为 `.invalidArguments`（`CKSyncEngineTransport.swift:188-192`）→ `fetchChanges` 直接抛出（`:124`）→ 终止失败 → latch。**注意：这不是"跳过这一条"，而是整轮 fetch 失败**，于是同账户的所有设备都停摆，直到旧设备升级。

**(b) 未知字段/畸形记录同理。** 任何 `decode` 失败都升级为整轮失败，没有"隔离坏记录、继续处理其余"的路径。

**(c) 远端删除 + 本机编辑。** 冲突时本机获胜（`CloudSyncReconciler.swift:421-427`），上传时沿用**已被删除记录的 system fields**：`:212-215` 取 `entityBaselines[key].serverMetadata`，而该 baseline 在"远端删除、本机也删"时才会被清（`:296-298`），冲突场景下保留。若 CloudKit 因此返回 `serverRecordChanged`，重发逻辑只在 `batch.nextToken` 之后找该 key 的 upsert（`:245-250`），删除事件在 token 之前，找不到 → `continue` → 该记录保持 `.failed`；若是 `unknownItem`，`CloudKitFailureMapper` 根本没有这个 case（`CloudKitRecordAdapter.swift:195-217`）→ `.other("CloudKit request failed (11)")`。两条都非 transient（`CloudSyncRetryPolicy.swift:33-55`）→ latch。

**为什么测试没抓到**：`InMemoryCloudSyncTransport.upsert` 直接把记录写进字典，**完全不校验 change tag / system fields**（`CloudSyncTransport.swift:195-208`），所以 `test_remoteDeleteWithLocalEditRecreatesRemoteAndPreservesLocal`（`CloudSyncETests.swift:102-116`）验证的是"业务意图"，不是"真实 CloudKit 会不会接受"。

**建议**（任一即可，但必须选一个）：
- 在 `reconcile` 里把"单条 decode 失败"降级为 per-record failure + 跳过，不污染整轮 fetch；
- `CloudKitFailureMapper` 补 `.unknownItem` → `.serverRecordChanged`（语义：记录已不存在，清 baseline 后按新建重传）；
- 给用户一个"重置此设备的同步状态"出口（清 metadata + 重新 inspect），否则任何 latch 都是死路。

### H2【高】归档导入 / 恢复点恢复与同步零协调，会静默推平云端

`WeekyiiDataArchiveService.importReplacing` 删除全部业务数据再写入归档内容（`DataArchiveService.swift:198-205`），**全程不接触 `CloudSyncCoordinator`**；`SettingsView` 调用点也只提示"恢复完成"（`SettingsView.swift:1110-1126`）。恢复点恢复同理（`SettingsView.swift:148`、`:3330`）。

后果：下一次同步里，本地缺失的每个实体都会被当作"本机删除"，作为 `deletesToSend` 推到云端（`CloudSyncReconciler.swift:206-220`、`:277-299`）。用户以为在"救回本机数据"，实际是把另一台设备上更新的一切从 iCloud 删掉。归档页脚只写了"导入不会合并数据"（`SettingsView.swift:983`），一个字都没提 iCloud。

**建议**：这两条路径在执行前调用 `coordinator.setRequested(false)`（或专门的 suspend），完成后提示"重新开启同步将以本机数据为准"，让用户显式确认"云端会被覆盖"。这是**产品语义**问题，不能只靠恢复点兜底 —— 恢复点只保护本机。

### H3【高】reconcile 的复杂度是 O(远端获胜条数 × 整库)，且每次把全部附件读进内存

`CloudSyncReconciler.reconcile` 对每个 remote-winner key 都做一次 `localStore.currentSnapshot()`（`CloudSyncReconciler.swift:142-156`），循环外又读两次（`:91-93`、`:160-162`）。而 `currentSnapshot()` = `WeekyiiSnapshotRepository.requireCleanSnapshot`（`CloudSyncLocalStore.swift:18-20`）→ 全表 fetch，**包含 `TaskAttachment.data`（`.externalStorage`）和 `MindStampItem.imageBlob` 的完整字节**（`WeekyiiSnapshotRepository.swift:115-124`、`:444-461`；`TaskAttachment.swift:7`）。

首次同步 1000 条远端记录 = 1000 次全库快照，每次携带全部附件字节。100 MB 附件就是 100 GB 级内存搬运，必然卡死或 OOM。即使没有附件，1000 次全表 fetch + 每次全实体 canonical JSON 编码（`:527-529`）也远超可接受。

**建议**：把"逐条重读"改成一次快照 + 每次 apply 前只读**该 key 的单行**（按 `dayId`/`id` 定向 fetch）；`currentSnapshot()` 增加"只要元数据不要 blob"的重载，blob 仅在真正上传该实体时按需读取。这是**结构性**问题，不是调参能解决的。

### H4【高】同步层没有 forward-compat 策略，也没有"未知记录"隔离区

与 H1(a) 同源，但值得单列：`CloudRecordCodec` 的 `payloadVersion` 机制存在，却没有配套的**降级读取**（读不懂就跳过并记账）或**版本协商**。一旦引入 v2 payload（这是计划 §8.1 明确允许的演进方式），所有未升级设备会立刻停摆。计划里"什么时候才考虑 `WeekyiiSyncZoneV2`"（§8.1）只讨论了 zone 版本，没讨论**同一 zone 内混版本**的共存规则。

**建议**：把"decode 失败"定义成 per-record 隔离 + 诊断计数，而不是整轮失败；并在设计文档里补一条"同一 zone 必须容忍未知 payloadVersion 至少一个大版本"。

---

## 4. 中优先级问题

### M1【中】`apply` 保存失败不回滚，可能把半套数据留在内存里等下一次 save 落盘

`SwiftDataCloudSyncLocalStore.apply` 末尾 `if context.hasChanges { try context.save() }`（`CloudSyncLocalStore.swift:197`），抛错直接上抛，**没有 `rollback()`**。对比 `HabitTaskMaterializer.sync` 是有 rollback 的（`HabitTaskMaterializer.swift:130-138`）。同步路径上任何后续 `save()`（用户一次普通编辑）都会把这次半应用的图落盘，然后下一轮 reconcile 会把它当成"本机新状态"上传。

**建议**：`apply` 用 `do/catch` 包住，失败 `rollback()` 后再抛。

### M2【中】习惯任务跨设备重复物化

- 习惯是否已处理今日，判据是**日记录**（`HabitModel.swift:120-122`，`hasProcessed` 读 `records`），而记录是同步的 —— 这一步设计正确，且远端 `(habitId, dayId)` 重复记录有确定性收敛（`CloudSyncReconciler.swift:452-492`）。
- 但由记录伴随生成的 `TaskItem` 用的是**随机 UUID**（`TaskPostponeService.swift:73-79` 走 `TaskItem(...)` 默认 id），同步层对 `task` 没有任何语义去重。

于是：两台设备在同一早晨各自物化（`HabitTaskMaterializer.swift:187-234`），合并后 `day.tasks` 里有两条同名习惯任务，永久存在（`contains(where: habit.id)` 只挡第三次）。

**建议**：要么给习惯任务确定性 id（`UUIDv5(habitId, dayId)`），要么在 reconcile 里加一条 task 语义收敛（同 `habitId` + 同 `dayId` + 同 zone 取一）。

### M3【中】账户切换的"使用此设备的数据"会清空新账户的云端，但它是视觉主按钮

`resolveAccountSwitch(.useLocal)` 执行 `resetCustomZone()` 再上传本机（`CloudSyncCoordinator.swift:941-955`），即**删掉新 Apple ID 下的全部 Weekyii 云数据**。而 UI 里它是 `.borderedProminent`（`ContentView.swift:320-328`），标签"使用此设备的数据"听起来最安全；反而"使用新 iCloud 数据"被标成 destructive（`:330-338`）。两个都是破坏性的，只有后者被标出来。

`emptyCloudWarning` 只在**新账户云端为空**时出现（`ContentView.swift:238-247`），恰恰是唯一无损的情况。

**建议**：`.useLocal` 加 destructive 标注或二次确认；在云端非空时明确写"将删除新 iCloud 账户中的 N 项 Weekyii 数据"。

### M4【中】"订阅到期"没有续订入口

计划 §27 要求"提供续订入口"（`docs/plans/2026-09-21-...:2060`）。代码里只有 `settings.icloud.status.locked` 一句文案（"同步已暂停：VIP 未开通或已到期，本地数据不受影响"），同步分区内**没有任何购买/续订按钮**。用户唯一路径是把开关关掉再打开，才会触发 paywall（`SettingsView.swift:908-910`）—— 而"关掉再打开"对一个已经到期的用户来说是反直觉的。

### M5【中】后台静默推送在无 scene 时不生效，Widget 只在 App 运行时更新

`appDelegate.attach(coordinator:)` 在 `ContentView.task` 里调用（`WeekyiiApp.swift:694-707`），即需要界面存在。冷启动的后台唤醒路径里 router 没有 handler，只记 `pendingBeforeAttachment` 并立刻回调 `.noData`（`CloudRemoteNotificationRouter.swift:137-141`）。没有 `BGTaskScheduler` 兜底（全仓零命中）。

后果：另一端改数据 → 本机后台收到 push → 什么也不做 → Widget / 通知 / Live Activity 保持旧值，直到用户主动打开 App。计划 §30 的意图是"push 触发一次受控 sync"，这一条只在 App 有 scene 时成立。

### M6【中】"首次开启待决策"状态在首页完全不可见

`CloudSyncDiagnosticsSnapshot.bannerKind` 没有 `.initialEnableDecisionRequired` 分支（`CloudSyncTypes.swift:108-124`），首页横幅只在 quota/paused/offline/accountUnavailable/locked/syncing/accountDecision 出现。而这个决策的 alert 挂在 **SettingsView** 上（`SettingsView.swift:186-204`、`:48-57`）。

于是：用户开启同步后杀掉 App → 重启 → 状态停在"待决策"→ 首页无任何提示、同步静默不动，只有进设置页才看到"处理"按钮。

---

## 5. 低优先级 / 记录

- **L1** `resolveInitialEnable` 的 `switch` 漏了两个组合：`(.remoteEmpty, .useLocal)` 与 `(.remoteNonempty, .uploadLocal)` 落到 `default: return`（`CloudSyncCoordinator.swift:743-745`），此时 `status` 已置 `.syncing`（`:645`），会永久停在"正在同步"。当前 UI 不会产生这两个组合（`SettingsView.swift:190-199`），但这是可被任意调用方触发的陷阱。
- **L2** `attach` 只看 `cloudSyncRequested` 就把状态置 `.ready`，不看资格（`CloudSyncCoordinator.swift:429-431`）。重新启动时非 VIP 用户会有一瞬间看到"就绪"，随后被 `handle(.appLaunch)` 纠正为 `.locked`。
- **L3** `couldNotDetermine` / `temporarilyUnavailable` 与"未登录"共用 `.accountUnavailable` 文案（`CloudSyncCoordinator.swift:610-616`），用户会被引导去"检查账户"，而实际问题可能只是网络抖动。
- **L4** 旧版本 `cloudSyncEnabled = true` 的用户升级后同步静默变关闭（`UserSettings.swift:274-279` 只写了迁移标记，不迁移值），没有任何提示。对"曾经用过同步"的人是功能倒退的观感。
- **L5** 冲突只计数不呈现：`CloudSyncReconciliationReport.conflicts`（`CloudSyncReconciler.swift:14`）在协调器里只用于判定成功与否（`:1226-1238`），从不显示。双设备同时编辑时，远端那份编辑**静默消失**，用户无从得知。
- **L6** `CloudSyncPreferenceController`（`CloudSyncEntitlementService.swift:26-47`）只有测试在用，生产零调用点；且它的默认 provider 是 `OpenAccess`（无门禁），放在生产代码里是个容易被误用的入口。
- **L7** `ContentView` 把 `.id(appState.dataRevision)` 挂在 `TabView` 上（`ContentView.swift:76`），而远端应用会 `bumpDataRevision`（`WeekyiiApp.swift:698`）。每次拉到远端数据，所有 tab 的导航栈/滚动位置被重置。首次大同步期间会连续发生。

---

## 6. 文档 / 运维缺口

**`docs/icloud-sync-runbook.md` 描述的是已废弃的架构，会误导上线操作：**

| runbook 说法 | 现状 |
|---|---|
| "SwiftData 正在导入或导出 CloudKit 变更"（:37） | 已改为 CKSyncEngine 显式同步 |
| 用 `-initializeCloudKitSchema` 初始化 schema（:19） | **该启动参数在全仓已不存在**（grep 零命中） |
| "Record Types 已由 SwiftData 创建"（:20） | 现在是自定义 zone `WeekyiiSyncZoneV1` + `WYEntityV1` |
| "应用启动时先收敛 CloudKit 重复周/日期…"（:41） | 已改为启动时只做本地 repair，云端收敛在 reconcile |

**上线前必须确认（代码里没有任何检查或友好报错）：**
1. CloudKit **production** 环境已部署 `WYEntityV1`。开发环境由 CKSyncEngine 自动建 schema，生产不会。未部署时所有写入失败，而 `CloudKitFailureMapper` 会把 `invalidArguments` / `missingEntitlement` 归为 `.badContainer`（`CloudKitRecordAdapter.swift:205`），用户只看到"此设备上的 iCloud 同步目前不可用"（catalog `cloud.sync.failure.configuration`）—— 无法定位。
2. `WYEntityV1` 在 production 允许 `CKQuery`（`CloudKitInfrastructureManager.inspect` 用 `NSPredicate(value: true)` 全量查询，`CloudKitInfrastructureManager.swift:127-142`）。这条查询在**首次开启决策**和**账号切换**的必经路径上，失败即整个流程失败。
3. zone 订阅 `WeekyiiSyncZoneV1-subscription-v1` 在真实账号下创建成功（`CloudKitInfrastructureManager.swift:16`、`:33-39`）。
4. `aps-environment` 仍是硬编码 `development`（`Resources/Weekyii.entitlements:5-6`），依赖描述文件覆盖 —— 第二轮已验证归档产物为 production，但每次改签名配置都要重新验证。

---

## 7. 测试覆盖评估

**规模**：`CloudSyncCoordinatorTests` 52 例、`CloudSyncETests` 21 例、`CloudSyncD1Tests` 21 例、`CloudSyncD2Tests` 11 例、`CloudSyncNetworkMonitorTests` 5 例，合计 110 例，质量整体高（会话失效、取消、崩溃恢复、journal 重放、partial failure、blob 独立通道都有）。

**缺口（按风险排序）**：
1. **真实 CloudKit 语义**：`InMemoryCloudSyncTransport` 不校验 change tag、不产生 `serverRecordChanged`/`unknownItem`（`CloudSyncTransport.swift:195-222`）。"远端删除 + 本机编辑"、"版本不一致"两条路径从未在真实行为下验证过（见 H1）。
2. **资格失效端到端**：唯一相关用例只断言 `entitlementState` 被更新（`ModelTests.swift:2752-2764`），没有断言"进行中的 cycle 被中止"、"local store 未被写"、"续订后能恢复"。
3. **后台推送**：`CloudRemoteNotificationRouterTests` 只测合并与完成回调，不覆盖"无 handler 的冷启动后台唤醒"。
4. **导入/恢复与同步交互**：零用例（H2）。
5. **性能**：无任何针对大库/多附件的基准（H3）。
6. **前向兼容**：`CloudRecordCodec` 有 `unsupportedPayloadVersion` 的单元测试（`CloudSyncD1Tests.swift:134`），但只断言"抛错"，没断言"同步不应因此整体停摆"。

---

## 8. 建议处置顺序

| 顺序 | 事项 | 类型 | 理由 |
|---|---|---|---|
| 1 | H1：单条坏记录不得污染整轮；补 `unknownItem` 映射；给"重置同步状态"出口 | 改代码 | 现在任何一个异常都能让同步永久死亡，且用户无法自救 |
| 2 | H2：归档导入 / 恢复点恢复前暂停同步并明确告知"将覆盖云端" | 改代码 | 静默删云是数据事故级 |
| 3 | H3：把 reconcile 的"逐条全库快照"改成"一次快照 + 定向单行读取"，blob 按需 | 改代码 | 附件用户必然踩到，且不可通过调参缓解 |
| 4 | 上线前三件事：production schema 部署、`WYEntityV1` 可查询、订阅创建 | 运维 | 缺一项就是"上线即失败"，且错误信息不可定位 |
| 5 | M1 `apply` 回滚、M2 习惯任务确定性 id | 改代码 | 数据正确性，改动小 |
| 6 | M3 `useLocal` destructive 标注、M4 续订入口、M6 首页提示"待决策" | 改 UI | 误操作与可发现性 |
| 7 | M5 后台同步（BGTask 或接受并写进文档） | 决策 | 要么补，要么明确"后台不保证" |
| 8 | 更新 `docs/icloud-sync-runbook.md` 到 CKSyncEngine 架构 | 改文档 | 现在这份会误导上线操作 |
| 9 | L1–L7 | 清理 | — |

---

## 9. 未验证 / 边界

- 所有结论来自静态阅读，**未跑构建与测试**（本轮为审查，不改代码）。真实 CloudKit 行为（H1c、schema 部署、查询权限）需要真机 + 真账号验证。
- 未验证 `CKSyncEngine` 在"保存一条已删除记录"时具体返回哪个 `CKError`（`serverRecordChanged` 还是 `unknownItem`）；两种都落到同一个 latch，结论不变。
- 未实测附件库下的内存峰值（H3 的量级是算术推导：快照次数 × 附件总量）。
- 未评估 Apple 审核对"iCloud 同步作为付费功能"的态度（产品/合规问题，非代码问题）。
