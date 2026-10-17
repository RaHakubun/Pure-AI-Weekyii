# Weekyii Local-First 付费 iCloud 同步完整执行计划

> 建议文件路径：`docs/plans/2026-09-21-local-first-paid-icloud-sync-execution-plan.md`
>
> 状态：**最终执行方案 / 取代此前 iCloud 收敛方案作为后续开发主计划**
>
> 基线工作区：`Weekyii`
>
> 当前分支：`online-chatgpt-develop`
>
> 当前 HEAD：`6b4c4da`
>
> 注意：当前 working tree 为 dirty 状态，存在大量未提交修改。**当前 working tree 的源码是真相源，不能 reset、checkout、覆盖或假定 HEAD 等于当前实现。**
>
> 本文基于当前 Repo 实际代码、以下旧文档及其评审重新制定：
>
> * `docs/plans/2026-09-19-icloud-sync-convergence.md`
> * `docs/plans/2026-09-20-baseline-capability-open-revision.md`
> * `ICLOUD_SYNC_REVIEW_ROUND3_2026-09-20.md`
>
> **本文是唯一权威执行规格（PLAN_REVISION 3）。**
>
> 从 Phase B 起，执行依据只有本文件：
>
> * `.workbuddy-ai/memory/` 下的会话摘要是**过程记录**，**不得**作为执行规格。
> * 旧 plan 保留为历史记录，**已不再作为实现目标**（见「本文与旧文档的关系」）。
> * 仓库代码与当前 dirty working tree 是**事实**真相源；本文件是**规格**真相源。
>   两者冲突时：先停下来报告，不要擅自改规格，也不要擅自改代码。
>
> ## 合并优先级（发生冲突时严格按此顺序）
>
> 1. 当前 Repo 真实代码
> 2. 后续独立 Review 已明确裁决
> 3. 增量修订 3
> 4. 增量修订 2
> 5. 增量修订 1
> 6. 原始 2026-09-21 主计划
>
> **不要**按「哪个文档写得更长」或「哪个更像最终稿」判断。
>
> ## 增量修订覆盖清单 —— **已闭合**
>
> 增量修订 1 / 2 / 3 的**原文归档**见：
>
> `docs/plans/2026-09-21-incremental-revisions-archive-and-merge-ruling.md`
>
> 覆盖清单（Revision 1 A–N / Revision 2 O–P / Revision 3 Q–AJ / 后续 Review 6 项）
> 共 **42 项**，逐项状态见文末附录「增量修订覆盖清单」。
> **状态集合里没有 UNKNOWN。** 状态只有三种：
>
> * `PRESENT` —— 本文件已有等价或更完整的条款
> * `MERGED_EQUIVALENT` —— 本文件以不同措辞完整承载了该语义
> * `SUPERSEDED_BY <条款>` —— 旧条款已被后续产品事实或 Review 裁决取代，**不要重新激活**
>
> ## 已裁决事项（不要再重新讨论）
>
> | 事项 | 裁决 | 落点 |
> |---|---|---|
> | 自动 SwiftData/CloudKit 同步留下的历史数据 | 仅内部 TestFlight / 开发使用过，**不需要** production `CD_*` → `WeekyiiSyncZoneV1` 迁移桥 | 「Legacy CloudKit records」 |
> | KVS（`NSUbiquitousKeyValueStore`）移除 | 属 **Phase B.4**，**不得**提前到 Phase A | 「Phase B.4」 |
> | Habit `generatedThroughDayId` | **Phase D 之前的硬前置**；Phase D 绝不序列化它 | 「Phase B.5」 |
> | Phase A2 的 merge 语义 | 保留确定性 local-preference；它只是建筑块，不是收敛算法 | 「Phase A」 |
>
> ## 当前进度
>
> **Phase A（A0–A2）已通过独立审查，实现被接受，行为已冻结 —— 不再重新设计。**
>
> 本轮 **Iteration 3** 只做文档、注释与静态封口，不引入任何行为实现。
> 封口被独立核对通过以后，才可以开始 Phase B。

---

# 0. 本方案的最终产品定义

Weekyii 必须首先是一款**完整的本地 App**。

iCloud 不是 Weekyii 数据库本身，不是数据库选择器，不是业务能力的前置条件，也不是任何写入操作的闸门。

最终必须满足以下定义：

> **`Weekyii.store` 是 Weekyii 唯一权威业务数据库。**
>
> 用户所有操作永远首先写入本地 SwiftData。
>
> iCloud 只是在用户满足付费资格并主动开启以后，附着在本地数据库上的可选远端同步服务。
>
> 没有网络、没有 Apple ID、没有 iCloud 空间、CloudKit 出错、订阅失效、用户关闭同步、Apple ID 切换，都不得让 Weekyii 的本地功能失效、变成只读、切换到另一份业务数据库或让已有数据不可见。

因此目标架构不是：

`SwiftData + 自动 CloudKit mirroring = 数据库`

而是：

`SwiftData 本地数据库 = 唯一真相`

加上：

`CloudSyncEngine = 可选的双向远端复制层`

---

# 1. 不可违反的产品不变量

以下内容必须作为代码设计的硬约束，而不是 UI 层约定。

## R1：本地数据库永远可用

只要本地 SQLite/SwiftData 本身没有真实损坏，以下能力必须始终可用：

* 建周
* 建日
* 建任务
* 编辑任务
* 删除任务
* 完成任务
* Focus 流程
* Draft / Frozen
* Pending
* Project
* Habit
* MindStamp
* Suspended Task
* 跨日流转
* Kill Time
* 过期处理
* 后移任务
* 系统 repair
* GC
* Widget 本地快照
* 通知
* Live Activity

这些行为不得查询：

* CloudKit 是否 settled
* 当前网络是否可用
* Apple ID 是否登录
* iCloud 是否有额度
* 用户是否购买订阅
* 最近一次同步是否成功

才能决定“可不可以写”。

---

## R2：唯一 canonical store

正式 App 只存在一个业务数据库：

`Application Support/Weekyii/Weekyii.store`

以后不得继续设计：

* `Weekyii.store = 云模式`
* `Weekyii.local.store = 本地模式`

这种双业务库架构。

`Weekyii.local.store` 以后只能作为**旧版本遗留数据源**被一次性迁移，不能再成为运行模式。

---

## R3：SwiftData 永久 local-only

正式业务 `ModelContainer`：

`cloudKitDatabase = .none`

永远如此。

不再让 SwiftData 自动 `NSPersistentCloudKitContainer` mirroring 成为生产同步机制。

iCloud 同步由新的显式 CloudKit 层负责。

这样才能真正控制：

* 什么时候同步
* 什么时候停止
* 重试几次
* 手动同步
* Apple ID 切换
* 数据来源选择
* 合并策略
* quota 错误
* 订阅失效
* 同步状态 UI

---

## R4：iCloud 默认关闭

当前：

`UserSettings.cloudSyncEnabled`

默认 `true`。

这个语义必须废除。

新安装用户默认：

`cloudSyncRequested = false`

用户不主动开启，就完全不进入 CloudKit 同步生命周期。

---

## R5：付费资格与同步开关是两个状态

不得再用一个 Bool 表达全部情况。

至少必须存在：

`cloudSyncRequested`

表示：

> 用户是否希望开启 iCloud 同步。

以及独立的：

`CloudSyncEntitlementState`

表示：

> 用户当前是否具备付费同步资格。

两者不能互相覆盖。

---

## R6：quota 不阻断本地

用户希望：

> 有足够 iCloud 空间才能同步。

实现上不能假定存在一个可靠的“同步前查询剩余容量”API。

因此正确语义是：

付费资格有效 + 用户开启 + Apple ID 可用
→ 尝试同步。

如果 CloudKit 返回 quota exceeded：

→ `.quotaExceeded`

→ 停止 Weekyii 主动同步

→ UI 明确显示：

“iCloud 空间不足。本机数据已经安全保存。释放空间后可以再次同步。”

→ 本地 App 完全正常。

quota 是**同步运行状态**，不是本地数据库资格。

---

## R7：同步失败不能无限主动重试

Weekyii 自己不得：

* 每分钟重新同步
* 每次 StateMachine reconcile 触发同步
* 无限重建容器
* 无限刷新账号
* 无限自动 retry
* 永远显示“正在同步”

一次同步失败以后必须进入稳定状态。

用户仍然正常操作本地数据。

UI 显示错误。

提供：

**立即同步**

按钮。

用户手动再次尝试。

---

## R8：关闭同步以后 Apple ID 变化零影响

如果：

`cloudSyncRequested == false`

则 Apple ID：

A → B
B → A
登录 → 退出
退出 → 登录

全部不能影响：

* 当前数据
* 当前 UI
* Weekyii store
* Kill Time
* 任何业务状态

此时甚至不需要主动查询 `userRecordID`。

---

## R9：开启同步后 Apple ID 切换必须先停云，再问用户

当同步开启：

A → B

必须首先：

1. 停止当前 Cloud Sync session。
2. 本地 `Weekyii.store` 继续正常读写。
3. 不得向 B 上传任何数据。
4. 获取 B 的 Weekyii 云端状态。
5. 主动弹出数据来源决策。
6. 用户明确选择后才能恢复同步。

---

## R10：同步状态只能用于展示和同步协调

以下状态：

* offline
* syncing
* quota exceeded
* account unavailable
* failed
* account changed
* entitlement expired

都只能影响：

`CloudSyncCoordinator`

不能传入：

* `StateMachine`
* `TodayViewModel`
* `PendingViewModel`
* `HabitViewModel`
* `ExtensionsViewModel`
* `WeekViewModel`

作为写权限。

---

# 2. 当前 Repo 的真实状态

以下不是旧文档描述，而是当前 working tree 实际代码。

## 2.1 当前 persistence 仍然是旧的四态设计

`App/WeekyiiPersistence.swift:17-49`

当前：

* `.production`
* `.localOnly`
* `.cloudDetached`
* `.inMemory`

其中：

`.cloudDetached.allowsSave == false`

这直接违反 R1。

---

## 2.2 当前 Apple ID / CloudKit 状态仍决定物理数据库

`WeekyiiPersistence.resolveStoreMode(...)`

当前：

* `.available` → `.production`
* `.noAccount` → `.localOnly`
* `.restricted` → `.localOnly`
* `.temporarilyUnavailable` → `.cloudDetached`
* `.couldNotDetermine` → `.cloudDetached`
* identity mismatch → `.cloudDetached`

所以：

账号状态仍然决定：

* 打开什么 store
* store 是否只读
* 是否挂 CloudKit

这必须全部删除。

---

## 2.3 当前仍有两份业务数据库

`WeekyiiPersistence.persistentStoreURL(for:)`

当前：

`.production / .cloudDetached`

→ `Weekyii.store`

`.localOnly`

→ `Weekyii.local.store`

这是当前大量“数据消失”“切换后另一份数据出现”“开关同步需要导出导入”的根源。

---

## 2.4 当前 production SwiftData 直接挂 CloudKit

`WeekyiiPersistence.makeModelContainer`

当前 production：

`ModelConfiguration.CloudKitDatabase.private(...)`

因此 SwiftData framework 自己控制：

* import
* export
* retry
* account lifecycle

Weekyii 无法真正控制“只重试有限次数”。

---

## 2.5 当前同步状态仍然决定业务写入

`Services/CloudSyncMonitor.swift`

仍有：

`settlement(...)`

和：

`syncedWritesAllowed(...)`

`Services/StateMachine.swift:108-131`

仍然：

`if allowsSyncedWrites { ... }`

里面包含：

* stale day
* cross day
* cross week
* Kill Time
* repair
* summary
* GC
* markProcessed

`WeekyiiApp.swift`

还使用同一个状态决定：

`HabitTaskMaterializer.sync`

这与 local-first 原则完全冲突。

---

## 2.6 当前还有大量 persistence read-only gate

当前全仓约 56 个：

`allowsPersistenceWrites`

调用/定义。

涉及：

* Today
* Pending
* Week
* Extensions
* Habit
* MindStamp

以及：

`WeekyiiError.persistenceReadOnly`

整个机制最终必须删除。

---

## 2.7 当前 App 冷启动等待 iCloud 后才创建数据库

`WeekyiiApp.resolveAndBootstrapPersistentContainer()`

当前启动：

1. `accountStatusForLaunch()`
2. 如果 available：
   `userRecordIDForLaunch()`
3. configure identity
4. resolve store mode
5. 最后才打开数据库

`PersistenceResolvingView` 甚至明确写：

“确认完成前不会创建持久化容器”。

这是与 local-first 相反的。

新架构必须：

**先打开本地数据库并进入 App。**

云同步在之后启动。

---

## 2.8 当前同步开关默认 true

`Resources/UserSettings.swift`

当前：

`cloudSyncEnabled = ... ?? true`

必须改为明确 opt-in。

---

## 2.9 当前关闭 CloudKit 同步也没有真正“零云端”

`UserSettings` 当前无条件使用：

`NSUbiquitousKeyValueStore.default`

并：

* synchronize
* 写默认 Kill Time
* 监听 iCloud KVS 外部更新

因此即使 CloudKit store 关闭：

Apple ID 变化仍可能改变 Weekyii 设置。

新方案必须移除这条隐式云通道。

---

## 2.10 当前账号切换无法真正暂停 SwiftData mirroring

当前：

`CloudSyncMonitor`

可以检测：

`CKAccountChanged`

也可以把：

`identityConfirmed = false`

但是生产 `ModelContainer` 已经创建，并挂着：

`.private(...)`

App 层的 Bool 无法停止框架 mirroring。

当前代码注释实际上已经承认：

> App 写闸门不能阻止 framework 把 A 的数据导出到 B。

这是旧架构无法彻底修补的问题。

---

## 2.11 当前账号三选实现本身存在语义错误

`WeekyiiPersistence.performIdentityResolution`

当前：

`.adoptCloud`

和：

`.overwriteCloud`

进入同一代码路径。

两者实际没有真正不同。

现有 archive 还是旧账号本地 store 的快照。

因此：

“采用新账号云数据”

并没有可靠实现。

---

## 2.12 当前“云端是否已有数据”实际上没有查看当前远端

设置页启用同步时读取：

本机 `Weekyii.store`

判断是否为空。

它不能代表：

当前 Apple ID 的 CloudKit Private Database 是否为空。

所以现有 conflict UI 的数据来源判断并不可靠。

---

## 2.13 当前没有真实 StoreKit entitlement

全 Repo：

没有完整 StoreKit 购买/订阅实现。

`premiumThemeUnlocked`

只是普通 UserDefaults。

而且：

`DataArchiveService`

会把它导出/导入。

所以它绝不能承担 iCloud 资格。

---

## 2.14 当前同步失败仍依赖 framework 自动 retry

`CloudSyncMonitor.consume`

当前注释明确：

CloudKit 失败后会自动重试，而且无上限。

这和新的产品要求不兼容。

---

## 2.15 当前 V8 schema 已冻结

`WeekyiiPersistence.swift`

明确：

`WeekyiiSchemaV8 is FROZEN`

因此本方案优先避免为了同步元数据修改 SwiftData schema。

Cloud sync metadata 存在业务 store 之外。

这样这一轮原则上：

**不需要 V9。**

---

## 2.16 当前业务模型适合做显式同步

当前主要业务实体：

* WeekModel — `weekId`
* DayModel — `dayId`
* TaskItem — UUID
* TaskAttachment — UUID
* ProjectModel — UUID
* MindStampItem — UUID
* SuspendedTaskItem — UUID
* TaskTypeDefinition — `idRaw`
* HabitModel — UUID
* HabitDayRecord — UUID

大部分都有稳定业务 ID。

`TaskStep` 没有 UUID。

因此 CloudKit 不应把 TaskStep 独立同步，而应作为 Task / SuspendedTask aggregate 的 JSON payload。

---

## 2.17 DataArchiveService 已经提供了一套可复用 DTO

`Services/DataArchiveService.swift`

已经存在：

* WeekRecord
* DayRecord
* TaskRecord
* StepRecord
* AttachmentRecord
* ProjectRecord
* MindStampRecord
* SuspendedTaskRecord
* TaskTypeRecord
* HabitRecord
* HabitDayLog

因此新的 Cloud layer 不应重新写第二套业务序列化模型。

需要把这些 DTO 抽出来作为：

`WeekyiiBusinessSnapshot`

同时保持现有 archive format v1 编码完全兼容。

---

# 3. 旧方案为什么不再作为执行方向

## 3.1 `2026-09-19-icloud-sync-convergence.md`

这份文档解决的是旧目标：

> 在 SwiftData 自动 CloudKit mirroring 基础上，尽量避免多端冲突。

它因此引入：

* syncedWritesAllowed
* settlement gate
* cloudDetached
* 只读 store
* 双 store
* 账号状态决定 store
* iCloud 账号解析进入启动关键路径

在当时问题定义下内部逻辑可以成立。

但是和现在产品要求直接冲突。

因此：

**整套“同步未 settled → 某些业务状态不写”的设计全部废弃。**

---

## 3.2 `ICLOUD_SYNC_REVIEW_ROUND3_2026-09-20.md`

Round3 很认真地验证了：

> 旧 convergence 方案有没有被代码正确实现。

所以报告中的：

“方案主体已落地且设计质量高”

只能解释为：

> 旧设计被实现得比较完整。

不能解释为：

> 当前产品目标已经达成。

Round3 仍然把：

* cloudDetached
* syncedWritesAllowed
* 双 store

视为合理架构。

因此这份文档以后只保留：

**历史审计证据**

不能继续作为目标架构。

---

## 3.3 `2026-09-20-baseline-capability-open-revision.md`

这份修订案已经正确发现：

* 只读错误
* sync settlement 不应该控制业务
* `.noAccount` 切库会让数据“消失”
* Habit watermark 问题
* 主动账号三选
* UI 状态缺失

这些结论继续有效。

但它仍然保留了两个关键旧前提：

### 错误前提 A：仍保留双 store

它仍然保留：

`Weekyii.store`

和：

`Weekyii.local.store`

并认为用户关同步时应该迁移数据库。

新的产品定义下：

**开关同步不能再切换数据库。**

---

### 错误前提 B：仍使用 SwiftData 自动 mirroring

它依旧依赖：

`ModelConfiguration.CloudKitDatabase.private`

作为同步引擎。

这导致 Weekyii 仍不能严格控制：

* retry 次数
* pause
* account switch
* quota 后停止
* 手动 sync

因此无法满足“失败以后停下来，由用户手动同步”的要求。

---

### 错误前提 C：merge 仍依赖 CloudKit 隐式 LWW

旧方案提出：

把本地写到 CloudKit store 后让 framework merge。

新目标下，“合并”必须具有明确产品语义。

不能把用户点击：

“合并”

解释为：

“交给 CloudKit 看着办”。

---

### 错误前提 D：关闭同步时 KVS 仍然运行

旧方案只考虑 SwiftData store。

没有把 `NSUbiquitousKeyValueStore` 纳入总同步开关。

---

### 错误前提 E：没有真正 StoreKit entitlement

旧方案的 cloudSyncEnabled 只有：

用户意图。

没有：

付费资格。

新的架构必须从类型层分开。

---

# 4. 最终目标架构

最终结构必须变成：

```
SwiftUI / ViewModels
         │
         ▼
  SwiftData local DB
   Weekyii.store
         │
         │  永远可写
         ▼
WeekyiiBusinessSnapshot
         │
         ▼
CloudSyncCoordinator
  │             │
  │             └── CloudSyncEntitlementService
  │
  ├── CloudSyncReconciler
  │
  ├── CloudSyncMetadataStore
  │
  └── CKSyncEngineTransport
                    │
                    ▼
           CloudKit Private DB
           WeekyiiSyncZoneV1
```

关键点：

**SwiftData 和 CloudKit 不再直接绑定。**

---

# 5. 新的同步域模型

新增：

`Services/CloudSyncTypes.swift`

建议核心状态如下。

## 5.1 用户意图

```
enum CloudSyncPreference {
    case off
    case on
}
```

实际可以继续存在 UserDefaults Bool：

`cloudSyncRequested`

默认：

`false`

---

## 5.2 entitlement

```
enum CloudSyncEntitlementState: Equatable {
    case checking
    case entitled
    case notPurchased
    case expired
    case notConfigured
    case verificationFailed(String)
}
```

不能使用：

`premiumThemeUnlocked`

---

## 5.3 account

```
enum CloudAccountState: Equatable {
    case unchecked
    case available(recordName: String)
    case noAccount
    case restricted
    case temporarilyUnavailable
    case failed(String)
}
```

仅当：

`cloudSyncRequested == true`

且 entitlement 有效时才需要主动解析账号。

---

## 5.4 用户可见同步状态

```
enum CloudSyncStatus: Equatable {
    case disabled
    case locked(CloudSyncEntitlementState)
    case checkingAccount
    case ready(lastSuccess: Date?)
    case syncing
    case synced(Date)
    case offline
    case quotaExceeded
    case accountUnavailable
    case accountDecisionRequired
    case pausedAfterFailure(String)
}
```

这些状态：

**不得被业务 ViewModel 用作写权限。**

---

## 5.5 Trigger

```
enum CloudSyncTrigger {
    case initialEnable
    case appLaunch
    case sceneActive
    case remoteNotification
    case networkRecovered
    case manual
    case entitlementRestored
}
```

---

# 6. 付费系统边界

当前没有完整购买弹窗体系。

本次不要为了赶进度伪造产品 ID。

新增：

`Services/CloudSyncEntitlementService.swift`

定义：

`CloudSyncEntitlementProviding`

生产实现最终使用 StoreKit 2 verified transaction。

但在实际 StoreKit product ID 尚未确定时：

生产状态返回：

`.notConfigured`

不得返回假 `.entitled`。

DEBUG 可以有：

`DeveloperCloudSyncEntitlementProvider`

用于后续开发调试。

必须：

`#if DEBUG`

且不能：

* 写入用户 archive
* 使用 `premiumThemeUnlocked`
* 进入 Release 默认逻辑

以后正式 StoreKit 接入时只替换 entitlement provider 和 paywall，不重新设计 persistence / CloudKit。

---

# 7. CloudKit 最终实现：显式 CKSyncEngine

由于部署目标已经是 iOS 18，新的同步层优先使用：

`CKSyncEngine`

而不是自己重新实现全部 zone token 管理。

要求：

**关闭 CKSyncEngine 的自动同步调度。**

Weekyii 自己决定：

什么时候：

* fetch
* send
* retry
* pause

如果当前 SDK 的具体 API 命名与计划示例有差异，以 Xcode 26.2 SDK 实际接口为准，但有一个不可改变的验收条件：

> CloudSyncCoordinator 不得把无限重试委托给业务循环。

---

# 8. CloudKit 数据结构

使用一个独立 custom zone：

`WeekyiiSyncZoneV1`

绝不能：

* 删除整个 private database
* 操作其它 App 数据
* 把 legacy `CD_*` record 当作新架构的数据区

建议使用一个统一 record type：

`WYEntityV1`

字段：

* `kind`
* `payloadVersion`
* `payload`
* `payloadHash`
* 可选 `blob`

所有普通结构数据：

JSON → `payload`

大二进制：

CKAsset → `blob`

这样 CloudKit schema 很稳定。

## 8.1 SwiftData Schema 与 Cloud Sync Protocol 完全解耦

`WeekyiiSchemaV8 / V9 / V10…` 与 `WeekyiiSyncZoneV1` **不是同一套版本系统**。
禁止建立这种机械映射：

```
SwiftData V9  ⇒  WeekyiiSyncZoneV2     // ❌ 禁止
```

### 三个互相独立的版本

| 版本 | 负责什么 |
|---|---|
| SwiftData schema version（`WeekyiiSchemaV8 → V9`） | 本机 SwiftData 数据结构与 migration |
| Cloud zone version（`WeekyiiSyncZoneV1`） | 第一代 Weekyii 显式 Cloud Sync Protocol 的 CloudKit 数据域 |
| Aggregate payload version（`task payloadVersion = 2` …） | **每一种 aggregate 各自维护**的 payload 版本 |

只要同步身份规则与整体协议仍可向后兼容，就**继续使用同一个 zone**。

### 普通模型字段升级的正确做法

如果 SwiftData 新增一个需要同步的字段：

1. 正常建立新的 SwiftData `VersionedSchema` / migration。
2. 更新对应 BusinessSnapshot DTO。
3. 对应 aggregate `payloadVersion += 1`。
4. decoder 兼容旧 payload。
5. **Cloud zone 不变。**
6. **CKRecord type 不变。**

### 本地专用字段

字段不需要跨设备 → **只改 SwiftData**。
不得因为本地字段变化去改 Cloud payload。

### 什么时候才考虑 `WeekyiiSyncZoneV2`

只有出现下列情况之一：

* record identity 规则整体改变；
* 现有 payload 无法安全向后读取；
* aggregate 边界发生全局重构；
* 旧、新同步协议无法安全共存；
* 原地 migration 成本明显高于新 zone migration。

**即使出现，也必须先写 migration plan。**
不能因为 SwiftData 开了 V9 / V10 就新建 zone。

---

# 9. Cloud record 身份

新增：

`SyncEntityKey`

由：

`kind + businessID`

组成。

> **`SyncEntityKey.description`（`"<kind>:<businessId>"`）是 Weekyii 的 logical key
> serialization，不是 CloudKit 的 `CKRecord.ID.recordName`。**
>
> 它是给人读的（日志、stored change log），不是 CloudKit 物理命名契约。
> Phase D 必须另做确定性的、安全的 **`CKRecordNameCodec`** ——
> 不得把 CloudKit record 命名绑到这个人类可读字符串上。

RecordName 必须确定性生成。

例如逻辑上：

* week / `2026-W39`
* day / `2026-09-21`
* task / UUID
* project / UUID
* habit / UUID
* habitDay / UUID
* taskType / idRaw
* attachment / UUID

但 RecordName 不要直接依赖未经处理的任意字符串。

实现统一 URL-safe / deterministic encoding。

同一个业务对象在所有设备必须得到同一个 CKRecord.ID。

---

# 10. 同步粒度

以下作为独立同步 aggregate：

* Week
* Day
* Task
* TaskAttachment
* Project
* MindStamp
* SuspendedTask
* SuspendedTaskAttachment
* TaskTypeDefinition
* Habit
* HabitDayRecord

`TaskStep`

不独立同步。

它是：

Task payload

或：

SuspendedTask payload

的一部分。

---

# 11. 不进入 CloudKit 的数据

以下保持设备本地：

* UserSettings
* cloudSyncRequested
* entitlement cache
* AppState
* systemStartDate
* lastProcessedDate
* notification permissions
* notification timing defaults
* theme
* language override
* recoveryPointRetentionCount
* developer settings
* Widget snapshot
* sync metadata
* sync retry state

**`HabitModel.generatedThroughDayId` 也不进入 CloudKit。** 它是 Phase B.5 要废掉的本地
水位线：Phase D **绝不**序列化它，也不得让它参与 incremental hash / dirty detection。
习惯的「这一天处理过没有」改由 `HabitDayRecord` 推导。

`DayModel.killTimeHour/Minute`

属于具体 Day 数据，因此仍作为 Day 业务对象同步。

这与默认 Kill Time 设置不同。

---

# 12. WeekyiiBusinessSnapshot

新增：

`Services/WeekyiiBusinessSnapshot.swift`

不要改变现有 archive format v1。

做法：

把 `DataArchiveService` 当前：

* WeekRecord
* DayRecord
* TaskRecord
* StepRecord
* AttachmentRecord
* ProjectRecord
* MindStampRecord
* SuspendedTaskRecord
* TaskTypeRecord
* HabitRecord
* HabitDayLog

抽出为共享 DTO。

## 12.1 Archive DTO ≠ Sync Snapshot DTO —— 必须分两层

原计划「把 DataArchiveService 的 Record DTO 提取出来**作为** `WeekyiiBusinessSnapshot`」需要**收窄**。

archive v1 是为**整包导出 / 整包恢复**设计的，它**不等于**新的 incremental sync aggregate：

* `TaskRecord` 内嵌 `steps` **和** `attachments`，而 `AttachmentRecord` 直接带 `Data?`
* `SuspendedTaskRecord` 同样内嵌 steps + attachments + Data

但新同步要求：Task 是一个 Cloud aggregate，`TaskAttachment` 是**独立** aggregate，
附件二进制走 `CKAsset`。

**如果直接复用 archive DTO，同一附件会同时出现在两处：**

1. Task 的 JSON payload 里
2. Attachment 的 CKRecord / CKAsset 里

**这是禁止的。**

### 两层各自的职责

#### 第 1 层：Archive compatibility DTO

保持 archive v1 的 JSON layout。`TaskRecord.attachments` **继续存在**。
**不能改变旧 archive format v1。**

#### 第 2 层：Normalized Business Snapshot

供 merge / hash / Cloud sync / legacy store consolidation 使用。至少包含：

* weeks / days / tasks / attachments / projects / mindStamps / suspendedTasks /
  taskTypes / habits / habitDayRecords

字段约束：

* `TaskSnapshot`：Task scalar data + steps + **attachment IDs**，**不含 attachment binary**
* `SuspendedTaskSnapshot`：同上，**不含附件二进制**
* `AttachmentSnapshot`：独立包含 id / owner / fileName / fileType / createdAt / blob(data)
* `MindStampSnapshot`：**必须区分 metadata/hash 与 image binary**；
  `CloudRecordCodec` 上传时 `imageBlob` 走 `CKAsset`

新增：

```
struct WeekyiiBusinessSnapshot
```

只包含业务数据。

`WeekyiiDataArchiveService.Payload`

仍然保持原有 JSON 字段布局。

它只是：

BusinessSnapshot

* SettingsRecord
* AppStateRecord

之间转换。

这样旧导出文件继续可读。

---

# 13. canonical 编码和 hash

同步需要判断：

“本地有没有改过”。

当前大部分 model 没有统一 updatedAt。

不要为了同步给 V8 所有 model 加 updatedAt。

使用已有 DTO：

canonical JSON encoding：

* `.sortedKeys`
* millisecondsSince1970

计算：

SHA-256

得到：

`localContentHash`

附件：

payload metadata hash

* blob SHA-256

共同形成 aggregate hash。

## 13.1 已冻结的两层哈希（Phase A 已落地）

* **blob hash** —— 附件字节 / 心智印记图片字节的 SHA-256。字节相同的两个附件共享
  同一个 blob hash，但它们仍是**两个实体**，合并后都存活。**blob hash 永远不是实体键。**
* **entity hash** —— 单个实体自身规范编码的 SHA-256。附件的编码**含** `blobSHA256`；
  **task 的编码只含附件 id** —— 所以无关的附件改动不会把 task 标脏。
* **SHA-256 是内容身份，不是权威。** 任何「哈希更大/更小者胜」的冲突规则都不允许出现；
  冲突一律走 local-first 的确定性规则。

## 13.2 编码的适用范围

`WeekyiiSnapshotCodec.encode(_:)` / `decode(_:)` 是**整快照**序列化，含附件与图片的
原始字节 —— 供本地快照文件、归档兼容、测试使用。

它**不是** CloudKit record payload encoder。Phase D 必须走 `CloudRecordCodec`：
metadata → 普通 record 字段，binary → `CKAsset`。

---

# 14. CloudSyncMetadataStore

新增：

`Services/CloudSyncMetadataStore.swift`

不要存进 SwiftData。

建议路径：

`Application Support/Weekyii/CloudSyncState/`

账号目录不能直接暴露 userRecordID。

用：

SHA-256(userRecordID)

作为目录。

保存：

* 当前绑定账号 hash
* CKSyncEngine state serialization
* 每个 `SyncEntityKey` 的 lastSyncedHash
* 必要的 server metadata
* lastSuccessfulSync
* lastAttempt
* lastFailure
* failure category
* automaticRetrySuppressed
* zone initialization state

写入必须：

atomic。

该目录：

不进入 Weekyii DataArchive。

---

# 15. local-first 冲突算法

这是新的核心。

对每个 Entity：

## 情况 A

本地没变
远端变了

→ 接受远端。

---

## 情况 B

本地变了
远端没变

→ 上传本地。

---

## 情况 C

两边新增不同 ID

→ 两边都保留。

---

## 情况 D

同 ID：

本地变了
远端也变了

→ **本地胜出。**

这是当前明确的 local-first 产品裁决。

同时记录：

conflict count

用于 diagnostics。

---

## 情况 E

本地删除
远端没变

→ 删除远端。

---

## 情况 F

远端删除
本地没变

→ 删除本地。

---

## 情况 G

远端删除
但本地从 baseline 后修改过

→ 本地胜出。

→ 重新创建远端。

## 关系重建（不得只拼 Codable 数组）

merge 与 apply 都**按 `SyncEntityKey` 逐实体**做，**不能对 archive JSON 整包 merge**。

规则：

* 不同 ID → union
* 相同 ID → local wins

**关系必须在 merge / apply 之后重建**，尤其：

* Day → Week
* Task → Day
* Task → Project
* Task → Habit
* Attachment → Task / SuspendedTask
* HabitDayRecord → Habit

不能只把 Codable 数组拼起来就完事 —— 数组里只有 id，关系是另一层。

---

# 16. 同步期间用户仍然可以继续编辑

这是非常重要的并发要求。

不能：

开始 sync 时抓一次 snapshot，然后网络回来以后无条件把远端覆盖进去。

在应用 remote change 前：

必须重新读取目标 entity 当前 local hash。

如果用户在网络等待期间已经修改：

currentLocalHash != baselineHash

则视为：

local changed

按 local-first：

不得覆盖。

---

# 17. session generation 防止迟到网络请求污染数据

`CloudSyncCoordinator`

维护：

`sessionGeneration`

每次以下事件发生：

* 用户关闭同步
* entitlement 失效
* Apple ID 切换
* 用户选择新账号处理方案
* 重建 sync session

generation 增加。

所有 async CloudKit operation 捕获自己的 generation。

网络完成后首先：

guard operationGeneration == currentGeneration

否则：

丢弃结果。

这样用户关同步以后：

迟到的 CloudKit fetch

不能再修改本地。

---

# 18. 同步 Trigger

正常情况下只允许这些自动 Trigger：

### 开启同步

一次。

### App 启动 / 进入前台

允许一次。

需要节流。

不能每次 SwiftUI redraw / minute tick 都同步。

### Cloud remote push

收到远端变化时允许一次。

### 网络从 offline → available

如果上次失败原因是网络：

允许一次。

### entitlement 从无效 → 有效

允许一次。

### 手动

用户点击：

“立即同步”

永远允许发起新的 cycle。

---

# 19. RetryPolicy

新增：

`Services/CloudSyncRetryPolicy.swift`

一次 sync cycle：

首次 request

加最多：

**2 次 transient retry**

即可。

建议退避：

第一次：根据 `CKErrorRetryAfterKey`，没有则约 1 秒。

第二次：约 4 秒。

设置最大等待上限。

不得长时间锁 UI。

---

## 不自动 retry

例如：

* quotaExceeded
* notAuthenticated
* permissionFailure
* account switch
* entitlement expired
* invalidArguments
* badContainer
* schema/configuration error

直接进入稳定错误态。

---

## transient

例如：

* networkUnavailable
* networkFailure
* serviceUnavailable
* requestRateLimited
* zoneBusy

cycle 内有限重试。

用完预算：

`.pausedAfterFailure`

---

## serverRecordChanged

不是普通网络 retry。

执行：

local-first conflict resolution。

当前 cycle 最多再发送一次。

---

## partialFailure

拆分每个 record。

只对 transient subset 使用剩余 retry budget。

terminal subset 立即形成失败状态。

---

# 20. failure latch

同步失败后不要：

sceneActive → retry
minute tick → retry
sceneActive → retry
minute tick → retry

形成隐性无限循环。

`CloudSyncCoordinator`

必须记住：

`automaticRetrySuppressed`

失败以后：

普通 sceneActive 不再触发。

解除 latch 的条件：

* 用户点“立即同步”
* 网络状态从 offline 真正恢复
* Apple ID 发生有意义变化
* entitlement 恢复
* 用户重新打开同步

quotaExceeded：

必须：

手动同步

或明确检测到相关条件变化后才重新尝试。

---

# 21. 开启同步的正确流程

用户点：

“启用 iCloud 同步”

不能立即修改 persistence。

流程：

1. 检查 entitlement。
2. 未购买：
   请求 paywall。
3. entitlement expired：
   显示续订入口。
4. entitlement notConfigured：
   明确显示当前支付模块未配置。
5. entitlement valid：
   查询 CKAccount。
6. account 不可用：
   保持 requested 状态或让用户取消，但本地不受影响。
7. account available：
   获取 userRecordID。
8. 打开/创建 `WeekyiiSyncZoneV1`。
9. Fetch 当前账号现有 Weekyii cloud snapshot。
10. 决定初次数据来源。

---

# 22. 初次开启时云端为空

如果：

远端 `WeekyiiSyncZoneV1` 不存在或为空。

UI：

“iCloud 中还没有 Weekyii 数据。是否将本机数据上传？”

选择：

* 上传本机数据并开启同步
* 取消

上传成功：

`cloudSyncRequested = true`

建立 baseline。

本地数据库从始至终没变化。

---

# 23. 初次开启时云端非空

不能自动 merge。

必须显示：

### 以本机数据为准

* 先抓取云端 staging snapshot
* 记录 diagnostics
* 用户确认
* 删除**WeekyiiSyncZoneV1**
* 重建 zone
* 上传当前本地 snapshot

注意：

只能删除：

Weekyii 自己的 custom zone。

不得删除：

整个 private database。

---

### 以 iCloud 数据为准

先：

`BackupRecoveryService.createSnapshot(Weekyii.store)`

然后：

把 remote snapshot 应用到本地业务数据。

UserSettings / AppState 不替换。

完成后：

建立 baseline。

---

### 合并本机与 iCloud

调用：

`WeekyiiSnapshotMergeService`

明确 merge。

不同 ID：

union。

同 ID：

local wins。

合并结果：

先写 canonical local store。

之后为了保证云端与本地完全一致：

删除并重建：

`WeekyiiSyncZoneV1`

上传 merged snapshot。

---

### 取消

`cloudSyncRequested = false`

本地不变。

---

# 24. Apple ID 切换

这是强制流程。

## 同步关闭

不监听或不消费账号变化。

零影响。

---

## 同步开启

检测：

A → B

立即：

1. `sessionGeneration += 1`
2. pause transport
3. `.accountDecisionRequired`
4. 本地继续正常使用
5. 不向 B 上传
6. fetch B 的 Weekyii custom zone 到 staging snapshot

然后弹出：

* 以本机数据覆盖 B
* 使用 B 云端数据
* 合并
* 关闭 iCloud 同步

不能只有设置页里才看得到。

应由：

`ContentView`

或 App 根层：

主动 sheet。

用户允许关闭 sheet。

如果关闭不选择：

本地继续正常使用。

云同步保持 paused。

状态条持续提醒。

---

# 25. A → B → A

每一次账号变化重新决策。

不能因为：

A 曾经用过

就自动继续。

元数据可以按账号分目录保存。

这样回到 A 时可以恢复 A 的 CKSyncEngine state。

但仍然需要确认：

当前 local 数据是否应该与 A 恢复同步。

---

# 26. 关闭同步

用户关闭 Toggle：

立即：

1. `cloudSyncRequested = false`
2. `sessionGeneration += 1`
3. 停止 Weekyii 发起新的 CloudKit 操作
4. 更新 UI `.disabled`
5. 保留所有 local data
6. 不 export
7. 不 import
8. 不换 store
9. 不要求重启

如果已有 network operation 无法真正 cancel：

它返回后由于 generation 失效：

不得 apply。

---

# 27. StoreKit 过期

如果用户同步开启中 entitlement 变：

`.entitled → .expired`

行为：

* invalidate sync session
* 不碰 local store
* 保留 cloudSyncRequested 用户意图
* UI 显示：
  “iCloud 同步已暂停：订阅已到期”
* 提供续订入口
* 所有 Weekyii 本地操作继续

续订成功：

允许一次恢复 sync。

---

# 28. quotaExceeded

映射 `CKError.quotaExceeded`。

行为：

* 不修改 local
* 不清空 cloud
* 不关闭用户数据
* latch 自动 retry
* UI 状态：
  `.quotaExceeded`

用户看到：

“iCloud 空间不足。本机数据已安全保存。”

按钮：

“立即同步”

让用户清理空间后再试。

---

# 29. UI 设计

## 设置页

替换当前：

`SettingsView.swift:685-1047`

旧：

* store transfer
* cloudDetached
* identity three-choice
* settled diagnostics

新结构：

### iCloud 同步

Toggle：

`cloudSyncRequested`

下面：

当前 entitlement。

当前 account。

当前 sync 状态。

最近成功同步时间。

最近失败原因。

按钮：

`立即同步`

如果：

quota：

显示空间不足。

如果：

offline：

显示“本机数据正常保存”。

如果：

expired：

显示续订。

如果：

account switch：

显示“需要确认数据来源”。

---

## 首页

`ContentView`

正常：

不显示同步噪音。

以下情况显示小型顶部状态：

* syncing
* offline with unsynced local changes
* quotaExceeded
* pausedAfterFailure
* accountDecisionRequired
* entitlement expired

不得：

遮挡任何业务操作。

不得：

disable Today / Pending / Project。

---

# 30. Remote Push

当前：

`Resources/Info.plist`

已经包含：

`UIBackgroundModes / remote-notification`

保留。

当前 Repo 没有完整：

`UIApplicationDelegateAdaptor`

远端 CloudKit push 处理。

新增：

`App/WeekyiiAppDelegate.swift`

以及：

`CloudRemoteNotificationRouter`

建立 `CKRecordZoneSubscription`。

收到 Weekyii zone push：

仅表示：

“远端可能有变化”。

它可以触发：

一次受 RetryPolicy 控制的 sync。

如果 failure latch 已开启：

不得因为 push 连续自动重试。

---

# 31. Phase A —— 抽出业务 Snapshot，保持现有行为不变

这是 Codex 第一个代码阶段。

**状态：已落地并通过独立审查（A0–A2）。行为已冻结 —— 不再重新设计、不再重开。**
Iteration 3 只做文档、注释与静态封口（见本节末尾「Iteration 3 的边界」）。

## 31.1 原始规格

新增：

* `Services/WeekyiiBusinessSnapshot.swift`
* `Services/WeekyiiSnapshotRepository.swift`
* `Services/WeekyiiSnapshotMergeService.swift`

修改：

* `Services/DataArchiveService.swift`

要求：

1. 把现有 Record DTO 提取出来。
2. DataArchive formatVersion 仍然是 1。
3. 老 archive JSON 继续可 decode。
4. `BusinessSnapshot` 不包含 UserSettings / AppState。
5. 实现 stable canonical encoding / SHA256。
6. 实现 deterministic merge：

   * distinct IDs union
   * same ID local wins
7. TaskStep 作为 Task aggregate。
8. Habit day logs 按 UUID 合并。
9. attachment 使用 UUID。

这一 Phase：

**不动当前 iCloud 运行行为。**

目的：

先建立后续所有迁移、CloudKit、账号选择共同使用的数据语言。

开发门禁：

* build
* archive existing regression tests
* round-trip archive
* merge unit tests

## 31.2 已落地并冻结的契约

后续 Phase 必须按这些契约写代码，**不要重新发明**。

### 身份

* `SyncEntityKind`：10 个 case，**FROZEN**（`week` / `day` / `task` / `suspendedTask` /
  `attachment` / `project` / `mindStamp` / `taskType` / `habit` / `habitDayRecord`）。
  只追加，永不改名 —— 改名等于让远端已存的 key 变成「删 + 增」。
* `SyncEntityKey`：`"<kind>:<businessId>"`，按**第一个**冒号切分（业务 id 自带冒号也能往返）。
  所有 UUID 一律用 `.uuidString`（**大写**），绝不转小写。
* `SyncEntityKey.description` 是 Weekyii 的 **logical key serialization**，
  **不是** CloudKit 的 `CKRecord.ID.recordName`。Phase D 必须另做确定性的
  `CKRecordNameCodec`，不得把 CloudKit 物理 record 命名绑到这个字符串上。
* 业务身份 ≠ 内容身份 ≠ SwiftData 行身份。这是三层，不要合并。
* `AttachmentOwner` 存在附件的 **payload** 里，不在 key 里 —— 把附件换到另一个 owner
  不改变它的身份。
* `TaskStep` **没有业务键**，内嵌在所属 task 的 snapshot 里。
* 快照只存 **child → parent** 链接；`WeekyiiBusinessSnapshot.init` 会把每个数组按
  `entityKey` 排序，所以编码结果与 SwiftData 返回行的顺序无关。

### 哈希：两层，永不合并

* **blob hash** —— 附件字节 / 心智印记图片字节的 SHA-256。两个字节相同的附件共享 blob hash，
  但它们仍是**两个实体**（身份是各自的 UUID），合并后都存活。blob hash **永远不是**实体键。
* **entity hash** —— 单个实体自身规范编码的 SHA-256。附件的编码**含** `blobSHA256`；
  而 **task 的编码只含附件的 id** —— 这正是「无关的附件改动不会把 task 标脏」的原因。
* **SHA-256 是内容身份，不是权威。** 任何「哈希更大/更小者胜」的规则都不允许出现。
* `UserSettings` / `AppState` **不进快照**：它们是 `UserDefaults` 上的单例，属设备本地状态，
  不随账号走。归档适配器把它们作为显式参数传入。

### 生产路径没有静默逃生口

* `WeekyiiSnapshotRepository.requireCleanSnapshot(from context: ModelContext)`：
  store 存在身份歧义时**抛错**（`WeekyiiSnapshotRepositoryError.ambiguousStore`，
  带上全部 diagnostics），绝不静默丢弃诊断继续产出「可同步快照」。
* **被删除的那个符号是 `WeekyiiSnapshotRepository.snapshot(from context: ModelContext)`**
  —— 它会吞掉 diagnostics。不要恢复它。
* ⚠️ 不要把它和**仍然存在**的 `WeekyiiSnapshotMergeService.snapshot(from payload:)`
  混为一谈：后者是**归档适配器**（`WeekyiiDataArchiveService.Payload` → snapshot），
  是另一回事，**必须保留**。

### merge 只是建筑块

* 入口名 `mergePreferringLocal(local:remote:)`。**故意非交换**：
  `mergePreferringLocal(local: a, remote: b)` 与 `(local: b, remote: a)` 结果不同。
* 它是 Phase E 收敛算法的**输入构造器**，不是分布式收敛算法本身。真正的收敛是
  Phase E 的 baseline 比较（本地 baseline vs 远端 delta vs 本地当前值）。
* 报告字段是 `localSnapshotChanged`（不是 `hasChanges`）。

### 资源身份（`TaskResourceIdentity`）

* `stepCopies` **保留** `createdAt`；重复保存不得让步骤时间漂移。
* `duplicatedAttachmentCopies` 铸造**全新身份**（新 UUID）—— 这是「复制」语义。
* `movedAttachmentCopies` **已删除**，不要恢复：它会新建 SwiftData 行却保留旧 UUID，
  未来调用者一旦没删原行，就会留下两行同一个业务 id。
* `SuspendedTask → Task` 用**同一 SwiftData resource row 的 re-parent**，不新建行。

### 序列化范围

* `WeekyiiSnapshotCodec.encode(_:)` / `decode(_:)` 序列化**整张快照，含附件与图片字节**。
  这是刻意的：本地快照文件、归档适配器、测试都需要一次无损整图往返。
* 它**不是** CloudKit payload encoder。Phase D 必须走 `CloudRecordCodec`：
  metadata → 普通 record 字段，binary → `CKAsset`。
* 之所以现在就能拆开，是因为 `entityHash` 把字节折成 `blobSHA256` 而不是字节本身 ——
  metadata 编码里从来就没有过 payload。

## 31.3 审查要求的四条修正（已全部落地）

| # | 修正 | 结果 |
|---|---|---|
| 1 | 生产路径不得有静默逃生口 | 删除 `snapshot(from:)`，改为 `requireCleanSnapshot` 抛错 |
| 2 | 不得用内容哈希决胜冲突 | `merge` → `mergePreferringLocal`；`hasChanges` → `localSnapshotChanged`；注释改写为「建筑块 + Phase E 收敛」 |
| 3 | 心智印记图片必须按 blob 参与 entity hash | 新增 `MindStampHashView`，`imageBlob` 以 `blobSHA256` 入 hash，不再整块进 metadata |
| 4 | 删除危险的 `movedAttachmentCopies` | 已删除；`duplicatedAttachmentCopies` 的回归测试**保留**（生产 API 仍在，就必须有直接覆盖） |

## 31.4 测试基线（已记录，后续不得静默降低）

`-only-testing:WeekyiiTests` **整个 target**：**9 个 suite / 317 个测试 / 0 失败，无任何排除**。

| suite | 用例数 |
|---|---|
| `ModelTests` | 162 |
| `NotificationServiceTests` | 13 |
| `StateMachineTests` | 50 |
| `SuspendedTaskLifecycleServiceTests` | 6 |
| `TaskPostponeServiceTests` | 22 |
| `TaskResourceIdentityTests` | 14 |
| `WeekCalculatorTests` | 4 |
| `WeekyiiSnapshotMergeServiceTests` | 26 |
| `WeekyiiSnapshotRepositoryTests` | 20 |

**`TaskPostponeServiceTests` 不再被排除。** 此前「它在模拟器上有既有崩溃」的判断是**错的**，
已实测推翻（单独跑 22/22，整 target 内也通过）。任何以「既有崩溃」为由排除 suite 的做法，
都必须先重新实测复现，否则不许排除。

反事实验证记录：

* A1 两轮破坏（6 处）→ 18 处断言失败 / 10 个用例变红；恢复后 317/317。
* A2 三轮破坏 → 15 处断言失败 / 7 个用例变红；恢复后 317/317。
* Iteration 2 的 8 项架构不变量变异 → 44 处断言失败 / 28 个用例变红；逐字节恢复后 317/317。

## 31.5 Iteration 3 的边界

只允许：

* 文档（本文件）
* 注释（`WeekyiiSnapshotCodec` 的序列化语义、`SyncEntityKey.description` 的边界）
* 静态清理（删除 `Features/Today/TodayView.swift` 上**既有**的一个尾随空格）

不允许：

* 任何行为实现
* 重跑 mutation testing（本轮没有新行为）
* 任何 `TodayView` 的语义改动

证据要求：`git diff --check` 全树 PASS，加一次构建。

## 31.6 Phase A 的实际执行切分：A0 / A1 / A2

Phase A 不是一步做完，而是三小步。顺序固定，**A0 不涉及 CloudKit**。

### A0 —— Resource Identity Stabilization

* attachment UUID 稳定
* attachment `createdAt` 稳定
* SuspendedTask → Task 的身份保留
* Step `createdAt` 稳定
* 不跨类型无意义重建
* 测试

### A1 —— Normalized BusinessSnapshot

* archive DTO 与 normalized DTO **分离**（见「Archive DTO ≠ Sync Snapshot DTO」）
* `AttachmentSnapshot` 独立
* Task / SuspendedTask **只持 attachment IDs**
* TaskStep 内嵌
* `SyncEntityKey`
* identity uniqueness validation

### A2 —— Merge / Hash

* canonical encoding
* entity hash
* blob hash
* deterministic local-wins merge
* relationship reconstruction
* Archive ↔ Normalized adapter
* archive v1 compatibility

**A2 完成后停止，等独立 review。**

## 31.7 Phase A 的 12 条历史验收边界

1. normalized `WeekyiiBusinessSnapshot`
2. `SyncEntityKey`
3. Attachment 与 Task / SuspendedTask 解耦
4. TaskStep 内嵌
5. archive v1 layout 不变
6. Archive ↔ Snapshot adapter
7. deterministic merge
8. relationship reconstruction
9. canonical encoding / hash
10. tests
11. **不改 persistence / CloudKit runtime**
12. **不删 `CloudSyncMonitor`**

第 11、12 条是 Phase A 的硬边界。`CloudSyncMonitor` 的退役属 Phase I（见「Phase I.2」）；
Phase B 只解除它对业务写权限与 persistence 生命周期的控制，**不删整个类型**。

## 31.8 A0 的测试要求

### Attachment

* 编辑 title → UUID 不变
* 编辑 steps → attachment UUID 不变
* 编辑 filename → UUID 不变
* 替换内容 → UUID 不变、blob hash 改变
* 删除 → UUID 消失
* 新增 → 新 UUID
* SuspendedTask → normal Task → UUID 不变
* 普通 postpone → Task / Attachment UUID 均不变

### Step

* 只改 Task title → `createdAt` 不变
* 只改 attachment → Step `createdAt` 不变
* reorder → `createdAt` 尽可能保留
* new Step → 新 `createdAt`

### Snapshot

同内容两个附件：

* blob hash 相同
* UUID 不同
* `SyncEntityKey` 不同
* merge 后两个都存在

## 31.9 资源重建的两条纪律

### 正常编辑不得 delete-all + recreate 附件

正常 Task update 必须**按 attachment UUID reconcile**：

1. `existingByID`
2. incoming 命中已存在 ID → **更新原 row**
3. incoming 是新 ID → 插入
4. missing ID → delete
5. 重建 relationship

这样：改 title 不重建附件；改 step 不触碰附件。

### 避免无意义重建 Step

1. normalized copy 保留 `createdAt`。
2. 只改 attachment 时**不重建 steps**。
3. 只改 title / description / type，steps 未变化时避免无意义重建。
4. 必要时用 value equality 判断是否 replace。

TaskStep **暂无 UUID**，继续作为父 Task / SuspendedTask aggregate 的内嵌数据。
复制现有 step 必须保留 `createdAt`，只有新增 Step 才产生新 `Date`。
不要求本轮新增 UUID，也**不需要 V9**。

> **历史背景（A0 修的就是这个）：** `normalizedStepCopies(from:)` 曾有**4 处独立实现**，
> 全都重建 `TaskStep(...)` 而**不保存 `createdAt`**，导致每次重建 timestamp 漂移。
> 受影响的 4 个文件是：
>
> * `Services/TaskPostponeService.swift`
> * `Features/Pending/PendingViewModel.swift`
> * `Features/Today/TodayViewModel.swift`
> * `Features/Week/DayDetailView.swift`
>
> A0 把它们统一为 `stepCopies` 并保留 `createdAt`。
> 而 `DataArchiveService.makeStep` **本来**就正确保留了 `createdAt`。

> 以后若需要 Step 独立多端冲突 / 单条 Step identity / 多端同时改同一 Step，
> 再考虑给 TaskStep 增加 UUID + 新 SwiftData schema。

## 31.10 Attachment UUID churn 的真实范围（不要记错）

**「每次 postpone 都会重建 attachment UUID」是不准确的。**

`TaskPostponeService.execute(...)` 后移已有 Task 时直接改 `task.day`，
**不调用 attachment copy**。所以普通 postpone：Task UUID 与 Attachment UUID **都保持**。

实际 churn 主要发生在：

* `TaskMutationService.replaceTaskResources`
* Task update
* SuspendedTask update
* 只改 steps 却连带 replace attachments
* 只改 attachments 却连带 replace steps
* `SuspendedTaskItem → TaskItem`
* `PendingViewModel` 相应的 copy 路径
* 其它 resource copy / edit 路径

## 31.11 `TaskAttachment` 稳定身份

至少修改：

* `Models/TaskAttachment.swift`
* `Services/TaskPostponeService.swift`
* `Features/Pending/PendingViewModel.swift`
* `Features/Extensions/ExtensionsViewModel.swift`

并检查**所有** `TaskAttachment(...)` copy 路径。

initializer **允许传 `id` 与 `createdAt`**；**不增加 persisted property**，
所以**不需要 V9**。

### move 与 duplicate 必须是两个不同的 API

* **move / re-parent**：保留身份（同 row）
* **duplicate**：铸造新身份（`UUID()`）

**禁止含糊的 copy 语义。** 不能因为 bytes 一样就沿用旧 ID。

### owner 变更的表现形式

`SuspendedTask(X) → Task(Y)` 在同步层应表现为 **Attachment owner update**，
**不是** old attachment delete + unrelated new attachment insert。

---

# 32. Phase B —— 单一 canonical local store

这是整个架构最关键阶段。

修改：

`App/WeekyiiPersistence.swift`

最终删除：

* `.production`
* `.localOnly`
* `.cloudDetached`

作为 cloud 语义。

建议 StoreMode 收敛为：

* `.persistent`
* `.inMemory`

或者直接删除 StoreMode，仅测试保留 `inMemory` 参数。

正式 `ModelConfiguration`：

`cloudKitDatabase: .none`

正式 URL：

始终：

`Weekyii.store`

删除：

* `resolveStoreMode`
* `launchStoreMode`
* `cloudKitContainerIdentifier` 对 persistence 的影响
* `makeDetachedReadOnlyCopy`
* detached caches
* `allowsSave: false`
* IdentityResolution 在 persistence 层的旧实现
* 双 store 日常切换

保留：

* backup
* archive recovery
* SwiftData migration plan
* Schema V8

---

# 33. Phase B.1 —— Legacy Weekyii.local.store 合并

不能简单删除旧文件。

新增：

`Services/LegacyStoreConsolidator.swift`

启动前检查：

`Weekyii.local.store`

如果不存在或无业务数据：

跳过。

如果 canonical `Weekyii.store` 为空：

把 legacy local business snapshot 导入 canonical。

如果两者都有数据：

先：

双方建立 recovery snapshot。

然后使用：

`WeekyiiSnapshotMergeService`

构建安全 union。

由于旧双 store 没有可信公共 ancestor：

不能伪造精确三方 merge。

默认策略：

* 不同 ID 全保留
* 同 ID local-first
* 生成 migration report

如检测到高风险冲突：

例如同一 Day/Week 主体状态明显分叉：

保留 recovery point 并记录 diagnostics。

完成后：

验证 canonical snapshot。

再把 legacy store 移动到：

`LegacyStores/`

或保留 recovery point 后删除 active legacy 文件。

加 migration completion key。

这条路径只执行一次。

---

# 34. Phase B.2 —— 删除所有业务写闸门

修改：

* `Services/StateMachine.swift`
* `Services/TaskPostponeService.swift`
* `Features/Today/TodayViewModel.swift`
* `Features/Today/TodayView.swift`
* `Features/Pending/PendingViewModel.swift`
* `Features/Pending/PendingView.swift`
* `Features/Pending/PendingWeekDetailView.swift`
* `Features/Week/WeekViewModel.swift`
* `Features/Week/WeekOverviewView.swift`
* `Features/Extensions/ExtensionsViewModel.swift`
* `Features/Extensions/HabitViewModel.swift`
* `Features/Extensions/MindStampViewModel.swift`
* `Features/Extensions/ExtensionsView.swift`
* `Features/Extensions/ExtensionsHubView.swift`
* `App/ContentView.swift`
* `App/WeekyiiApp.swift`

全仓最终要求：

`grep syncedWritesAllowed`

零命中。

`grep allowsSyncedWrites`

零命中。

`grep allowsPersistenceWrites`

零命中。

`grep persistenceReadOnly`

零业务命中。

StateMachine：

所有本地业务 reconcile 无条件正常执行。

TaskPostpone：

完成语义无条件写。

Today：

完成日无条件写。

Habit：

本地正常物化。

---

# 35. Phase B.3 —— 启动不再等待 iCloud

修改：

`App/WeekyiiApp.swift`

删除当前：

`.resolving → accountStatus → userRecordID → resolveStoreMode`

启动关键路径。

新顺序：

1. legacy local migration（如需要）
2. 打开 `Weekyii.store`
3. seed
4. local repair
5. 进入 UI
6. App ready 后异步启动 CloudSyncCoordinator

没有 Apple ID：

照常进 App。

飞行模式：

照常进 App。

CloudKit API 卡死：

照常进 App。

---

# 36. Phase B.4 —— 移除 KVS

> **归属已裁决：KVS 移除属于 Phase B.4，不得提前到 Phase A。**
>
> 当前 `Resources/UserSettings.swift` **确实仍在双向使用 KVS**：`ubiquitousDefaults`
> 读优先（构造期 `synchronize()` 后取 shared 值）、写入时 `set` + `synchronize()`、
> 监听 `NSUbiquitousKeyValueStore.didChangeExternallyNotification`、并处理外部变更。
>
> 这是**上一份计划 C.2 项已落地的结果，不是遗漏**。它随 Phase B
> 「唯一 canonical local store + 清除云对本地运行状态的影响」一起删，
> 不要跨阶段单独动它。

修改：

`Resources/UserSettings.swift`

删除：

* `NSUbiquitousKeyValueStore`
* synchronize
* didChangeExternallyNotification
* external kill-time apply

默认 Kill Time 回到纯设备本地。

修改：

`Resources/Weekyii.entitlements`

删除：

`com.apple.developer.ubiquity-kvstore-identifier`

保留：

* CloudKit
* APS
* App Group

---

# 37. Phase B.5 —— Habit watermark 与幂等修正（Phase D 硬前置）

> **排序已裁决：Habit 修正前移到 Phase D 之前，成为硬前置。**
>
> 原因不只是「`generatedThroughDayId` 不得进入 `WeekyiiSyncZoneV1`」，而是它
> **连未来的 incremental hash / dirty detection 都不该污染**：一个靠 LWW 就能回退的
> 本地水位线字段，会让「这个习惯今天处理过没有」在多端之间来回翻转，
> 从而制造重复物化。这个问题闸门挡不住。

## 37.1 现状（已核实）

| 位置 | 现状 |
|---|---|
| `Models/HabitModel.swift` | `var generatedThroughDayId: String = ""` —— 仍是**存储字段** |
| `Services/HabitTaskMaterializer.swift` | `assignToday` 写（取 `max`）；`sync` / `advanceWatermark` 读它做守卫、再写它 |
| `Features/Extensions/HabitViewModel.swift` | 编辑排程时**回拨**水位线 |
| `Services/DataArchiveService.swift` | 归档 DTO 携带该字段 |
| `Services/WeekyiiSnapshotRepository.swift` | 归一化时把它填进 `HabitSnapshot` |
| `Services/WeekyiiSnapshotMergeService.swift` | merge 与归档适配器都会消费 / 回填它 |

也就是说：**它现在确实在同步面上。**

## 37.2 目标

「这个习惯这一天处理过没有」改由 **`HabitDayRecord` 推导**：

* 读：`habit.records.contains { $0.dayId == day }`（或等价谓词）
* `generatedThroughDayId`：**V8 中保留字段，但停止读写** → 零 schema 变更，**不需要 V9**
* `HabitTaskMaterializer` 不再读写它
* `HabitViewModel` 不再回拨它

必须保持的语义：

* 用户删除今天已生成的习惯任务后，**当天不自动复活** ——
  靠 `HabitDayRecord` 仍然存在来保证，不再靠水位线。
* 跨日仍由新日期重新评估。

## 37.3 硬约束

* **Phase D 绝不序列化 `generatedThroughDayId`。** 它不得进入 `WeekyiiSyncZoneV1`、
  不得进入 record payload、也不得参与 incremental hash / dirty detection。
* 本 Phase 完成后，Phase D 才允许进入「active Cloud record encoding」。

## 37.4 对照测试（必须带「改回缺陷必须失败」证据）

* 故意把 `generatedThroughDayId` 改小、或直接删掉 → **仍不重复物化**。
* 把判据改回存储字段 → **必须失败**。
* 删除当天生成的习惯任务 → 当天不复活；跨日重新评估。

---

# 38. Phase C —— entitlement + preference

新增：

* `Services/CloudSyncEntitlementService.swift`
* `Services/CloudSyncTypes.swift`

修改：

`Resources/UserSettings.swift`

把：

`cloudSyncEnabled`

迁移成：

`cloudSyncRequested`

默认 false。

兼容旧 key：

升级时读取旧值时**不要自动开启新 CloudKit 引擎**。

旧 `cloudSyncEnabled == true`

只能作为 legacy 信息。

新的显式 CloudKit engine 首次使用仍要求用户确认。

原因：

旧 true 是自动 mirroring 时代产生的，不能解释成用户已经同意新同步语义。

### 升级语义（逐条）

* **新安装**：`cloudSyncRequested = false`
* **老安装**，且只存在旧 `cloudSyncEnabled`：
  * `cloudSyncRequested = false` —— **不继承旧 true**
  * 写一次 migration marker：**`weekyii.cloudSyncPreferenceMigratedV2`**
  * Settings **可以**显示一次**非阻断**提示：

    > iCloud 同步方式已更新。如需继续多设备同步，请重新开启 iCloud 同步。

  * **不得**自动创建 `WeekyiiSyncZoneV1` —— 直到用户主动开启

否则升级后会**未经重新确认**就进入新 custom-zone sync。

---

# 39. Phase D —— Cloud transport

新增：

* `Services/CloudSyncTransport.swift`
* `Services/CKSyncEngineTransport.swift`
* `Services/CloudRecordCodec.swift`
* `Services/CloudSyncMetadataStore.swift`
* `Services/CloudSyncRetryPolicy.swift`

要求：

1. private database。
2. `WeekyiiSyncZoneV1`。
3. explicit sync。
4. automatic scheduling off。
5. persistent engine state。
6. deterministic CKRecord.ID。
7. attachment / MindStamp image 使用 CKAsset。
8. temp CKAsset file 必须清理。
9. zone / subscription 创建幂等。
10. transport 本身不知道 SwiftUI。

这一阶段：

先使用 fake/local transport unit test。

不要立刻把真实 CloudKit 接入 App UI。

---

# 40. Phase E —— CloudSyncReconciler

新增：

`Services/CloudSyncReconciler.swift`

职责：

* build local snapshot
* build local manifest
* fetch remote delta
* classify local/remote changes
* local-first conflict
* remote apply
* local send
* tombstone
* metadata baseline update

必须支持：

* insert
* update
* delete
* concurrent local editing
* attachments
* remote deletion
* serverRecordChanged

原则：

只有成功同步的 entity 才推进自己的 baseline。

失败 entity：

保持 pending。

不要做“整轮全成功才更新所有 manifest”的脆弱事务。

## 40.1 apply 顺序约束（不得随机顺序写 SwiftData）

显式 sync 有实体依赖关系。**不得**按任意顺序把 remote records 写进 SwiftData。

### Upsert 推荐顺序

1. TaskTypeDefinition
2. Week
3. Day
4. Project
5. Habit
6. SuspendedTask
7. Task
8. HabitDayRecord
9. Attachment
10. MindStamp

也可以两遍走：

* 第一遍：create / update entities
* 第二遍：resolve relationships

### Delete

删除**不能机械反转** upsert 顺序。

必须先形成一份一致的：

`ReconciliationPlan`

再**集中 apply**。保证 parent delete 之后，child **不会又被重新插回来**。

---

# 41. Phase F —— CloudSyncCoordinator

新增：

`Services/CloudSyncCoordinator.swift`

`@Observable` / MainActor 管 UI 状态。

协调：

* preference
* entitlement
* account
* transport
* reconciler
* retry policy
* failure latch
* session generation

修改：

`WeekyiiApp.swift`

注入 coordinator。

Scene active：

只给 coordinator 一个 trigger。

绝不能重新连接到 StateMachine 写闸门。

---

# 42. Phase F.1 —— 初次 enable

实现第 21-23 节流程。

设置页旧：

store transfer

完全删除。

同步 Toggle 不再：

export current store
import another store
request restart

新 Toggle：

只控制 cloud session。

开关不需要重启。

---

# 43. Phase G —— 账号切换

新增：

`CloudAccountResolutionContext`

`CloudAccountResolutionChoice`

例如：

* useLocal
* useCloud
* merge
* disable

修改：

`ContentView`

主动 sheet。

新增 staging remote snapshot。

不得创建第二个业务 SwiftData store。

staging：

只用 DTO / temp files。

---

# 44. Phase H —— 故障、手动同步和 UI

修改：

`Resources/SettingsView.swift`

新增：

* Sync Now
* last success
* last failure
* entitlement status
* account status
* quota
* retry state

修改：

`ContentView.swift`

状态 pill/banner。

新增本地化字符串到：

`Resources/Localizable.xcstrings`

本轮新 UI 禁止继续硬编码中文。

---

# 45. Phase H.1 —— Remote push

新增：

`WeekyiiAppDelegate`

处理 remote notification。

push：

触发一次 `.remoteNotification`。

不意味着：

必须成功。

如果失败：

显示错误。

不要 push → retry → push → retry 无限循环。

---

# 46. Phase I —— 收尾阶段

本阶段处理：

1. consistency validation
2. 删除旧 CloudKit mirroring 架构
3. 测试与文档清理

> **Habit watermark 修正已前移为 Phase B.5，不再属于 Phase I。**
> 见「Phase B.5 —— Habit watermark 与幂等修正（Phase D 硬前置）」。
> Phase D 进入 active Cloud record encoding 以它完成为硬前置。

---

# 47. Phase I.1 —— consistency validation

当前：

`validateContainerConsistency`

多个 present week：

直接 throw → App failed。

改为：

本地 repair + diagnostics。

只有真正：

* store 无法打开
* migration 失败
* SQLite/persistence 损坏

才能进入 PersistenceFailureView。

业务数据不一致：

不得阻断 App 启动。

---

# 48. Phase I.2 —— 删除旧 CloudKit mirroring 架构

最终删除：

`Services/CloudSyncMonitor.swift`

如果其中还有可复用 UI error mapping：

迁移到新类型后删文件。

## 48.1 Phase I-0：`CloudSyncMonitor` retirement（原子步骤）

**`CloudSyncMonitor` 不允许孤立删除。** 它当前是一个具有完整编译依赖图的类型。

### 当前直接源码依赖（至少 5 处）

* `App/WeekyiiApp.swift`
* `App/ContentView.swift`
* `Resources/SettingsView.swift`
* `Features/Today/TodayView.swift`
* `Tests/ModelTests.swift`

### pbxproj 登记点（**4 处**，删文件必须同批清理）

1. `PBXBuildFile`
2. `PBXFileReference`
3. Group children entry
4. Sources build phase entry

> 项目**未**使用 Xcode 16 的 `PBXFileSystemSynchronizedRootGroup`，
> 所以手工清理这 4 处登记项是必要的。

### 必须按顺序执行

1. `WeekyiiApp.swift` 已完全迁移到 `CloudSyncCoordinator`：
   删除 `CloudSyncMonitor` state/property、`start()`、`refreshAccountStatus()`、
   `importRevision`、launch account/status/userRecordID resolution、`markContainerLoaded()`、
   旧 `identityConfirmed` 生命周期。
2. `ContentView.swift`：不再读取 `CloudSyncMonitor`；不再调用 `syncedWritesAllowed(...)`；
   新状态 UI 只用 `CloudSyncCoordinator.status`。
3. `TodayView.swift`：删除 `@Environment(CloudSyncMonitor.self)` 与 `syncedWritesAllowed(...)`；
   Today 业务不再接收任何 Cloud 权限。
4. `SettingsView.swift` 已全部迁移到新 Coordinator。必须显式替换 / 删除的旧接口：
   * `cloudSyncMonitor.state`
   * `cloudSyncMonitor.lastFailureDetail`
   * `cloudSyncMonitor.settlement(...)`
   * `cloudSyncMonitor.identityConfirmed`
   * `cloudSyncMonitor.currentUserRecordID`
5. **重写** `ModelTests.swift` 中所有 `CloudSyncMonitor` 测试 —— **不是简单删除**。
   特别是 2026-09-20 新增的诊断行为 `inFlightSetupEventIdentifiers` 与 `lastFailureDetail`：
   若对应产品需求在新架构仍成立（「保留最近失败原因」、
   「多个并发操作不能让 UI 错误显示成功」），应**迁移**为
   `CloudSyncCoordinator` / `CKSyncEngineTransport` 的新测试。
   旧 `NSPersistentCloudKitContainer.Event` 实现细节测试删除。
6. 全仓确认 `CloudSyncMonitor` 只剩 `Services/CloudSyncMonitor.swift` 与 Xcode project reference。
7. 删除 `Services/CloudSyncMonitor.swift`。
8. 同批修改 `Weekyii.xcodeproj/project.pbxproj`，删掉上面 4 处登记。
9. Build。
10. 全仓 `grep CloudSyncMonitor` **只能命中历史 docs**，
    不得命中 active source / active tests / pbxproj。

### 时序硬约束

`CloudSyncMonitor.swift` 的删除**必须发生在 Phase F / H 完成替代实现之后**。

**不得提前在 Phase B 删除整个类型** —— 当前 Settings / UI / account diagnostics 仍依赖它。
Phase B 只负责解除它对业务写权限与 persistence 生命周期的控制。

## 48.2 同批删除的其它旧实现

删除：

* NSPersistentCloudKitContainer eventChangedNotification
* settlement
* syncedWritesAllowed
* identityConfirmed 旧模型
* lastSyncedUserRecordIDKey 旧用途
* pendingIdentityResolutionKey
* old IdentityResolution
* cloudDetached
* detached read-only copy
* old store transfer
* restart-required sync flow
* initializeCloudKitDevelopmentSchema 的旧 SwiftData mirroring 版本

`WeekyiiPersistence.swift`

最终可以不再：

`import CloudKit`

也不再 DEBUG import CoreData 为 CloudKit schema initialization。

---

# 49. Legacy CloudKit records

> **已裁决（RESOLVED）：旧自动 SwiftData/CloudKit 同步只在内部 TestFlight / 开发阶段使用过，
> 从未真正面向生产用户发布。**
>
> 由此：
>
> * **不需要** production `CD_*` → `WeekyiiSyncZoneV1` 的迁移桥。
> * 不把 legacy CD schema 当作新产品数据源。
> * 仍然**不得**在这一轮代码里擅自删除 legacy production CloudKit 数据。
>
> 这个事实不再需要 Codex 猜；以本节裁决为准。
>
> **因此 Phase I 的 `PRODUCT_DECISION_REQUIRED` 硬停点已取消。**
> 它只存在于「产品历史未知」这一前提之下，而该前提已被本节裁决取代。
> **不要重新激活这个停点。**
>
> 具体口径：
>
> * 不建设生产级 `CD_* → WeekyiiSyncZoneV1` migration bridge；
> * 不把旧 `CD_*` records 当作正式数据来源；
> * 不为兼容内部测试数据延续 automatic mirroring；
> * 保留旧 CloudKit 数据即可，本次**不主动删除**；
> * 新架构上线后，以当前设备的 canonical `Weekyii.store` 作为旧测试安装的数据来源；
> * Phase I 可以清理旧 automatic mirroring 代码。

当前自动 SwiftData CloudKit 会产生：

`CD_*`

record。

新 engine 使用：

`WYEntityV1`

以及：

`WeekyiiSyncZoneV1`

但代码设计必须保证：

旧 CD 数据和新 custom zone 不互相覆盖。

---

# 50. 当前开发阶段不等于最终验证阶段

用户已经明确：

目前先完成完整代码。

所以各 Phase 只需要“开发门禁”。

开发门禁包括：

* build
* build-for-testing
* 针对本阶段的 unit tests
* git diff --check

不要求现在完成：

* 双真机最终矩阵
* App Store 沙盒完整购买
* quota 真机故障注入
* A/B 两 Apple ID TestFlight 全验收

这些属于：

最终代码闭合后的 Release Validation Phase。

---

# 51. 但是每一阶段必须补回归测试

这不是最终验收，而是防止 Codex 把旧错误重新写回来。

必须覆盖：

## Persistence

* formal container 永远 `.none`
* production 不存在 `.private(...)`
* canonical URL 永远 Weekyii.store
* no cloud status influences store URL

## Business availability

模拟：

* no account
* offline
* quota error
* expired entitlement
* sync failure

业务 create/edit/delete 仍正常。

## Preference

默认 false。

## Disabled

sync off：

不 query account。

不调用 CloudKit transport。

## Merge

本地和远端相同 ID：

local wins。

不同 ID：

union。

## Delete conflict

remote delete + local edit：

local survives。

## Session generation

关 sync 后迟到 network result：

不能 apply。

## Retry

超过 retry budget：

进入 paused。

不能自动继续。

---

# 52. 旧测试必须主动清理

当前 ModelTests 仍断言：

* cloudDetached read-only
* temporarilyUnavailable → cloudDetached
* localOnly → Weekyii.local.store
* identity mismatch closes sync write gate

这些测试属于旧架构。

不能为了“让老测试绿”保留错误设计。

应删除或重写。

---

# 53. AppHealthCoordinator 最终职责

保留：

* local state transitions
* notifications
* Habit materialization
* Widget
* Live Activity
* diagnostics

删除：

Cloud settlement 权限。

最终：

`AppHealthCoordinator`

甚至不需要知道：

CloudSyncCoordinator

是否存在。

这是一条重要完成标准。

---

# 54. Widget

Widget 当前从：

App Group snapshot

读取。

这是正确设计。

不要让 Widget 接 CloudKit。

Cloud remote change：

应用到 local store

→ local widget snapshot refresh

即可。

---

# 55. Notification

通知继续纯本地。

Cloud sync 不直接 schedule notification。

remote data apply 后：

正常 App reconcile

再重排通知。

---

# 56. DataArchive

保留为：

人工导出 / 恢复工具。

不能把 DataArchive 变成 CloudKit transport。

但：

DTO / snapshot layer 可以复用。

人工 restore：

仍然允许完整 replace。

Cloud incremental sync：

不得每次 `deleteAllData + insert`。

---

# 57. 性能要求

正常 local 操作：

不能等待 CloudKit。

Sync：

网络操作必须 async。

不要在主线程：

* hash 大附件
* CKAsset 文件准备
* CloudKit request
* 大型 snapshot JSON 编码

SwiftData snapshot extraction / apply：

放在安全 ModelContext actor / MainActor 边界。

网络阶段使用 detached value DTO。

---

# 58. 数据安全要求

以下操作必须先建 recovery point：

* 云端完整覆盖本机
* local + cloud merge 后整体替换本地
* legacy 双 store consolidation
* 人工 DataArchive restore

普通 incremental remote update：

不需要每一个 record 都做全库 snapshot。

---

# 59. Diagnostics

新的 diagnostics 至少包含：

* cloudSyncRequested
* entitlement state
* account state
* sync status
* account hash（不得输出完整 recordName）
* zone initialized
* last success
* last attempt
* last failure category
* retry count
* pending local change count
* pending deletion count
* conflict count
* session generation
* metadata version

不得泄露：

完整 Apple user record ID。

---

# 60. 新文件总表

**Phase A 已落地**（3 个；每个都已按 4 处 pbxproj 注册进 target）：

* `Services/WeekyiiBusinessSnapshot.swift`
* `Services/WeekyiiSnapshotRepository.swift`
* `Services/WeekyiiSnapshotMergeService.swift`

**后续阶段建议新增：**

* `Services/LegacyStoreConsolidator.swift`
* `Services/CloudSyncTypes.swift`
* `Services/CloudSyncEntitlementService.swift`
* `Services/CloudSyncTransport.swift`
* `Services/CKSyncEngineTransport.swift`
* `Services/CloudRecordCodec.swift`
* `Services/CloudSyncMetadataStore.swift`
* `Services/CloudSyncRetryPolicy.swift`
* `Services/CloudSyncReconciler.swift`
* `Services/CloudSyncCoordinator.swift`
* `App/WeekyiiAppDelegate.swift`

必要时拆：

`CloudAccountService.swift`

和：

`CloudRemoteNotificationRouter.swift`

---

# 61. 主要修改文件总表

必须重点修改：

* `App/WeekyiiPersistence.swift`
* `App/WeekyiiApp.swift`
* `App/ContentView.swift`
* `Resources/UserSettings.swift`
* `Resources/SettingsView.swift`
* `Resources/Weekyii.entitlements`
* `Resources/Localizable.xcstrings`
* `Services/DataArchiveService.swift`
* `Services/StateMachine.swift`
* `Services/TaskPostponeService.swift`
* `Services/HabitTaskMaterializer.swift`
* `Models/WeekyiiError.swift`
* `Features/Today/TodayView.swift`
* `Features/Today/TodayViewModel.swift`
* `Features/Pending/PendingView.swift`
* `Features/Pending/PendingViewModel.swift`
* `Features/Pending/PendingWeekDetailView.swift`
* `Features/Week/WeekOverviewView.swift`
* `Features/Week/WeekViewModel.swift`
* `Features/Extensions/ExtensionsView.swift`
* `Features/Extensions/ExtensionsHubView.swift`
* `Features/Extensions/ExtensionsViewModel.swift`
* `Features/Extensions/HabitViewModel.swift`
* `Features/Extensions/MindStampViewModel.swift`
* `Tests/ModelTests.swift`
* `Tests/StateMachineTests.swift`

以及相关 CloudKit/Sync 新测试。

---

# 62. 明确不做的事情

本计划不允许 Codex：

1. 继续修补 `.cloudDetached`。
2. 创建 `.cloudUnsynced` 作为新 StoreMode。
3. 再增加第五/第六种 SwiftData store mode。
4. 继续使用 `Weekyii.local.store` 作为产品运行模式。
5. 把网络状态传给业务 ViewModel。
6. 把 entitlement 传给业务 ViewModel 决定写权限。
7. 用 `premiumThemeUnlocked` 当购买凭证。
8. 给 `cloudSyncEnabled` 默认 true。
9. 用 CloudKit LWW 冒充显式“合并”。
10. 用户关同步时清本地数据。
11. 用户关同步时要求重启。
12. quota 时进入只读。
13. offline 时进入只读。
14. 账号不明时进入只读。
15. sync failure 时停止 StateMachine。
16. 为了同步修改 V8 frozen schema，除非出现不可避免的新业务字段且另开 V9 方案。
17. 删除 legacy production CloudKit 数据。
18. 为 legacy `CD_*` 造 production 迁移桥（已裁决：仅内部 TestFlight/开发使用过，不需要桥）。
19. 把 KVS 移除提前到 Phase A（它属 Phase B.4）。
20. 让 Phase D 序列化 `generatedThroughDayId`（Phase B.5 是它的硬前置）。
21. 把 `SyncEntityKey.description` 当成 CloudKit 的 `CKRecord.ID.recordName`。
22. 把 `WeekyiiSnapshotCodec.encode(_:)` 当成 CloudKit record payload encoder。

---

# 63. Phase 执行依赖

严格顺序：

### Phase A

BusinessSnapshot + Merge 基础。

**已通过审查，行为冻结。**

↓

### Phase B

唯一 local store + 删除所有业务 sync gate + 移除 KVS（Phase B.4）。

↓

### Phase B.5

Habit watermark 与幂等修正。

**这是 Phase D 的硬前置：它不完成，Phase D 不得进入 active Cloud record encoding。**

↓

### Phase C

Entitlement + preference。

↓

### Phase D

显式 CloudKit transport。

↓

### Phase E

Local-first reconcile algorithm。

↓

### Phase F

Coordinator + enable / disable / initial sync。

↓

### Phase G

Apple ID switch。

↓

### Phase H

Retry / quota / manual sync / UI / push。

↓

### Phase I

consistency validation + 删除旧 CloudKit mirroring 架构 + docs/test cleanup。

（Habit watermark 已移出 Phase I，见 Phase B.5。）

B 与 C 之间可以按依赖关系微调，但 **B.5 必须早于 Phase D 生效**。

不能：

Phase A 没完成就直接做 CloudKit DTO。

不能：

Phase B 没完成就继续扩旧 StoreMode。

不能：

Phase B.5 没完成就让 Phase D 进入 active Cloud record encoding。

不能：

Phase E 没有确定性 merge 就做账号切换。

---

# 64. Codex 工作方式

Codex 每次只执行一个 Phase。

完成后返回：

```
[C2C]
STATE: EXECUTED
TASK_ID: c2c_local_first_paid_icloud
PHASE: <phase>
ITERATION: <n>

CHANGED_FILES:
...

RESULT:
...

BEHAVIOR_CHANGE:
...

MIGRATION:
...

TESTS:
...

BUILD:
...

RISKS:
...

NEXT_EXPECTED_STEP:
Independent review before next phase.
```

不要一个任务直接把 A-I 全部改完。

原因：

这是 persistence + sync architecture 重构。

必须逐层审查。

---

# 65. Phase A 的直接 Codex 指令

第一轮只执行：

**Phase A**

也就是：

* 抽 Record DTO
* BusinessSnapshot
* SnapshotRepository
* SnapshotMergeService
* 保持 archive v1 compatibility
* 补 unit test
* 不动当前 iCloud runtime

目标是先建立新的数据抽象。

完成以后停。

等待独立 review。

---

## 65.1 已完成的迭代

| 迭代 | 内容 | 结果 |
|---|---|---|
| A0–A2 / Iteration 1 | 三个 service + 归档适配 + 单测 | 完成 |
| A0–A2 / Iteration 2 | 审查要求的四条修正 + 8 项架构不变量变异验证 | **代码通过审查** |
| A0–A2 / Iteration 3 | 只做文档、注释、静态封口 | 本轮 |

## 65.2 Iteration 3 的唯一任务

1. 把主计划与增量修订 1 / 2 / 3 合并进本文件。
   **⚠️ 这一条未完成核对，不得报为已完成。** 增量 1 / 3 的专有条款
   （`cloudSyncPreferenceMigratedV2`、`Reconciliation`、`normalizedStepCopies`、
   `TaskMutationService`、`assignTask`、§I / §L / §N 的条款）在本文件中 **0 命中**；
   增量 2 在**全仓与记忆里都没有记录**。状态见文首「增量修订的并入状态」。
2. 澄清 `WeekyiiSnapshotCodec` 的序列化语义：整快照 `encode` / `decode` 含原始字节，
   但**不是** CloudKit record payload encoder；Phase D 走 `CloudRecordCodec`
   （metadata → 普通字段，binary → `CKAsset`）。
3. 澄清 `SyncEntityKey.description` 是 Weekyii 的 logical key serialization，
   **不是** `CKRecord.ID.recordName`；Phase D 另做确定性的 `CKRecordNameCodec`。
4. Habit watermark 排序修订（前移为 Phase B.5，Phase D 硬前置）。
5. 只删除 `Features/Today/TodayView.swift` 上**既有**的那一个尾随空格。
6. `git diff --check` 全树 PASS。

不引入行为实现，不重跑 mutation testing。证据：静态检查 + 一次构建。

封口被独立核对通过后，才可以开始 Phase B。

---

# 66. 最终完成标准

代码层：

* `Weekyii.store` 是唯一业务 store。
* SwiftData 正式 container 永远 `.none`。
* `Weekyii.local.store` 不再作为运行模式。
* `cloudDetached` 零命中。
* `syncedWritesAllowed` 零命中。
* `allowsSyncedWrites` 零命中。
* cloud-derived `allowsPersistenceWrites` 零命中。
* `persistenceReadOnly` 不再用于 Cloud 状态。
* StateMachine 不认识 CloudSync。
* Habit 不依赖 generatedThroughDayId 做同步水位。
* UserSettings 不再使用 KVS。
* cloud sync 默认关闭；启用由设备本地 `cloudSyncRequested` 显式表达。
* Cloud sync 当前向所有用户开放；保留 `CloudSyncEntitlementProviding` 抽象，生产 provider 返回 `.entitled`。
* 当前不接入 StoreKit、付费墙、商品 ID 或购买校验；未来商业 entitlement 通过替换/inject provider 接入。
* CloudKit 使用 explicit custom zone。
* failure 有稳定 UI。
* quota 不影响 local。
* account switch 不影响 local。
* sync off 不查询/消费 Apple ID。
* manual sync 可触发一次新 cycle。
* app-level retry 有明确上限。
* sync on/off 不换数据库、不重启。

产品层：

用户可以永远把 Weekyii 当纯本地 App 用。

这是最高优先级。

iCloud 是用户明确开启后使用的多设备复制能力。开放访问只代表用户有资格使用，不代表自动开启。

只要这一句话在任何代码路径上不成立，就说明实现仍未完成。

---

# 67. 本文与旧文档的关系

**本文已正式落仓于
`docs/plans/2026-09-21-local-first-paid-icloud-sync-execution-plan.md`，
它是后续阶段的唯一权威执行规格。**

* `.workbuddy-ai/memory/` 下的会话摘要只是**过程记录**，**不得**作为执行依据。
* 旧 plan 保留为历史证据，不再作为实现目标。

> 当前产品政策以 Phase C 裁决和 Phase I 最终状态（§70）为准：云同步向所有用户开放，用户选择仍是必要条件。下文或归档材料中的“付费”表述属于历史方案，不是当前行为。

从本文开始：

`2026-09-19-icloud-sync-convergence.md`

状态：

**历史设计，已废弃为执行目标。**

`ICLOUD_SYNC_REVIEW_ROUND3_2026-09-20.md`

状态：

**旧实现审计记录，仅保留历史证据。**

`2026-09-20-baseline-capability-open-revision.md`

状态：

**部分问题判断继续有效，但最终架构已被本文取代。**

继续有效的结论包括：

* 删除业务同步写闸门
* 删除只读保护
* Habit watermark 修复
* 同步状态需要 UI
* 账号变化必须主动询问
* adoptCloud / overwriteCloud 当前语义有问题

被本文替换的方向包括：

* 双 store
* `.cloudUnsynced`
* SwiftData automatic CloudKit mirroring
* storeMode 表达云状态
* CloudKit implicit LWW merge
* 关闭同步做数据库迁移

---

# 68. 最终 C2C 控制消息

```
[C2C]
STATE: PLANNED
TASK_ID: c2c_local_first_paid_icloud
ITERATION: 0

WORKSPACE:
Weekyii

BRANCH:
online-chatgpt-develop

SOURCE_OF_TRUTH:
Current dirty working tree. Do not reset or overwrite unrelated changes.

GOAL:
Rebuild iCloud as an optional paid explicit remote-sync layer over one authoritative local SwiftData store.

HARD_INVARIANTS:
- Weekyii.store is the only authoritative business database.
- SwiftData production persistence is local-only.
- Cloud state never gates business writes.
- Sync defaults OFF.
- Disabling sync never swaps databases.
- Cloud failures never block local use.
- Account changes while sync is OFF have zero product effect.
- Account changes while sync is ON pause cloud activity before user resolution.
- App-level retries are bounded.
- Manual Sync Now exists.
- premiumThemeUnlocked is not a cloud entitlement.

SUPERSEDES:
docs/plans/2026-09-19-icloud-sync-convergence.md
docs/plans/2026-09-20-baseline-capability-open-revision.md as implementation target

RESOLVED_DECISIONS:
- Legacy CD_* automatic sync was internal TestFlight/dev only. No production migration bridge.
- KVS removal belongs to Phase B.4. Do not pull it into Phase A.
- Habit generatedThroughDayId correction is a hard prerequisite for Phase D.
- A2 merge keeps deterministic local-preference. It is a building block, not convergence.
- SyncEntityKey.description is NOT a CloudKit recordName.
- WeekyiiSnapshotCodec.encode is NOT a CloudKit payload encoder.

EXECUTION_ORDER:
A -> B -> B.5 -> C -> D -> E -> F -> G -> H -> I

CURRENT_STATE:
Phase A (A0-A2) code approved. Incremental revisions 1/2/3 plus the post-review amendments are merged with a closed coverage checklist (no UNKNOWN).

NEXT_EXPECTED_STEP:
Phase A is CLOSED. Start Phase B (single canonical local store).
```

---

# 69. 附录：增量修订覆盖清单（已闭合）

原文归档：`docs/plans/2026-09-21-incremental-revisions-archive-and-merge-ruling.md`

状态含义：

* `PRESENT` —— 本文件已有等价或更完整的条款
* `MERGED_EQUIVALENT` —— 本文件以不同措辞完整承载了该语义
* `SUPERSEDED_BY <条款>` —— 已被后续产品事实或 Review 裁决取代，**不要重新激活**

**共 42 项，无 UNKNOWN。**

## 69.1 Revision 1（A–N，14 项）

| # | 条款 | 状态 | 落点 |
|---|---|---|---|
| A | `CloudSyncMonitor` 不允许孤立删除；5 处源码依赖；pbxproj 登记；原子退役步骤 | `PRESENT` | Phase I.2 / 48.1 |
| B | §2.12 确认成立（用本机 store 判空冒充远端判空） | `PRESENT` | 2.12 |
| C | §2.13 确认成立（`premiumThemeUnlocked` 不是可信 entitlement） | `PRESENT` | 2.13 |
| D | Archive DTO ≠ Sync Snapshot DTO，必须分两层 | `PRESENT` | 12.1 |
| E | `DataArchive` ↔ Snapshot adapter，formatVersion 仍为 1 | `PRESENT` | 12 |
| F | Snapshot identity 在 Phase A 锁定（10 类映射；TaskStep 无独立键） | `PRESENT` | 9 / 31.2 |
| G | merge 按 normalized aggregate 做；关系必须重建 | `PRESENT` | 15「关系重建」/ 31.2 |
| H | Phase E apply 顺序 1–10 + 两遍 + `ReconciliationPlan` | `PRESENT` | 40.1 |
| I | Phase E 网络等待期间二次校验 local hash | `PRESENT` | 16 |
| J | 旧 `cloudSyncEnabled` 升级语义 + `weekyii.cloudSyncPreferenceMigratedV2` | `PRESENT` | 38「升级语义（逐条）」 |
| K | V8 冻结与 legacy `CD_*` 是两个问题 | `PRESENT` | 2.15 / 49 |
| L | Phase I 原始 `PRODUCT_DECISION_REQUIRED` 硬停点 | `SUPERSEDED_BY` 49 产品裁决（停点已取消） | 49 |
| M | 其余原则不变（12 条） | `MERGED_EQUIVALENT` | 1（R1–R10 不变量，措辞不同） |
| N | Phase A 原始 12 条执行边界 | `PRESENT` | 31.7 |

## 69.2 Revision 2（O–P，2 项）

| # | 条款 | 状态 | 落点 |
|---|---|---|---|
| O | SwiftData Schema 与 Cloud Sync Protocol 完全解耦；per-aggregate `payloadVersion` | `PRESENT` | 8.1 |
| P | Legacy automatic CloudKit 产品裁决 | `PRESENT` | 49 |

## 69.3 Revision 3（Q–AJ，20 项）

| # | 条款 | 状态 | 落点 |
|---|---|---|---|
| Q | pbxproj **4 个**登记点同批清理 | `PRESENT` | 48.1 |
| R | Attachment UUID churn 的真实影响范围（普通 postpone 不 churn） | `PRESENT` | 31.10 |
| S | `TaskAttachment.id` 是唯一逻辑身份；不得用 `SHA256(data)` 作键 | `PRESENT` | 31.2 |
| T | `AttachmentSnapshot` 结构（id/owner/fileName/fileType/createdAt/blob） | `PRESENT` | 12.1 / 31.2 |
| U | metadata hash vs blob hash 的分工 | `PRESENT` | 13.1 / 31.2 |
| V | Phase A0（Resource Identity Stabilization）先于 A1 / A2 | `PRESENT` | 31.6 |
| W | `TaskAttachment` 稳定身份；4 个待改文件；init 允许传 id/createdAt；不需 V9 | `PRESENT` | 31.11 |
| X | 正常编辑不得 delete-all + recreate 附件；按 UUID reconcile | `PRESENT` | 31.9 |
| Y | SuspendedTask → Task 是 resource move（同 row re-parent） | `PRESENT` | 31.11 / 31.2 |
| Z | 真 duplicate 必须新 UUID；move 与 duplicate 两个 API | `PRESENT` | 31.11 |
| AA | `normalizedStepCopies` 不保留 `createdAt`；4 处受影响文件 | `PRESENT` | 31.9 |
| AB | Phase A0 稳定 TaskStep（保留 `createdAt`；不加 UUID / V9） | `PRESENT` | 31.9 / 31.6 |
| AC | 避免无意义重建 Step（4 条最低要求） | `PRESENT` | 31.9 |
| AD | Task aggregate hash 只含 scalar + ordered steps + attachment IDs | `PRESENT` | 31.2 |
| AE | SuspendedTask 同一规则；owner 变更表现为 owner update | `PRESENT` | 31.11 |
| AF | SnapshotRepository 唯一性校验；`requireCleanSnapshot` 拒绝生成 syncable snapshot | `PRESENT` | 31.2 / 31.3 |
| AG | Phase A 最终内容（A0 / A1 / A2 各自范围） | `PRESENT` | 31.6 |
| AH | Phase A0 测试要求（Attachment / Step / Snapshot 三组） | `PRESENT` | 31.8 |
| AI | Legacy automatic CloudKit 最终裁决 | `PRESENT` | 49 |
| AJ | 最终身份原则（business / content / persistence 三层） | `PRESENT` | 31.2 |

## 69.4 后续 Review 覆盖项（6 项）

| # | 条款 | 状态 | 落点 |
|---|---|---|---|
| 1 | merge 不使用 hash 决胜；保留 `mergePreferringLocal` | `PRESENT` | 31.2 / 31.3 |
| 2 | MindStamp `imageBlob` 是 blob（metadata hash 用 byte count + SHA-256） | `PRESENT` | 31.2 / 13.1 |
| 3 | whole snapshot `encode` ≠ Cloud payload `encode` | `PRESENT` | 13.2 / 31.2 |
| 4 | `SyncEntityKey.description` ≠ `CKRecordName`；Phase D 另做 `CKRecordNameCodec` | `PRESENT` | 9 / 31.2 |
| 5 | Habit watermark 前移为 Phase B.5（Phase D 硬前置） | `PRESENT` | 37 |
| 6 | KVS 归属 Phase B（`Phase B.4`），不进 Phase A | `PRESENT` | 36 |

# 70. Phase I 最终实现与验证状态

本节记录当前代码所表达的最终架构与 Phase I 执行结果。它取代本文早期“付费 + 用户选择”的当前产品措辞；历史设计记录保留原样作为迁移证据。

## 70.1 最终架构事实

- 唯一运行时业务数据源是 `Application Support/Weekyii/Weekyii.store`；SwiftData 配置使用 `cloudKitDatabase: .none`。
- 云同步由用户设备本地的 `cloudSyncRequested` 显式开启，默认 `false`。当前产品政策允许所有用户使用；生产 entitlement provider 为 `.entitled`，`CloudSyncEntitlementProviding` 保留为未来替换点。
- 当前没有 StoreKit、付费墙、商品 ID、购买验证或购买状态 gating。entitlement 不会自动开启同步，也不改变本地存储可用性。
- 显式 CloudKit transport 使用私有数据库、自定义区 `WeekyiiSyncZoneV1` 和记录类型 `WYEntityV1`，经 `CloudSyncCoordinator`、`CloudSyncReconciler` 与 `CKSyncEngineTransport` 工作。
- `WeekyiiSyncZoneV1` 外的旧 `CD_*` 记录保持未触碰；没有生产迁移桥，也没有全私有数据库删除路径。
- 本地 SwiftData 是唯一业务事实源。离线、无账号、配额、同步失败、推送缺失或 entitlement 状态不会禁止本地启动和业务写入。
- 冲突按既定 local-first merge 规则处理；远端变更先进入持久 inbox，应用与 acknowledgement 按既定协调流程完成。
- 账号身份使用哈希、活动账号哈希和决策 journal；账号切换保留显式决策与 session generation 校验，不持久化原始 Apple record ID 作为身份基线。
- app-level retry 有界；终态失败 latch 保留可见失败状态；网络恢复只解除网络类 latch；push 用于提示同步引擎，不取代 reconciliation，也不自动清除终态错误。
- `CloudSyncMonitor` 自动镜像架构已退役。AppHealthCoordinator、StateMachine 与本地业务写路径不依赖 Cloud 状态。
- 启动时的持久化打开、迁移、整合及必要修复保存失败仍为致命错误；业务一致性问题由 bootstrap 诊断报告，不会仅因业务状态不一致使启动进入 `.failed`。

## 70.2 Phase I 验证记录

执行分支：`online-chatgpt-develop`。本轮仅执行 Phase I，没有开始后续开发阶段。

- Phase I focused regressions：79 passed，0 failed。
- 完整 `WeekyiiTests`：463 passed，0 failed。
- Debug build：通过。
- `build-for-testing`：通过。
- Release build：通过。
- `plutil`（Xcode project、Info.plist、entitlements）、`jq empty`（Localizable.xcstrings）与 `git diff --check`：通过。
- `WeekyiiUITests`：未运行；已知 Pending-month 问题在本阶段范围外。
- 实机双设备 CloudKit/APNs 验证：未运行，留待 Release Validation。
- 编译器仍有测试目标中的 Swift 并发提示（notification router 测试的冗余 `await` 和若干 XCTest assertion 对 MainActor 隔离类型的调用）。本轮所触及的 HabitViewModel 与 WeekyiiSnapshotRepository 应用代码告警已修正；未扩大范围改写无关测试。
- 工作区内与本任务无关的既有改动保持原样。

独立最终复审尚待执行。本节记录已执行的实现和验证，不表示 Phase I 已获独立验收或 CLOSED。

## 70.3 Phase I 静态搜索门禁

计数范围：活动源码为 `App/Features/Resources/Services/Models/Shared`；测试为 `Tests/WeekyiiUITests`；文档为 `docs/**/*.md`。`pbxproj` 单独计数。下表记录字面出现次数：

| 搜索项 | 活动源码 | 测试 | pbxproj | 文档 | 解释 |
|---|---:|---:|---:|---:|---|
| `CloudSyncMonitor` | 0 | 0 | 0 | 66 | 仅历史文档 |
| `cloudDetached` | 0 | 0 | 0 | 104 | 仅历史文档 |
| `syncedWritesAllowed` | 0 | 0 | 0 | 49 | 仅历史文档 |
| `allowsSyncedWrites` | 0 | 0 | 0 | 18 | 仅历史文档 |
| `allowsPersistenceWrites` | 0 | 0 | 0 | 7 | 仅历史文档 |
| `identityConfirmed` | 0 | 0 | 0 | 29 | 仅历史文档 |
| `currentUserRecordID` | 0 | 0 | 0 | 8 | 仅历史文档 |
| `lastSyncedUserRecordIDKey` | 0 | 0 | 0 | 5 | 仅历史文档 |
| `pendingIdentityResolutionKey` | 0 | 0 | 0 | 5 | 仅历史文档 |
| `IdentityResolution` | 0 | 0 | 0 | 27 | 仅历史文档 |
| `NSPersistentCloudKitContainer` | 0 | 0 | 0 | 11 | 仅历史文档 |
| `eventChangedNotification` | 0 | 0 | 0 | 2 | 仅历史文档 |
| `initializeCloudKitDevelopmentSchema` | 0 | 0 | 0 | 3 | 仅历史文档 |
| `-initializeCloudKitSchema` | 0 | 0 | 0 | 9 | 仅历史文档 |
| `NSUbiquitousKeyValueStore` | 0 | 0 | 0 | 10 | 仅历史文档 |
| `StoreKit` | 0 | 0 | 0 | 18 | 仅历史文档 |
| `Weekyii.local.store` | 9 | 9 | 0 | 35 | 源码与测试命中只在 `LegacyStoreConsolidator` 及迁移覆盖 |
| `cloudKitDatabase: .private` | 0 | 0 | 0 | 1 | 该拼写不存在；显式 CloudKit 使用 `privateCloudDatabase`（源码 2 处） |
| `generatedThroughDayId` | 8 | 16 | 0 | 50 | 本地/归档兼容语义；Cloud codec/hash 不编码该水位 |
| `CD_` | 0 | 0 | 0 | 26 | 只在历史文档，代码没有 legacy Cloud record 读取或迁移桥 |

其他架构定位：`WeekyiiSyncZoneV1` 在活动源码/测试共 3 处；正式 SwiftData 配置显式使用 `.none`。旧 Monitor 的四个 pbxproj 登记均为 0。
