# Weekyii iCloud 同步收敛方案 —— 第三轮完整审查

审查对象：`docs/plans/2026-09-19-icloud-sync-convergence.md`（v3.2，1852 行）所描述的全部开发任务
审查日期：2026-09-20
审查方式：**以代码仓库为唯一真相源**。文档自述只用于确定"要求是什么"，任何"已完成"的判定均以代码行号为据，不以文档状态行为据。
构建基线：`WeekyiiTests` 255/255、`WeekyiiUITests` 20/20（`/tmp/weekyii_final_unit.log`、`/tmp/weekyii_ui2.log`，2026-09-20 02:08）

---

## 0. 结论摘要

**方案主体已落地且设计质量高。** 四态 `StoreMode`、单一闸门 `syncedWritesAllowed`、两阶段启动、`cloudDetached` 进程级只读副本、身份护栏与三选决策，这些承重结构在代码里都能逐行找到对应实现，且部分实现优于文档描述。

**发现 9 项文档与代码不一致，其中 3 项是实质性缺口**（不是"文档没更新"那么轻）：

| 严重度 | 项 | 影响 |
|---|---|---|
| **高** | §8.1 Phase F 水位线改推导**未落地** | 文档状态行声称"F 已实现"，代码仍是存储 String + LWW 回退。§13.7 对应验收断言无着落 |
| **高** | §6 D1 `validateContainerConsistency` 护栏**未落地** | 文档要求"失败不阻断启动"，代码仍 `throw` → `.failed`。且该缺口被引导期 repair 掩盖，从未被测试检验 |
| **高** | §4.4 引导期 repair 未按文档删除 | `.production` 容器仍在 CloudKit 首次导入前做一次全库归一化（§1.6 想消除的问题在该档残留） |
| 中 | 冷启动每次必调 `userRecordID()` 网络往返 | 文档 §7.2.3 ② 提出的"快速判定短路"未实现，有账号设备冷启动必然多一次网络等待 |
| 中 | `settlement()` 在 SwiftUI body 热路径上被调用，且含 UserDefaults 读写 | 见 §5.2 |
| 中 | 新增 UI 文案大量硬编码中文，未走 `String(localized:)` | 英文用户看到中文；与项目既有 i18n 约定不符 |
| 低 | §4.8 `.remoteImport` 未新增 | 无安全影响，但文档三处（§4.8/§4.9/§13.2）留悬空待办 |
| 低 | §7.1.1 无参 `persistentStoreURL()` 未删 | 死代码 |
| 低 | GC 注释缺 #20 五条强制表述 | §13.6 明列为交付检查项 |

---

## 1. 逐 Phase 落地核查

判定口径：**已落地** = 代码行为与文档要求一致；**等效替代** = 行为达成但实现路径不同；**偏离** = 行为与要求有实质差异；**未落地** = 找不到对应实现。

### Phase A（终态契约 + 停止删除）—— 已落地

| 文档要求 | 代码证据 | 判定 |
|---|---|---|
| §3.1 删除修复侧 `closedAt` 回填 | `StateMachine.swift:690-751` `normalizeStatus` 三级判据：`closedAt != nil → .completed`；`status == .expired → 保持`；其余按 zone 派生。**全文件无 `closedAt = now`**；写入点收敛到 `TodayViewModel.swift:276`、`TaskPostponeService.swift:439/454` | 已落地 |
| §3.2 getter 门控 + raw 保留 | `DayModel.swift:43-56` 三个 getter 带 `guard !isTerminal`；`:58-60` `completedTasks` **不门控**（红线 1）；`:34-37` `tasks` raw（红线 2）；`:70-72` `isTerminal` 为计算属性不入 schema | 已落地 |
| §3.2 `expire` 停止删除 | `StateMachine.swift:296-303` 只写 `status/expiredCount/isDraftZoneUnlocked`，**无 `modelContext.delete`**；`removeTasks` 已整体删除 | 已落地 |
| §3.3 `doneFocus` 闸门期降级 | `TodayViewModel.swift:274-276` `if allowsSyncedWrites() { day.status = .completed; day.closedAt = now }` | 已落地 |
| §3.3 `TaskPostponeService` 同构降级 | `TaskPostponeService.swift:437-440`、`:452-455` 两处均包在 `if allowsSyncedWrites()` 内 | 已落地 |
| §3.3 "正在同步确认"文案 | `TodayViewModel.swift:43-49` `isAwaitingSyncConfirmation`；`TodayView.swift:661-662` 渲染；i18n 键 `today.done.awaiting_sync` 在 `Localizable.xcstrings:7013-7025` 有 en + zh-Hans | 已落地 |
| §3.4 SettingsView 内联删除 | `SettingsView.swift:2001-2007` 只写 `status/.expiredCount/.isDraftZoneUnlocked` + 取消通知，**无 delete** | 已落地 |
| §3.6 测试断言审计（强制交付项） | `ModelTests.swift:629` 起 `test_terminalDay_hidesOpenZonesWithoutDeletingRawTasks` 用 raw 形式断言 | 已落地 |
| §3.7 GC | `StateMachine.swift:411-439` `TaskGarbageCollector`：`retentionWeeks` 默认 8、`max(retentionWeeks, 2)` 硬下限；只删 `.expired` 且 `dayId < cutoffDayId` 的 draft/focus/frozen；不删 DayModel、不删 complete；用 `WeekyiiTimeZone.calendar` | 已落地（注释缺 #20 表述，见 §2.9） |

**附带发现（A 的一个小洞）**：`SettingsView.swift:2001` 的"改 kill time 立即过期"路径**没有闸门检查**。它在 `cloudDetached` 下会走到 `today.status = .expired`，而只读容器的 `save()` 会抛错。属于用户显式动作，文档 §3.4 也未要求加闸门，但它在闸门关闭时仍试图写终态语义，值得记一笔。

### Phase B0（容器模式解析）—— 已落地，2 处偏离

| 文档要求 | 代码证据 | 判定 |
|---|---|---|
| §4.2.2 `StoreMode` 第四态 + 派生属性 | `WeekyiiPersistence.swift:17-49`：`production/localOnly/cloudDetached/inMemory`；`hasNoRemotePeer`（`:32-39`）；`allowsSave`（`:41-48`） | 已落地 |
| §4.2.2 `resolveStoreMode` 映射表 | `:119-141`：XCTest → `.localOnly`；`!cloudSyncEnabled` → `.localOnly`；`!identityConfirmed` → `.cloudDetached`；`.available → .production`；`.noAccount/.restricted → .localOnly`；`.temporarilyUnavailable/.couldNotDetermine/nil → .cloudDetached`。**逐行符合 §13.2.0 的 10 行映射表** | 已落地 |
| §7.2.3 ① `LaunchState.resolving` | `:51-55` | 已落地 |
| §7.2.3 ② 阶段 1 异步解析 | `WeekyiiApp.swift:706-762` `resolveAndBootstrapPersistentContainer()`；`init()` 只赋 `.resolving`（`:583`） | 已落地 |
| §7.2.3 ③ 两条重试路径传 storeMode | `WeekyiiApp.swift:687`、`:697-700` 均显式传 `resolvedStoreMode`；`persistentStoreURL(for:)` 同步传模式 | 已落地 |
| §7.1.1 路径分离 + 9 处调用点 | `:252-262` `persistentStoreURL(for:)`；`.localOnly → Weekyii.local.store`；全部调用点显式传模式（`WeekyiiApp.swift:676/691/781/784`、`SettingsView.swift:126/868/874/904/928/938/1119/1265/3015/3022`） | 已落地 |
| §7.2.2 `cloudDetached` 只读副本 | `:179-201` + `:224-250` `makeDetachedReadOnlyCopy`：复制 `.store/-wal/-shm` 到 `Caches/Weekyii/DetachedStores/<pid>/`，以 `allowsSave: false` 打开副本；无源文件时退化为内存只读容器 | **优于文档**（文档只说"复制到临时目录"，实现还处理了"文件不存在"的新设备场景） |
| §4.4 删除引导期 repair | `:158-161` **保留** `seed + repair`，仅加 `if resolvedMode.allowsSave` 守卫 | **偏离**（见 §2.1） |
| §4.11 第一步 播种移出 `makeModelContainer` | `:170-222` `makeModelContainer` **内无任何 seed 调用**；播种在 `:159`（bootstrap 内） | 已落地（落点与文档不同，见 §2.3） |
| §6 D1 `validateContainerConsistency` 护栏 | `:490-497` 仍 `throw`；`:162` 用 `try` 包着 → 抛错即 `.failed` | **未落地**（见 §2.2） |

### Phase B（同步静止闸门）—— 已落地，1 处偏离

| 文档要求 | 代码证据 | 判定 |
|---|---|---|
| §4.2.1 四态结算 + 单一谓词 | `CloudSyncMonitor.swift:300-361` `settlement(storeMode:now:)`；`:363-373` `syncedWritesAllowed` 只在 `noRemotePeer`/`settled` 放行 | 已落地 |
| §4.2.1 `cloudDetached` 恒 `unsettled` | `:307-309` `guard storeMode == .production else { return .unsettled(.containerNotLoaded) }` —— 注意它先于 `hasNoRemotePeer` 判断，所以 `cloudDetached` 不可能落 `noRemotePeer` | 已落地 |
| §4.10 并发事件追踪 | `:216` `inFlightEventIdentifiers: Set<String>`；`:482-519` `consume` 按 `event.identifier` 维护集合、`lastEventEndedAt` 取 `max`、失败事件也移除、`.setup` 单独记录 | 已落地 |
| §4.12 事件基线 | `:287-298` `markContainerLoaded(at:)`；`WeekyiiApp.swift:745` 容器建成后调用 | 已落地 |
| §4.3 reconcile 分层 | `StateMachine.swift:98-136`：`if allowsSyncedWrites { ...全部 Tier-2... }`，`:133` `bumpStateTransitionRevision` 在闸门外 | **优于文档**：文档写"加 `allowSyncedWrites: Bool` 入参"，实际是 init 注入 `syncedWritesAllowedProvider` 闭包（`:68/86/108`），能反映运行时变化；`:138-150` `ensureSystemStartDate` 也做了分层 |
| §4.6 拆 `markProcessed` | `StateMachine.swift:4-15` 协议含 `markRollover` + `markProcessed`；`AppState.swift:42-52` 两个实现；`:129` 闸门内 `markProcessed`、`:148` 闸门外 `markRollover` | 已落地 |
| §4.2.4 `repair` 不拆参 | `StateMachine.swift:49-51` 协议仍是单参 `repair(referenceDate:)`；`:458-486` 实现未加参 | 已落地 |
| §4.11 第三步 `load()` 纯读 | `TaskTypeDefinition.swift:94-97` 只 fetch，**无 seed 调用** | 已落地 |
| §4.8 新增 `.remoteImport` | `WeekyiiApp.swift:368-373` 仍是四态；`:647` 仍 `.manualResync, force: true`；`:459` force 条件仍 `\|\| trigger == .manualResync` | **未落地**（见 §2.4） |
| §4.8 注入默认值 fail-closed | `WeekyiiApp.swift:395-404` `storeMode: = .production`、`cloudSyncMonitor: = nil`；`:434-437` `settlement` 兜底为 `.unsettled(.monitorNotStarted)` | 已落地 |

### Phase C（kill time 去设备本地化）—— 已落地

| 文档要求 | 代码证据 | 判定 |
|---|---|---|
| C.1 幂等化 | `StateMachine.swift:263-285` `syncTodayDefaultKillTimeIfNeeded`：`guard todayDay.followsDefaultKillTime \|\| isLegacyUntouchedDay`，写入后置 `followsDefaultKillTime = true` | **等效替代且更完整**：文档写"仅当日值为 23:45 且 followsDefault 时写"，实现额外识别老版本 20:00 遗留日（`isLegacyUntouchedDay`），覆盖面更广 |
| C.2 KVS 镜像 | `UserSettings.swift:189-202` 读 KVS 优先；`:334-336` 写 KVS + `synchronize()`；`:264-267` 监听 `didChangeExternallyNotification`；`:347-353` 处理外部变更 | 已落地 |

### Phase D1（设备内时区锚点）—— 锚点已落地，护栏未落地

| 文档要求 | 代码证据 | 判定 |
|---|---|---|
| 锚点时区写入 UserDefaults | `Date+Weekyii.swift:3-25` `WeekyiiTimeZone`：`anchorKey = "weekyii.timeZoneAnchor"`，首次读取时写入当前时区 | 已落地 |
| `dayId`/`weekId` 用锚点 | `:28-41` 两个 formatter 均 `timeZone = WeekyiiTimeZone.timeZone`；`startOfDay`/`startOfWeek`/`addingDays`/`isoWeekday` 也用锚点 calendar | 已落地 |
| 护栏：validate 失败不阻断启动 | `WeekyiiPersistence.swift:490-497` 仍 `throw`；`:162` `try` → catch → `.failed` | **未落地**（见 §2.2） |

### Phase E-1'（同步开关 + 双向迁移）—— 已落地

| 文档要求 | 代码证据 | 判定 |
|---|---|---|
| `cloudSyncEnabled` 设备本地偏好 | `UserSettings.swift:9/23/202/282`；`resolveStoreMode` 的第二条 guard 消费它 | 已落地 |
| 关闭同步（云→本地） | `SettingsView.swift:859-896` `prepareStoreTransfer`：export → 当前库快照 → 目标库快照 → 检查目标是否为空 → 空则 `completeStoreTransfer`，非空则 `showingStoreConflict` | 已落地 |
| 开启同步（本地→云）二选一 | `:887-891` 非空目标弹二选一；`:925-953` `adoptCloudStoreForSync` 用 `exportReadOnly` 读云库 → `importReplacing` 到本地 → `cloudSyncEnabled = true` | 已落地 |
| `restoreSnapshot` 目标按模式解析 | `SettingsView.swift:3022` `persistentStoreURL(for: storeMode)` | 已落地 |
| 切换不热重建容器 + 提示重启 | `:711` "切换后重启应用生效"；`:919/949/966-967` 各路径均提示重启 | 已落地（文案硬编码，见 §2.6） |
| 运行中不允许切换（未结算） | `:830-842` `canRequestCloudSyncChange`：`.production` 下需 `settled`；`:851-854` 未结算时给提示 | 已落地 |

### Phase E-1.5 / B.5（账号身份护栏）—— 已落地

| 文档要求 | 代码证据 | 判定 |
|---|---|---|
| settled 时持久化 `userRecordID` | `CloudSyncMonitor.swift:349-359`，在 `settlement()` 返回 `.settled` 前写入 `defaults`（`lastSyncedUserRecordIDKey`） | 已落地（副作用设计见 §3.2） |
| 身份比对关闭闸门 | `:456-459` `configureIdentity` → `identityConfirmed = stored == nil \|\| stored == current`；`:333-335` `guard identityConfirmed else { return .unsettled(.identityMismatch) }` | 已落地 |
| 运行期账号切换 | `:387-394` `refreshAccountStatus` 重算身份；`WeekyiiApp.swift:619` `scenePhase == .active` 时调用 | 已落地 |
| 测试 | `ModelTests.swift:356-450` 六个 `test_identityGuard_*` 用例 | 已落地 |
| 局限写入代码注释 | `CloudSyncMonitor.swift:353-355` 明确"不能阻止框架在已建好的 `.private(B)` 容器上把 A 的记录导出到 B" | 已落地 |

### Phase E-2'（身份不一致三选）—— 已落地

| 文档要求 | 代码证据 | 判定 |
|---|---|---|
| 三选枚举 + 待决键 | `WeekyiiPersistence.swift:287-294` `IdentityResolution`；`:12` `pendingIdentityResolutionKey` | 已落地 |
| 启动准备待决快照 + 两库恢复点 | `WeekyiiApp.swift:747-749` + `:764-790` `prepareIdentityResolution`：`exportReadOnly` + 云库/本地库各建恢复点 | 已落地 |
| 身份恢复一致时清残留 | `:750-756` | 已落地 |
| 执行器 | `WeekyiiPersistence.swift:317-345` `performIdentityResolution` → `:350-377` cloud / `:380-411` local | 已落地 |
| 设置页三选 UI | `SettingsView.swift:728-754` 三按钮；`:184-192` 确认弹窗；`:980-1047` 文案与执行 | 已落地 |
| 修复"条件永不成立"的真 bug | `:725-728` 改为 `storeMode == .cloudDetached && !cloudSyncMonitor.identityConfirmed`，注释写明原条件失效原因 | 已落地 |
| 全程 fail-closed | `ModelTests.swift:552-569` `test_identityResolution_gateStaysClosedThroughoutDecision` 断言 `cloudDetached` 与 `production` 下均为 false | 已落地 |

### Phase F（习惯水位线）—— **未落地**

| 文档要求 | 代码证据 | 判定 |
|---|---|---|
| §8.1 水位线改由 `records` 推导 | `HabitModel.swift:77` **仍是存储字段** `var generatedThroughDayId: String = ""`；`HabitTaskMaterializer.swift:138` 仍读它、`:186-190` `advanceWatermark` 仍写它 | **未落地**（见 §2.5） |
| §8.2 撤销去重 pass | 全仓无按 `(dayId, habitId)` 去重的代码；`HabitStatistics.swift:112-123` rank 合并语义完好（`:144-150` completed=2/missed=1/pending=0） | 已落地（"撤销"本身） |

### Phase A.7（GC）—— 已落地，注释缺强制表述

见 Phase A 表格最后一行。补充：`StateMachine.swift:405-409` 的注释说明了"只在闸门开启后执行"，但**没有包含 #20 的五条强制表述**（GC 不是绝对安全 / 离线设备跨窗口重上线可能复活 / 已知数据一致性风险 / 独立于 A、B 验收 / 不得宣称"删除绝不复活"）。§13.6 明文要求"必须逐条出现在代码注释与本文件中"。

---

## 2. 文档与代码不一致清单（逐条）

### 2.1 【高】§4.4 引导期 repair 未删除

**文档要求**：删掉 `bootstrapPersistentContainer` 内的 `repair` 调用，把首次修复交给第一次闸门开启后的 reconcile。
**代码实际**：`WeekyiiPersistence.swift:158-161`
```swift
if resolvedMode.allowsSave {
    try TaskTypeCatalog.seedBuiltInTypesIfNeeded(in: container.mainContext)
    _ = DataInvariantRepairService(modelContainer: container).repair(referenceDate: referenceDate)
}
```
**分层影响**：
- `cloudDetached`（`allowsSave == false`）→ 不跑 ✅ 已满足 §7.2.2 的硬前置
- `.localOnly`（`hasNoRemotePeer == true`，闸门恒开）→ 跑，无危害 ✅
- `.production` → 跑，且此刻容器刚建、CloudKit 首次导入未到 → **§1.6 想消除的"引导期跑在导入之前"在这一档仍然存在** ⚠️

**有测试反向锁定**：`ModelTests.swift:887-922` `test_bootstrapNormalizesCompetingPresentWeeksFromDifferentDevices`，XCTFail 文案 `"Competing present-week updates must be repaired during launch"`。删 repair 会打破它。

**判定**：这是**为"修复及时性"做的有意取舍**，不是遗忘。但文档 §4.4 与 §13.2 的对应断言（"`bootstrapPersistentContainer` 内不再出现 repair"）没有同步更新，形成"文档要求 X、代码做非 X、测试反向锁定非 X"的三方矛盾。

**注意**：不能用"与首次 settled reconcile 语义一致（同函数、同输入）"来论证风险可接受 —— §4.1 明确批判过这个推理（"函数设备无关 ≠ 输出设备无关，因为输入是本地可见集合"）。首启时本地装的是上次会话残留，不是完整视图。**正确理由是**：repair 产出的错误是**可纠正的软派生**（§3.1 保证 `closedAt` 只由显式动作写、status 每轮可重算），最坏情况会在首次 `settled` 的 reconcile 里被重算纠正。

### 2.2 【高】§6 D1 的 `validateContainerConsistency` 护栏未落地

**文档要求**：校验失败时不再 `.failed` 阻断启动，改为记录 + 走 `BackupRecoveryService` 提示恢复（"只防锁死"）。
**代码实际**：`WeekyiiPersistence.swift:490-497` 仍然 `throw`；`:162` `try validateContainerConsistency(container: container)` 位于 `do` 块内，抛错即走 `:164-167` 的 catch → 返回 `.failed`。

**与 2.1 的耦合（重要）**：现有 `ModelTests.swift:866-884` 那条测试名叫 "A recoverable CloudKit merge must not block app launch"，看起来像在验护栏，**实际是通过 repair 先把重复周合并掉才 `.ready`** —— 护栏从未被检验。也就是说：
- 保留 repair = 继续掩盖 D1 护栏缺失
- 任何 **repair 修不掉**的不一致（不止 present week 重复这一种）仍会让 App 直接启动失败

### 2.3 §4.11 第一步：已达成，落点与文档不同

`makeModelContainer`（`:170-222`）内**无任何播种调用**，构造器是干净的 —— 文档"移出 `makeModelContainer`"已达成。
但文档要求"由 `AppHealthCoordinator` 在闸门允许时显式调用"，实际落在 `bootstrapPersistentContainer:159` 内按 `allowsSave` 判断。差异是"闸门允许"被简化为"容器可写"。

### 2.4 【低】§4.8 `.remoteImport` 未新增

`WeekyiiApp.swift:368-373` `AppHealthTrigger` 仍只有 `launch/sceneActive/minuteTick/manualResync`；`:647` 仍是 `reconcile(trigger: .manualResync, force: true)`。
**安全上无影响**：`force` 只绕 `shouldSkipReconcile` 节流（`StateMachine.swift:99-104`），闸门读的是独立的 `syncedWritesAllowedProvider`（`:108`），与 trigger 无关。
**但文档三处留悬空待办**：§4.8、§4.9（`:937`/`:940-941`）、§13.2（`:1755-1756`）。下一个接手人会对着三处"待办"发呆。

### 2.5 【高】§8.1 Phase F 水位线改推导未落地

**文档要求**：`HabitTaskMaterializer` 的水位线改由 `records.map(\.dayId).max() ?? ""` 推导，抗 LWW 回退。
**代码实际**：
- `HabitModel.swift:77` `var generatedThroughDayId: String = ""` —— **仍是会被同步的存储字段**
- `HabitTaskMaterializer.swift:138` `guard habit.generatedThroughDayId < todayKey else { return }` —— 仍读它
- `:186-190` `advanceWatermark` 仍写它

**后果**：文档 §8.1 自己论证过"存储的 String 会被 LWW 回退 → 重复物化"。闸门（Phase B）能抵抗"部分同步"，但**抗不住 LWW 回退**（两台设备各自推进水位线，同步后可能取到较小值 → 该日被重新物化）。§8.1 明确说"闸门抵抗部分同步，推导抵抗 LWW 回退，**两者缺一不可**"。

**文档状态行声称"F 已实现"，与代码不符。** §13.7 的对应验收断言（"水位线由 `records` 推导后，删除最新 record 不会导致重复物化"）无着落。

### 2.6 【中】新增 UI 文案硬编码中文，未走 `String(localized:)`

文档 §7.2 边界 3 明确建议文案入 `Localizable.xcstrings`，键名 `settings.cloud.restart_required`。**该键不存在**（全仓 grep 零命中）。

新增文案全部是硬编码中文字面量，例如：
- `SettingsView.swift:711` "切换后重启应用生效；关闭时使用独立本地数据"
- `:720` "当前处于只读保护，待完成账号确认或重启后才能切换数据源。"
- `:730/733` 三选标题与说明
- `:739/744/749` 三个选项的 subtitle
- `:846` 切换确认文案
- `:919/949/966-967` 迁移完成提示
- `:984/986/988` 三选确认文案（"此操作不可撤销"）
- `:1034/1046` 待决快照缺失与完成提示
- `ContentView.swift:80` 只读横幅 "当前数据处于只读保护，等待 iCloud 账号确认。"
- `WeekyiiError.swift:69` "当前数据处于只读保护状态，请登录 iCloud 或重启应用后再修改。"
- `WeekyiiApp.swift:895/898` 占位页文案

**对照**：`today.done.awaiting_sync` 走了 `String(localized:)` 且 catalog 有 en/zh ✅；`settings.icloud.status.*` 系列也完整 ✅。所以这不是"项目没做 i18n"，而是**本轮新增文案漏做了**。

### 2.7 【低】§7.1.1 无参 `persistentStoreURL()` 未删

`WeekyiiPersistence.swift:264-268` 保留，注释写 "Compatibility entry point for existing recovery/test callers"，返回 `.production`。全仓已无调用点（死代码）。
文档 §7.1.1 改动 1 说"更好的做法是删掉无参版本，强制所有调用点显式传模式"；§13.2.0 有"编译期：无参版本已删除"的断言 → 不成立。

### 2.8 【低】`failureDiagnostics()` 硬编码 `.production`

`WeekyiiPersistence.swift:476` `let storeURL = persistentStoreURL(for: .production)`。
文档 §7.1.1 表格把 `:184` 列为需按模式解析的调用点之一（后果："诊断信息指向错误的库"）。`.localOnly` 设备点"导出诊断信息"会拿到云库路径与云库快照列表。
影响面小（该函数在 `PersistenceFailureView` 里调用，而该视图拿不到 storeMode），但确实是文档列明未修的一处。

### 2.9 【低】GC 注释缺 #20 五条强制表述

见 §1 Phase A.7。§13.6 明文要求"逐条出现在代码注释与本文件中"。

### 2.10 【记录】报告声称的 `IdentityResolutionTests` 类不存在

交接材料称"`ModelTests.swift 498~622` 共 6 个用例 + `IdentityResolutionTests` 另 3 个，共 9 个"。全仓 grep `IdentityResolutionTests` **零命中**。实际是 `ModelTests.swift` 内 `identityGuard_*` 6 个（`:356-450`）+ `identityResolution*` 6 个（`:498-627`），共 12 个。数字口径与代码不符，但**测试本身是真实存在的**。

---

## 3. 代码质量评估

### 3.1 设计质量（高）

- **类型系统承载业务教训**：`cloudDetached` 这一态的存在，把"'没有入站通道' ≠ '没有对端'"编码进枚举，不靠调用方记得传对参数。`settlement()` 里 `guard storeMode == .production` 先于 `hasNoRemotePeer`，从结构上排除了"只读云库被误判为无对端"。
- **fail-closed 是默认值**：`AppHealthCoordinator` 的 `storeMode = .production` + `monitor = nil` 兜底到 `.unsettled(.monitorNotStarted)`；`StateMachine` 的 `syncedWritesAllowed` 闭包默认 `{ true }` 只服务测试，生产调用点显式传值。
- **门控只发生在调用点**：`repair` 实现一行未改（§4.2.4），把"是否需要门控"与"如何修复"解耦，波及面最小。
- **注释解释"为什么"**：`DayModel.swift:67-69`、`CloudSyncMonitor.swift:349-355`、`WeekyiiPersistence.swift:264-265/414-417` 都写明了取舍理由与已知局限，符合可交接要求。

### 3.2 `settlement()` 的副作用设计（中风险）

`CloudSyncMonitor.settlement()` 名字是查询，实际会写 `UserDefaults`（`:356-359`）。它被以下位置调用：
- `syncedWritesAllowed()`（`:367`）→ 被 `StateMachine.reconcile` 每次调用
- `AppHealthCoordinator.settlement`（computed）→ `diagnosticsSnapshot`、设置页
- `TodayViewModel.isAwaitingSyncConfirmation`（computed）→ **`TodayView` body 热路径**（`TodayView.swift:661`）
- `SettingsView.canRequestCloudSyncChange`（computed）→ 设置页每次重绘
- `ContentView.onOpenURL` 闭包

当前靠 `defaults.string(forKey:) != currentUserRecordID` 做幂等，行为上正确。但"查询函数写状态"会让后续任何缓存/短路优化变得危险 —— 例如有人给 `settlement` 加 memo 缓存，身份持久化就会静默失效。

**建议**：把持久化移到 `settled` 的**状态转移点**（例如 `consume` 里事件全部结束且 quiet 期满时，或 `markContainerLoaded` 后首次进入 settled 时），让 `settlement()` 回归纯函数。这不改变行为，但消除了一类未来风险。

### 3.3 错误处理一致性（中）

- `bootstrapPersistentContainer:165` 用 `print` 记录错误（非 DEBUG 也执行），而项目其它地方用 `runtimeLog`（DEBUG 才打印）。
- `WeekyiiApp.swift:165` 的错误文案是硬编码中文长句。
- `HabitTaskMaterializer.sync` 的 `saveFailed` 会**清零** `createdCount/missedRecordCount`（`:80-81`），调用方无法知道"部分成功"，但 `needsSave` 未重置 —— 语义上 `needsSave == true && saveFailed == true` 的组合需要调用方正确解读。

### 3.4 测试质量

**优点**：
- `test_identityResolution_gateStaysClosedThroughoutDecision`（`:552-569`）直接断言验收约束，是真在检验不变量。
- `test_terminalDay_hidesOpenZonesWithoutDeletingRawTasks`（`:629`）用 raw 形式断言，避免了 §3.6 警告的同义反复。
- 崩溃规避手法（`retainedUserDefaults/retainedViewModels/retainedContainers/retainedResolutionContainers`）都带了框架缺陷注释，可交接。

**问题**：
1. **测试无法区分 `adoptCloud` 与 `overwriteCloud`**。`WeekyiiPersistence.swift:432-444` 的 `performIdentityResolutionForTesting` 对两者都走 `applyIdentityResolutionToCloudStore(cloudMode: .localOnly)`，落盘结果一致。真正的差异（adoptCloud 靠重启后 CloudKit 回填、overwriteCloud 靠本机 archive 上传）只在真机 + 真账号下成立。现有 6 个用例覆盖的是"决策被正确执行 / 键被正确更新"，不是"两种来源语义真的不同"。
2. **§13.2 有 3 条验收断言无对应测试**：`bootstrap` 内无 repair、`makeModelContainer` 后 catalog 为空、`validateContainerConsistency` 不阻断启动。其中第 2 条按当前代码**写成测试就能通过**（构造器确实干净），属于"补测试即可闭合"的缺口。
3. **`settlement()` 的幂等性无直接测试**。`test_identityGuard_settledPersistsCurrentUserRecordID` 只验证"写入"，没验证"不重复写"。

---

## 4. 性能评估

### 4.1 【中】冷启动必然多一次网络往返

`WeekyiiApp.swift:706-713`：
```swift
let accountStatus = await cloudSyncMonitor.accountStatusForLaunch()
let currentUserRecordID: String?
if accountStatus == .available {
    currentUserRecordID = await cloudSyncMonitor.userRecordIDForLaunch()   // ← 网络
}
```
文档 §7.2.3 ② 明确提出了缓解措施："先用本机缓存的 `lastSyncedUserRecordID` 与 `CKContainer.accountStatus`（同步、无网络）做一次快速判定，只有快速判定不足以确认时才等 `fetchUserRecordID()`"。

**实际未实现该短路**：只要账号 `.available`，每次冷启动都会 `await` 一次 `userRecordID()`。`CKContainer.userRecordID()` 虽有本地缓存，但首次/缓存失效时是网络请求。

**影响**：有账号设备（绝大多数用户）冷启动必须等这次网络往返，且这段时间停在 `PersistenceResolvingView`（"正在确认同步账户…"）。文档自己把这条列为"实现细节，不改变裁决"，但它直接决定用户感知的启动速度。

**可行的短路**：`accountStatus == .available && storedUserRecordID != nil` 时，先用 stored 值建容器（`identityConfirmed` 暂置 true），把 `fetchUserRecordID()` 移到容器建成后的后台校验 —— 若后台发现不一致，闸门会自动关闭（`identityChanged` 已有完整通路）。这样冷启动不阻塞，安全性由"闸门 fail-closed + 身份不一致关闸"保证。**注意**：这需要重新论证 §7.2 的"检测不能晚于容器创建"约束是否被削弱 —— 若不能，就应把这条性能代价明确写进文档，而不是留着一条未实现的缓解措施。

### 4.2 【中】`settlement()` 在热路径上

见 §3.2。`TodayView.swift:661` 的 `viewModel.isAwaitingSyncConfirmation` 是 computed，每次 body 求值都会调 `allowsSyncedWrites()` → `settlement()`，其中包含 `defaults.string(forKey:)`、`inFlightEventIdentifiers.isEmpty`、`max()` 比较，以及（首次进入 settled 时）`defaults.set()`。

**UserDefaults 读写本身是内存操作，单次成本极低**，但这是每次 SwiftUI 重绘都发生的开销，且 SwiftUI 无法对它做 diff（因为它不是 `@Published`）。建议至少把 `isAwaitingSyncConfirmation` 的结果在 `refresh()` 时算一次并缓存。

### 4.3 reconcile 的重复全表扫描（既有问题，本轮未恶化）

一次闸门开启的 reconcile 会触发多次全表 fetch：
- `processStaleOpenDaysBeforeToday` / `processCrossDay`（全表 DayModel）
- `processCrossWeek`（全表 WeekModel）
- `processExpiredSuspendedTasks`（全表 SuspendedTaskItem）
- `repair`（全表 TaskTypeDefinition + WeekModel + DayModel + **每个 day 的 tasks**）
- `refreshWeekSummaryMetrics`（全表 WeekModel + days）
- `TaskGarbageCollector.collect`（全表 DayModel）
- `HabitTaskMaterializer.sync`（全表 HabitModel + 其 records）
- `rescheduleNotificationsAfterReconcile`（全表 DayModel）

触发频率：`minuteTick`（前台每分钟）+ `sceneActive` + `launch` + `remoteImport`。`shouldSkipReconcile`（`StateMachine.swift:390-397`）用分钟键节流，所以**前台每分钟最多一次全量扫描**。

这是既有设计（项目记忆 `launch-perf-audit` 已记录"橙屏间隔 = 主线程同步全量 reconcile"），本轮**没有恶化**，但也没改善。`repair` 被移出 `makeModelContainer` 之后启动路径少了一次，是正向的。

### 4.4 `cloudDetached` 的全库文件复制（可接受）

`WeekyiiPersistence.swift:224-250` 每次以 `cloudDetached` 打开容器都会复制 `.store` + `-wal` + `-shm` 到 `Caches`。
- 只在"账号解析超时 / 身份未确认"时发生，不是常规路径
- 复制在 `makeModelContainer` 内同步执行，会阻塞主线程（该函数是 `@MainActor` 上下文调用的）
- 大库（例如数百 MB 含附件）时这段时间用户停在占位页

**建议**：`DetachedStores` 目录按 pid 隔离且进程启动时清理（`:230-234` 已做），但可以考虑用 `NSFileCoordinator` 或 `clonefile`（APFS clone，零拷贝）替代 `copyItem`。这是优化项，非缺陷。

### 4.5 备份快照的 SHA-256 全量哈希（既有问题）

`WeekyiiPersistence.swift:499-525` `makeFileEntry` 对每个文件做全量 SHA-256；`:651-673` 建快照后对**所有文件再验一遍**。而 `backupPersistentStoreIfExists`（`:270-281`）在 `bootstrapPersistentContainer:151` 每次启动都会调用 —— 靠 `hasValidSnapshot(reason: "preflight-v8")` 短路，所以只在首次/快照失效时真的做。

E-1'/E-2' 新增的迁移流程会多建快照（`:193` importReplacing 内、`:360/390/403` 各建一次），哈希成本随之增加。对含大量图片附件的库（`@Attribute(.externalStorage)`）可能达到秒级。**未实测**，列为观察项。

---

## 5. UI 易用性评估

### 5.1 只读保护（做得好）

- **不静默吞点击**：`TodayView.swift:458/553/574/597/843` 等多处 `.disabled(!storeMode.allowsSave)`，按钮明确置灰而非"点了没反应"。
- **有可见解释**：`ContentView.swift:78-90` 顶部横幅（`allowsHitTesting(false)`，不挡操作）+ `SettingsView.swift:720` 说明行。
- **文案可本地化**：❌ 横幅与说明均为硬编码中文（§2.6）。
- **`isReadOnly` 传入子视图**：`:470/610` 传给任务卡片，说明只读态在卡片层面也有表达。

**一个缺口**：`SettingsView.swift:2001` 的 kill time 立即过期路径未受只读保护，`cloudDetached` 下会尝试写终态并 `save()` 抛错。用户可能看到错误弹窗或静默失败。

### 5.2 三选 UI（结构正确，文案待补）

- 显示条件正确（`:728`），注释写明原 bug 原因 ✅
- 三个选项的 title/subtitle 语义清晰，覆盖"云端优先 / 本机优先 / 转本地"三种意图 ✅
- 二次确认弹窗（`:184-192`）+ "此操作不可撤销"提示 ✅
- **文案硬编码中文** ❌
- **误操作风险**：`adoptCloud`（"本机修改将被丢弃"）与 `overwriteCloud`（"本机数据将覆盖云端"）都是破坏性操作，弹窗用了 `.destructive` role（`:188`），但没有要求二次输入确认或高亮默认安全选项。考虑到这是"换 Apple ID"这种低频高危场景，建议把**破坏性最小**的选项（保留本机数据转本地）作为视觉默认。

### 5.3 闸门期的可理解性（中）

文档 §4.7 列出了 8 项用户可见退化（昨天仍显示执行中、不出现新 present week、首页可能为空、习惯不物化、完成最后一项不立刻显示已完成、内置类型显示兜底名、重复周不合并、GC 不跑）。

**代码侧只有 3 处表达**：
1. `today.done.awaiting_sync`（只覆盖第 5 项）
2. `ContentView` 的 cloudDetached 横幅（只在 `cloudDetached` 显示，`.production + unsettled` **不显示**）
3. `SettingsView` 的状态行（要进设置页才看得到）

**最大的缺口**：`.production + unsettled` 时，用户看到的是"昨天还在执行中 / 首页空 / 习惯没物化"，但**首页没有任何解释**。文档 §4.7 说"首页在闸门期显示既有的 iCloud 状态行作为'正在同步'的可见解释（已定项 #14）"，这一条**未落地** —— 首页没有状态行，横幅只在 `cloudDetached` 出现。

这是本轮 UI 侧最值得补的一项。

### 5.4 设置页诊断可见性（基本满足）

`SettingsView.swift:691` 显示 `settlement(storeMode: storeMode).description`，能区分 `noRemotePeer` / `settled` / `noInboundChannel` / `unsettled(...)` 及具体 blocker（`events-in-flight-N` / `quiet-until-...` / `no-event-baseline` 等）✅。

**但未显示 `settlementDiagnostics`**（`CloudSyncMonitor.swift:375-385`，含 `identityConfirmed` / `userRecordID` / `inFlight` / `lastEventEndedAt`）。它只在 `AppHealthCoordinator.diagnosticsSnapshot()`（`WeekyiiApp.swift:498`）里用，用户看不到。文档 §4.12 说"设置页显示 `settlement` 的具体 blocker **与 monitor diagnostics**" —— 前半满足，后半未满足。

### 5.5 重启提示的可达性（满足）

每条改变数据源/同步状态的路径都提示重启：`:919`（迁移完成）、`:949`（采用云库）、`:966-967`（保留设置）、`:1046`（三选完成）。且 `identityResolutionAppliedMessage`（`:1046`）用 "请立即重启" 的措辞，比其它路径的"请重启"更强。

**缺口**：没有提供"立即重启"的入口（如 `exit(0)` 或跳系统设置）。iOS 上主动退出 App 是不被推荐的，所以提示用户手动重启是合理选择 —— 但文案可以更明确（如"请从后台彻底关闭 Weekyii 后重新打开"）。

---

## 6. 风险排序与处置建议

| 优先级 | 项 | 建议动作 |
|---|---|---|
| P0 | §8.1 水位线改推导未落地 | **改代码**。这是 §8.1 论证过的真实缺陷（LWW 回退 → 重复物化），闸门挡不住。改动面小：`HabitTaskMaterializer` 读处改为 `habit.records.map(\.dayId).max() ?? ""`，写处保留（或一并去掉）。需补一条"故意把 `generatedThroughDayId` 改小 → 不重复物化"的对照测试 |
| P0 | §6 D1 validate 护栏未落地 | **改代码**。`validateContainerConsistency` 改为不抛错、记录 + 返回诊断；`bootstrapPersistentContainer` 不再因它进 `.failed`。**必须先决定这条，再决定 2.1** —— 因为护栏补上后，删 repair 才安全 |
| P1 | §4.4 引导期 repair | **改文档**（推荐）或**改代码**。若选改文档：在 §4.4 加偏差注记说明"保留、限定 `allowsSave` 容器"，并把 §13.2 那条断言改写为"只读模式下不执行 repair"并补真实测试。若选改代码：需同时改 `ModelTests.swift:887-922` 并承担"首启双 present 周延迟到首次 settled 才归一化"的行为变更 |
| P1 | 冷启动 `userRecordID()` 往返 | **二选一**：实现文档 §7.2.3 ② 的快速判定短路，或把这条性能代价明确写进文档（删除"缓解措施"表述）。不要留悬空 |
| P1 | 新增文案 i18n | **改代码**。约 15 处硬编码中文字面量改为 `String(localized:)` 并补 catalog 的 en/zh |
| P2 | 闸门期首页无解释 | **改代码**。把 `cloudDetached` 横幅的显示条件扩展为 `storeMode == .cloudDetached \|\| !syncedWritesAllowed`，或按 §4.7 定项 #14 在首页加状态行 |
| P2 | `settlement()` 副作用 | **改代码**（重构）。把持久化移到状态转移点，`settlement()` 回归纯函数 |
| P2 | §4.8 `.remoteImport` | **二选一**：补 5 行代码 + 2 个测试，或把 §4.8/§4.9/§13.2 三处同步改为"未实施，复用 `.manualResync`" |
| P3 | 无参 `persistentStoreURL()` | **删代码**（4 行，零调用点） |
| P3 | `failureDiagnostics()` 硬编码 `.production` | **改代码**，或接受并把 §7.1.1 表格对应行标注为"有意保留" |
| P3 | GC 注释缺 #20 五条 | **改注释**（§13.6 明文交付项） |
| P3 | 补 3 条缺失的验收测试 | **改测试**。其中"`makeModelContainer` 后 catalog 为空"写成测试即可通过 |
| P3 | 设置页显示 `settlementDiagnostics` | **改代码**（可选，诊断用） |

---

## 7. 证据索引

**已完整阅读**：`CloudSyncMonitor.swift`(544) / `WeekyiiApp.swift`(978) / `AppState.swift`(74) / `DayModel.swift`(78) / `Date+Weekyii.swift`(104) / `TaskTypeDefinition.swift`(174) / `HabitModel.swift`(216) / `HabitTaskMaterializer.swift`(200) / `ContentView.swift`(127)
**关键段阅读**：`WeekyiiPersistence.swift`(2075；读 1-825 / 1007-1062 / 1700-2075，825-1007 为 V1-V7 冻结 schema 定义略读) / `StateMachine.swift`(790；读 1-157 / 240-405 / 405-505 / 505-595 / 680-790) / `DataArchiveService.swift`(390；读 40-270) / `TaskPostponeService.swift`(493；读 396-493) / `SettingsView.swift`(读 628-880 / 876-991 / 2001-2219) / `HabitStatistics.swift`(读 100-160) / `ModelTests.swift`(5188；读 348-640 + 全文 grep) / `UserSettings.swift`(grep) / `NotificationService.swift`(grep)

**未逐一验证的项（需实测）**：
- 人工双机场景（§13 各节的"人工双机"条目）—— 无真机与双账号环境
- `Event.identifier` 在同一事件 start/end 两次通知间是否稳定（§4.10 的推断项）
- `cloudDetached` 在 store 版本 < V8 时能否成功构造（§7.2.2 的推断项）
- 备份快照 SHA-256 在含大量附件库上的实际耗时
- GC 后离线旧设备重新上传的真实行为（§3.7，已被 #20 裁定为"接受为已知残余风险"）
- `HabitTaskMaterializer.sync` 的 `saveFailed` 组合语义在 UI 上的表现

**本报告未修改任何源码。** 工作区仍为审查前状态。
