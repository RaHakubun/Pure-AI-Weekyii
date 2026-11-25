# 基础能力全开 —— iCloud 同步收敛方案修订案

> 修订对象：`docs/plans/2026-09-19-icloud-sync-convergence.md`（v3.2）  
> 修订依据：用户 2026-09-20 裁决的产品原则  
> 状态：**待执行**（本文只给方案，未改代码）
>
> **修订记录**
> - **v2（2026-09-20，用户指出两处错误后重推）**：
>   1. 术语纠正 —— 数据层是 **SwiftData**，本文此前把底层持久化栈称作 "Core Data" 是错的（§1.6）。
>   2. **V2 撤销** —— 原 V2 把 `cloudKitDatabase` 当成 store 元数据，据此提出的"硬阻塞项"不成立（§1.6）。
>   3. **设计收窄** —— 重推后确认"离线/额度满/暂时不可用"**不需要**新状态（§1.5），
>      `.cloudUnsynced` 的适用面收窄到"身份存疑"；**`.cloudDetached` 只读态整体废除**（§1.1），
>      连带删掉 `makeDetachedReadOnlyCopy` 与 `allowsSave: false` 整套机制。
>      净效果：StoreMode 仍是 4 态，但**没有任何状态是只读的**。

---

## 0. 修订动因

### 0.1 用户裁决原文

> 不管有没有网络、有没有 iCloud 账号，都必须要能够支撑 Weekyii 软件的全部操作。  
> 同步功能本身就是锦上添花的附加功能，不可以影响整个 App 完整的基础能力，必须全开。  
> 只是说，当账号可用的时候要开启 iCloud 后台同步。

### 0.2 由原则推出的四条硬约束

| #      | 约束                                                                                              |
| ------ | ----------------------------------------------------------------------------------------------- |
| **R1** | 基础能力 = 建周 / 建日 / 建任务 / 编辑 / 删除 / 完成 / 开始执行 / 流转 / 后移 / 过期 / 习惯物化 / 重复合并 / GC。**这些在任何情况下都必须可用。** |
| **R2** | **身份存疑（`identityConfirmed == false`）必须"不挂 CloudKit + 可写 + 主动问用户"**，而**不是**只读。v1 曾把这一条写成"唯一允许的只读条件"，v2 已推翻：只读同样是"阻断操作"，违反 R1。护栏靠"不挂载"而不是"不让写"。 |
| **R3** | "同步是否静止"（`settlement`）**不得**作为任何写入闸门。它最多只能驱动同步状态的 UI 展示。                                        |
| **R4** | iCloud 同步只在账号可用时后台挂载。账号不可用时，**App 照常工作，只是不同步**。                                                 |

### 0.3 v3.2 现状与原则的冲突点

| #  | 冲突                                                                                                                               | 位置                                                      |
| -- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| C1 | `.temporarilyUnavailable` / `.couldNotDetermine` / 查询抛错 → `.cloudDetached`（**全只读**），而 Apple 对该状态的原文是"账号是 available 的，不要删除任何缓存数据" | `WeekyiiPersistence.swift:136-139`                      || C2 | `syncedWritesAllowed`（= "同步静止"）被当成 Tier-2 的开关，而"同步静止"要求有网络 → 判据退化成"有网络才能跑系统派生"                                                   | `StateMachine.swift:108-131`、`WeekyiiApp.swift:461-464` |
| C3 | `setupSucceeded` 是闸门条件，而 `.setup` 需要网络 → 断网时 `settlement()` 恒 `unsettled` → Tier-2 永久不跑                                          | `CloudSyncMonitor.swift:336-338`                        |
| C4 | `.noAccount` → `.localOnly`（**换文件**）→ 退出 iCloud 的用户打开 `Weekyii.local.store`，若该文件为空则**首页空白**，`Weekyii.store` 里的数据"消失"             | `WeekyiiPersistence.swift:134-135`、`:256-261`           |
| C5 | 文档自相矛盾：§11 line 1541 把 `accountStatus` 描述为"同步、无网络"，§13.2 line 1687 却要求"飞行模式冷启动 → 只读态"                                            | 文档                                                      |
| C6 | `maxWait`（§7.2.1 的占位页上界）**未实现**，`PersistenceResolvingView` 无超时 → 账号查询卡住则 App 永久停在转圈页                                             | `WeekyiiApp.swift:890-904`                              |

**C1 与 C3 是"同步不可用 → 基础能力被锁"的直接来源；C4 是"数据看起来丢了"的严重来源。**

---

## 1. 目标状态

> **v2 修订（2026-09-20，用户指出术语与定性错误后重推）**：本节初版提出"四态扩五态"，
> 并为新增的 `.cloudUnsynced` 挂了一个"V2 硬阻塞项"。重推后确认：**初版把"离线"误判成需要新状态，
> 从而自造了 V2。** 正确结论是 —— **`.cloudUnsynced` 仍然需要，但它的适用面从"账号不可用"收窄到
> "身份存疑"，而且 `.cloudDetached`（只读）应当被它取代、整个只读机制可以删除。**
> 详见 §1.5。

### 1.1 StoreMode：`.cloudDetached`（只读）被 `.cloudUnsynced`（可写）取代

```swift
enum StoreMode: Equatable {
    case production      // Weekyii.store       + .private(id)  可写 —— 同步开启且身份一致
    case localOnly       // Weekyii.local.store + .none        可写 —— 用户主动关闭同步 / XCTest
    case cloudUnsynced   // Weekyii.store       + .none        可写 —— 【取代 .cloudDetached】身份存疑
    case inMemory        // 内存               + .none        可写 —— UI 测试
}
```

**`.cloudDetached` 整体删除**，连带删除的机制：

- `makeDetachedReadOnlyCopy(of:)`（`WeekyiiPersistence.swift:224-250`）+ `Caches/Weekyii/DetachedStores/<pid>/` 目录管理
- `makeModelContainer` 的 `.cloudDetached` 分支（`:179-201`）—— 含"无云库文件时退回内存只读"的兜底
- `allowsSave: false` 这条路径本身（全仓唯一使用点是 `:187` / `:198`）
- 四层只读防线里的第 3、4 层（`ModelConfiguration.allowsSave` + 只读副本）
- 因只读而存在的 UI 缺口修复（原 §2.9：`DraftEditorView.swift:132` 温度开关、`:182` 左滑删除）
- `ModelTests.swift:124-174`（`test_cloudDetachedContainerIsReadOnlyWithoutChangingStoreFiles`）

### 1.2 属性取值

```swift
var cloudKitContainerIdentifier: String? {
    switch self {
    case .production: return WeekyiiPersistence.cloudKitContainerIdentifier
    case .localOnly, .cloudUnsynced, .inMemory: return nil
    }
}

var hasNoRemotePeer: Bool {
    switch self {
    case .localOnly, .inMemory: return true
    case .production, .cloudUnsynced: return false
    }
}

var allowsSave: Bool {
    // v2：不再有 false 分支。R1「任何情况都能操作」在类型层面成立，
    // 无法被后续改动悄悄破坏 —— 这是"让缺陷无法表示"。
    true
}
```

> `allowsSave` 保留为计算属性（而非直接删掉）是为了把改动面收在 `StoreMode` 内部，
> 避免一次性重写 `TodayView` / `TodayViewModel` / `PendingViewModel` / `ExtensionsViewModel`
> 里所有 `allowsSave` / `allowsPersistenceWrites` 调用点。它们的值恒为 `true`，
> 行为上等价于"闸门消失"，但删除调用点是后续独立清理项（见 §2.6 备注）。

### 1.3 `resolveStoreMode` 新映射表

```swift
static func resolveStoreMode(
    environment: [String: String],
    accountStatus: CKAccountStatus?,
    identityConfirmed: Bool = true,
    cloudSyncEnabled: Bool = true
) -> StoreMode {
    if environment["XCTestConfigurationFilePath"] != nil { return .localOnly }
    guard cloudSyncEnabled else { return .localOnly }        // 用户主动关闭 → 走显式迁移流程
    guard identityConfirmed else { return .cloudUnsynced }   // 唯一需要"不挂 CloudKit"的场景

    // 账号状态不再影响 store 选择：挂不上就挂不上，写入照常。
    return .production
}
```

**全表：**

| `accountStatus`                                            | `identityConfirmed` | `cloudSyncEnabled` | 落点                 | 可写 | CloudKit       | 说明                                                    |
| ---------------------------------------------------------- | ------------------- | ------------------ | ------------------ | -- | -------------- | ----------------------------------------------------- |
| `.available`                                               | true                | true               | `.production`      | ✅  | `.private(id)` | 正常同步                                                  |
| `.available`                                               | **false**           | true               | **`.cloudUnsynced`** | ✅  | `.none`        | **不挂 CloudKit（否则把 A 的记录传到 B）+ 主动弹窗**                  |
| `.noAccount` / `.restricted`                               | true                | true               | **`.production`**  | ✅  | `.private(id)` | ← **改**：原为 `.localOnly`（换文件 → C4 空白页）。挂载失败无妨，写入照常 |
| `.temporarilyUnavailable` / `.couldNotDetermine` / 抛错 / 超时 | true                | true               | **`.production`**  | ✅  | `.private(id)` | ← **改**：原为 `.cloudDetached`（全只读）。Apple 原文说此状态账号是 available 的   |
| 任意                                                         | 任意                  | **false**          | `.localOnly`       | ✅  | `.none`        | 用户主动关闭同步                                              |

**关键改动是"账号状态不再参与 store 选择"。** 这一条同时消掉了 C1、C3、C4：

- **C1**：`.temporarilyUnavailable` 不再落只读态，与 Apple 原文（"账号是 available 的，不要删除任何缓存数据"）一致。
- **C4**：`.noAccount` 不再切到 `Weekyii.local.store`，"退出 iCloud 后首页空白"的路径消失。
- **C3**：`setupSucceeded` 依赖网络，但闸门删除后它不再影响任何写入（见 §2.2）。

### 1.4 与 #16 / #18 的关系（必须明示，不是推翻）

- **#16（独立 store 文件）保留。** `.localOnly` 仍指向 `Weekyii.local.store`，用户主动关闭同步仍走
  §7.1.1 的显式迁移（快照 + 导入）。#16 禁止的是"在云库文件上以 `.none` 建可写数据，日后登录即隐式合并"。
- **`.cloudUnsynced` 是否违反 #16？** 形式上命中"在云库文件上以 `.none` 建可写数据"，
  但 #16 担心的隐式合并**不会发生**，因为本状态**只由身份存疑触发**：
  - CloudKit 未挂载 → 本次运行物理上不可能上传；
  - 本状态必然伴随主动弹窗，用户必须显式三选；
  - 三个选项各自的动作都是**整体重写**（`importReplacing` = `deleteAllData` + `insert`），
    不存在"靠 CloudKit 增量导出把两边拼起来"的路径（见 §1.6）。
- **#18（未登录设备切库）改判。** #18 原意是"未登录设备必须可用时，切到独立 store"。
  新映射表用"不切库 + 挂载失败无所谓"达到同一目的，且额外保住数据可见性
  （#18 的切库会让用户看到空 App —— 见 C4）。这是一次有意的改判，需同步修订 #18 的裁决记录。

### 1.5 为什么"离线 / 额度满 / 暂时不可用"**不需要**新状态

初版把这一类场景当成 `.cloudUnsynced` 的主要理由，是错的。三条依据：

1. **`CKContainer.accountStatus()` 是本地判断，不需要网络。** 它的语义是"系统能否访问用户的 iCloud 账号"，
   离线时设备自己知道账号状态 → 已登录 + 飞行模式返回 `.available`。
   所以"断网"根本走不到任何降级分支，`resolveStoreMode` 返回 `.production`。
2. **`.production` 本来就是可写的。** `allowsSave` 对 `.production` 恒为 `true`（`WeekyiiPersistence.swift:41-48`）。
3. **CloudKit mirroring 是异步且失败可容忍的。** `CloudSyncMonitor` 存在的意义就是"观察失败"，
   而不是"失败就阻止写入"。挂载失败不影响 SwiftData 往本地 SQLite 落数据。

**结论：离线、额度满、暂时不可用 —— 一律 `.production`，写入照常，同步自己重试。**

> ⚠️ 第 1 条仍需真机确认一次（原 V1）。但它已不是设计分叉点：
> 即便某机型/某系统版本离线时返回 `.couldNotDetermine`，新映射表也仍然落 `.production`，行为一致。

### 1.6 `.cloudUnsynced` 期间的写入如何被处置（原 V2 的替代答案）

**先把术语纠正过来**：这里涉及的**不是 Core Data 层面**，而是 SwiftData 的
`ModelConfiguration.CloudKitDatabase` —— 一个**构造期参数**，不是写进 store 的元数据。
`docs/plans/2026-09-19-icloud-sync-convergence.md:1115` 已经写明这一点
（"`cloudKitDatabase` 在 `ModelConfiguration` 构造时固定，`ModelContainer` 建成后不可变更"）。
所以"同一个文件先 `.none` 后 `.private(id)`"不构成底层异常。

真正需要交代的是**语义问题**：在 `.cloudUnsynced`（`.none`，mirroring 未挂载）期间写入的数据，
下次以 `.private(id)` 打开时能不能同步上去？

**本设计不依赖这个答案**，因为 `.cloudUnsynced` 必然伴随身份弹窗，而三个选项的动作都是整体重写：

| 用户选择 | 动作 | `.cloudUnsynced` 期间的写入 |
| --- | --- | --- |
| 以云端为准（`adoptCloud`） | 补 `removeStoreFiles(at: cloudURL)` 后挂 `.production` | **显式丢弃**（用户已知情） |
| 以本机为准（`overwriteCloud`） | `importReplacing` 本机 archive 写满云库路径 → 整体重写 | **整体保留**（不依赖增量导出） |
| 关闭同步（`switchToLocal`） | `importReplacing` 到本地库路径 + 清空云库路径 | **整体保留**（不依赖增量导出） |
| 用户关掉弹窗不做选择 | 保持 `.cloudUnsynced`，继续可写可读 | 留在原处，下次启动再问 |

**所以不存在"靠 CloudKit 增量导出兜住"的隐含依赖。** 原 V2 降级为一条设计约束，记在 §7 残余风险里。

---

## 2. 代码改动清单

### 2.1 `App/WeekyiiPersistence.swift`

| 行          | 改动                                                                                                                                       |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `:17-49`   | `StoreMode`：**删除 `case cloudDetached`，新增 `case cloudUnsynced`**；三个计算属性按 §1.2 重写。`allowsSave` 不再有 `false` 分支                         |
| `:119-141` | `resolveStoreMode` 按 §1.3 重写（账号状态不再参与 store 选择）                                                                                          |
| `:143-168` | `bootstrapPersistentContainer`：`if resolvedMode.allowsSave` 的守卫**可以删除**（恒为 true），也可保留为无害形式；播种与修复在 `.cloudUnsynced` 下照常执行（可写，符合预期）            |
| `:170-222` | `makeModelContainer`：**删除 `.cloudDetached` 整段分支（`:179-201`）**；`.cloudUnsynced` 走最后的 `else` 分支，`cloudKitContainerIdentifier == nil` → `.none`，`allowsSave == true` → 天然正确 |
| `:224-250` | **删除** `makeDetachedReadOnlyCopy(of:)`（`Caches/Weekyii/DetachedStores/` 整套机制随之消失）                                                            |
| `:252-262` | `persistentStoreURL(for:)`：`case .production, .cloudUnsynced, .inMemory:` → `Weekyii.store`                                                  |
| `:264-268` | **删除**无参 `persistentStoreURL()`（零调用点的死代码）                                                                                                |
| `:317-345` | `performIdentityResolution`：**拆开 `.adoptCloud` 与 `.overwriteCloud` 的合并 case**（V4 核实结论，见 §2.8）                                                   |
| `:350-377` | `applyIdentityResolutionToCloudStore`：新增 `clearsCloudStore: Bool` 参数，`.adoptCloud` 传 `true` 时先 `removeStoreFiles(at: cloudURL)`                     |
| `:475-488` | `failureDiagnostics()` 硬编码 `.production` → 改为接受 `storeMode` 参数                                                                           |


### 2.2 `Services/CloudSyncMonitor.swift`

| 行          | 改动                                                                                                                                                                 |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `:27-66`   | `CloudSyncSettlementBlocker` 新增 `case syncNotMounted`（本次运行未挂载 CloudKit），`description` = `"sync-not-mounted"`                                                       |
| `:300-361` | `settlement(storeMode:now:)`：`guard storeMode == .production` 分支改为 —— `.cloudUnsynced` 返回 `.unsettled(.syncNotMounted)`。**这是展示用值，不再参与任何写入判定** |
| `:363-373` | **删除** `syncedWritesAllowed(storeMode:now:)`。名字里带 "Allowed" 的 API 只要存在就会被误接，必须删干净                                                                                  |
| `:387-394` | `refreshAccountStatus()` 保持不变（账号恢复后更新 `accountState`；`storeMode` 本进程内不改，靠重启生效）                                                                                     |
| `:421-444` | `accountStatusForLaunch()` **增加超时参数**（实现文档 §7.2.1 的 `maxWait`）                                                                                                     |
| `:131-182` | `CloudSyncState.detail`：`.unavailable(.temporarilyUnavailable)` 文案从"iCloud 暂时不可用，将自动重试"改为"iCloud 暂时不可用，本次运行使用本地数据，重启后重试"（当前文案承诺了不会发生的自动重试）                         |

**超时实现（`accountStatusForLaunch`）：**

```swift
/// 带超时的账号解析。超时视为"账号暂时不可达"（等价 .temporarilyUnavailable），
/// 不阻塞启动 —— 这是文档 §7.2.1 的 maxWait 上界，之前未实现。
func accountStatusForLaunch(timeout: Duration = .seconds(5)) async -> CKAccountStatus? {
    guard let cloudContainer else {
        accountState = .unavailable(.temporarilyUnavailable)
        return nil
    }
    let status: CKAccountStatus? = await withTaskGroup(of: CKAccountStatus?.self) { group in
        group.addTask { await self.queryAccountStatus(cloudContainer) }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
    if let status {
        applyAccountStatus(status)          // 抽出 :425-438 的映射逻辑
    } else {
        accountState = .unavailable(.temporarilyUnavailable)
    }
    return status
}
```

> `CloudSyncMonitor` 是 `@MainActor` 类（隐式 `Sendable`），`self` 可安全跨任务捕获。  
> 超时与查询同时完成时以先到者为准；查询后到会覆盖 `accountState`，结果只会更准，无害。


### 2.3 `App/WeekyiiApp.swift`

| 行                           | 改动                                                                                                                   |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `:248` `:259` `:272` `:285` | 删除 `allowsSyncedWrites` 参数及其透传                                                                                       |
| `:368-373`                  | `AppHealthTrigger` 增加 `case remoteImport`（文档 §4.8 要求，顺带补上）                                                           |
| `:416-431`                  | 删除 `syncedWritesAllowed:` 闭包注入；`StateMachine` 不再需要该参数                                                                |
| `:434-446`                  | 删除 `syncedWritesAllowed` 计算属性；`settlement` 保留（仅供 `diagnosticsSnapshot`）                                              |
| `:459`                      | `reconcile(now:force:)` 的 force 条件加 `\|\| trigger == .remoteImport`                                                  |
| `:461-464`                  | **删除** `if syncedWritesAllowed { ... }` 包裹 → `HabitTaskMaterializer.sync(...)` **无条件执行**                             |
| `:647`                      | `reconcile(trigger: .manualResync, force: true)` → `.remoteImport`                                                   |
| `:706-762`                  | `resolveAndBootstrapPersistentContainer`：`accountStatusForLaunch()` → `accountStatusForLaunch(timeout: .seconds(5))` |
| `:730`                      | 硬编码字符串 `"cloudSyncEnabled"` → 引用 `UserSettings.cloudSyncEnabledKey`（需把该常量从 `private` 放开为 `internal`）                 |
| `:786-789`                  | `prepareIdentityResolution` 失败**不再静默**：写入 `appState.runtimeErrorMessage`（`ContentView:91-100` 已有 alert 承接）           |
| `:890-904`                  | `PersistenceResolvingView` 无需改动（超时已在 `accountStatusForLaunch` 内解决）                                                   |

### 2.4 `Services/StateMachine.swift`

| 行           | 改动                                                                                                                                                                                    |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `:68`       | 删除 `private let syncedWritesAllowedProvider: () -> Bool`                                                                                                                              |
| `:78` `:86` | 删除 init 参数与赋值                                                                                                                                                                         |
| `:98-136`   | **删除 `if allowsSyncedWrites { ... }` 包裹** —— `:112-130` 的 Tier-2 全部无条件执行                                                                                                              |
| `:108-109`  | 删除 `let allowsSyncedWrites = ...` 与传参                                                                                                                                                 |
| `:138-150`  | `ensureSystemStartDate(allowsSyncedWrites:)` → `ensureSystemStartDate()`；`:143` 的 `if allowsSyncedWrites, appState.lastProcessedDate == nil` → `if appState.lastProcessedDate == nil` |

> **这是本次修订的核心改动。** 改完后 `reconcile` 只有一种行为：全跑。

### 2.5 `Services/TaskPostponeService.swift`

| 行                     | 改动                                                                      |
| --------------------- | ----------------------------------------------------------------------- |
| `:236` `:245` `:248`  | 删除 `allowsSyncedWrites` 属性与 init 参数                                     |
| `:437-440` `:452-455` | **删除** `if allowsSyncedWrites()` 包裹 → `closedAt` / `.completed` 回填无条件执行 |

### 2.6 `Features/Today/TodayViewModel.swift` + `TodayView.swift`

| 行                                                                 | 改动                                                                               |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `TodayViewModel.swift:33` `:59` `:68` `:72`                       | 删除 `allowsSyncedWrites` 属性、init 参数、赋值、`TaskPostponeService` 传参                   |
| `TodayViewModel.swift:43-49`                                      | **删除** `isAwaitingSyncConfirmation`（Tier-2 无条件跑后，`completed` 状态即时生效，该标志恒为 false） |
| `TodayView.swift:171-172`                                         | `allowsPersistenceWrites` 闭包保留但**值恒为 `true`**（`storeMode.allowsSave` 改造后无 `false` 分支）。**删除调用点是独立清理项**，本次不做 —— 见 §1.2 的说明          |
| `TodayView.swift:458/470/553/574/597/610/843`                     | `.disabled(!storeMode.allowsSave)` / `isReadOnly: !storeMode.allowsSave` 全部**恒为 false**，行为上等价于闸门消失；调用点同样属独立清理项 |
| `TodayView.swift:661-662`                                         | 删除 `isAwaitingSyncConfirmation` 对应的 UI 分支                                        |

### 2.7 `App/ContentView.swift`

| 行          | 改动                                                                                  |
| ---------- | ----------------------------------------------------------------------------------- |
| `:109-115` | 删除 `allowsSyncedWrites` 闭包（`LiveActivityActionRouter` 只需 `allowsPersistenceWrites`） |
| `:79-89`   | 横幅改为**按 `identityConfirmed` 分两种文案**，见 §2.8                                          |


### 2.8 切账号：主动弹窗（身份存疑的处置）

> 需求原文：切换账号（含来回切换），**在开启了 iCloud 的情况下要主动弹窗**向用户验证下一步。

**现状缺口（三处）：**

1. **不主动弹窗。** E-2' 三选只在设置页里（`SettingsView.swift:728-754`），是"用户自己走到设置页才会看到"。
2. **首页横幅不指路且文案错。** `ContentView.swift:80` 写"等待 iCloud 账号确认" —— 身份冲突场景下账号已经确认了，只是与上次不同。用户看到的是一句含糊的"等待"，出口在三层菜单之外。
3. **选项不全。** 现有三选只有"以云端为准 / 以本机为准 / 关闭同步"，缺"云端非空时的合并"（见下表）。

**改动 ①：启动即弹窗（不是横幅）**

`resolveAndBootstrapPersistentContainer` 已经为身份冲突准备了待决快照（`WeekyiiApp.swift:747-749`  
→ `prepareIdentityResolution`）。把"进设置页才能选"改成"启动后立即弹 sheet"：

```swift
// ContentView.swift — 新增
.sheet(isPresented: $showingIdentityResolution) { IdentityResolutionSheet() }
.onAppear {
    showingIdentityResolution = (storeMode == .cloudUnsynced
                                 && !cloudSyncMonitor.identityConfirmed)
}
```

弹窗**不阻塞**：`.interactiveDismissDisabled(false)`，用户可以直接关掉，**继续正常读写**
（`.cloudUnsynced` 可写）；下次启动若身份仍存疑会再弹一次。
首页横幅保留为"随时可重新打开弹窗"的入口（点横幅 → 重新弹）。

**改动 ②：选项补齐（逐条对照需求）**

| 需求原话                    | 现有三选                                     | 判定     | 处理                      |
| ----------------------- | ---------------------------------------- | ------ | ----------------------- |
| 清空当前数据库？                | `adoptCloud`（"以 iCloud 云端数据为准，本机修改将被丢弃"） | **文案与实现相反** | 保留选项，**给实现补 `removeStoreFiles`**，文案可不动（见 V4 核实结论）        |
| 将当前本地数据库同步到新的云端？        | `overwriteCloud`（"以本机数据为准，覆盖云端并上传"）      | **覆盖** | 保留                      |
| 切换后的云端本来就不是空的 → 云端和本地同步 | —                                        | **缺失** | **新增 `mergeWithCloud`** |
| （需求未提，但现有能力）关闭同步仅用本地    | `switchToLocal`                          | 保留     | 保留                      |

**新增 `IdentityResolution.mergeWithCloud` 的语义：**

- 不做记录级 merge（§13.2 line 1805 禁止仓内出现"两个 store 记录级合并"代码路径）
- 实现方式：**把本机 archive 写进云库路径后挂上 `.private(新账号)`，由 CloudKit 的 import 做 LWW 合并**
- 也就是说：本地记录与新账号云端记录**两边都保留**，同 record ID 冲突走 LWW
- 与 `adoptCloud` 的差别在于**是否先清空云库路径**：
  - `adoptCloud`：先 `removeStoreFiles` 清空云库路径 → 只剩新账号云端数据（真正的"清空本机"）
  - `mergeWithCloud`：不清空 → 本地 archive + 新账号云端并存 → 合并

> ✅ **V4 已核实（2026-09-20，代码级，无需真机）**——结论比原设想更严重：
>
> 1. **`adoptCloud` 与 `overwriteCloud` 是同一个代码路径、同一个入参。**  
>    `performIdentityResolution`（`WeekyiiPersistence.swift:325-333`）把两者写在同一个 `case` 里，
>    都调 `applyIdentityResolutionToCloudStore(archive:)`；该函数（`:350-377`）只做
>    `backupPersistentStoreIfExists` → `importReplacing(archive, into: 云库路径)` → 改写
>    `lastSyncedUserRecordID`。**两个选项之间没有任何分支差异。**
> 2. **入参 archive 是"云库内容"而不是"本机内容"。**  
>    `prepareIdentityResolution`（`WeekyiiApp.swift:767-790`）导出的是
>    `modelContainer.mainContext`，而该容器来自身份存疑启动分支
>    （现为 `.cloudDetached`，改造后为 `.cloudUnsynced`）——即 `Weekyii.store` 的内容。
>    所以 archive == 切换前账号 A 的云库快照。
> 3. **因此 `adoptCloud` 的真实效果是"把 A 的旧数据写回云库路径并认领给 B"**，
>    重启后 CloudKit 以 B 身份挂载该文件 → 会把 A 的记录**上传到 B 的云端**。
>    这与文案"本机修改将被丢弃，重启后从云端重新加载"**语义相反**。
> 4. 现有测试无法发现：`test_identityResolution_adoptCloud_updatesIdentityAndKeepsCloudStoreFile`
>    （`ModelTests.swift:572-600`）与 `test_identityResolution_overwriteCloud_...`（`:498-521`）
>    除前置 `cloudSyncEnabled` 外**断言完全相同**，没有任何"两者产出不同"的断言。
>
> **修正后的设计口径（替换原 §286-288 的差别描述）：**
> - `adoptCloud` 必须**先 `removeStoreFiles(at: cloudURL)` 再挂 `.production`**，否则它根本不"丢弃"任何东西。
> - `mergeWithCloud` = 保留现状行为（archive 写入云库路径 + 不清空 + 由 CloudKit LWW 合并）。
> - 即：**现在的 `adoptCloud` 实现其实就是 `mergeWithCloud`，两个选项被写反了。**  
>   修复动作是"给 `adoptCloud` 补清空"，而不是"给 `mergeWithCloud` 新写一套"。

**改动 ③：文案**

| 位置                            | 现状                    | 改为                                   |
| ----------------------------- | --------------------- | ------------------------------------ |
| `SettingsView.swift:984`      | "将用启动时保存的云端快照覆盖本机数据…" | "将丢弃本机改动，从新账号的 iCloud 重新加载。此操作不可撤销。" |
| `SettingsView.swift:985`（新增项） | —                     | "将保留本机数据与新账号云端数据，两边合并。此操作不可撤销。"      |

**改动 ④：横幅（保留，但改为弹窗入口）**

```swift
// ContentView.swift:79-89
if storeMode == .cloudUnsynced {
    Button { showingIdentityResolution = true } label: {
        Label(
            "检测到 iCloud 账号已变化，点击选择数据来源。",
            systemImage: "exclamationmark.triangle.fill"
        )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("cloudUnsyncedIdentityBanner")
}
```

> **文案修正**：原横幅写"当前数据处于只读保护" —— 改造后 `.cloudUnsynced` **是可写的**，
> "只读保护"这句必须删掉，否则与事实相反。改造后只剩"账号已变化，请选择数据来源"这一种含义。

**改动 ⑤：来回切换账号**

用户在 `.cloudUnsynced` 态做了选择并重启后，`lastSyncedUserRecordID` 已被改写为新账号（`WeekyiiPersistence.swift:372-376`  
/ `:406-410`）。若之后又切回原账号，会**再次**进入 `.cloudUnsynced` 并**再次**弹窗 —— 这是正确行为  
（每次都让用户显式决定），但必须保证：

- 待决快照（`pendingIdentityResolutionKey`）每次都会被重新准备（`prepareIdentityResolution` 已有  
  "已有则复用"的逻辑，需确认复用不会导致快照过期 —— **V5**）
- 每次决策前都已建恢复点（`prepareIdentityResolution:780-785` 已建双库恢复点 ✅）


### 2.8b 关闭同步时切账号：零影响（需求 5）

> 需求原文：如果是在不开启 iCloud 能力下去切换 iCloud 账号，那也不应该给用户造成任何影响，  
> 除非用户明确在界面上打开了 iCloud 同步的能力。

**代码顺序已经正确**（`WeekyiiPersistence.swift:125-129`）：

```swift
guard cloudSyncEnabled else { return .localOnly }        // ← 先判开关
guard identityConfirmed else { return .cloudUnsynced }   // ← 后判身份
```

关闭同步时根本不会走到身份判定，`storeMode` 恒为 `.localOnly`，`allowsSave == true`，  
**不可能进入身份弹窗态**。`SettingsView.swift:728` 的三选显示条件也含 `storeMode == .cloudUnsynced`，  
所以不会出现。**结论：行为已正确，缺的是显式声明 + 回归测试。**

**但有一个 UI 缺陷必须修：**

`SettingsView.swift:685-694` 的 iCloud 状态行读的是 `cloudSyncMonitor.state`，  
而 `CloudSyncState.resolve`（`CloudSyncMonitor.swift:106-129`）**只看 `accountState` + `eventState`，  
完全不看 `cloudSyncEnabled`**。所以：

> 关闭同步 + 已登录 iCloud → 状态行显示 **"已开启，将通过 iCloud 自动同步"**（蓝图标），  
> 而它正下方那个 Toggle 是关的。

**改法**：`CloudSyncState` 增加一个"已关闭"态，或在 `SettingsView` 渲染前按  
`settings.cloudSyncEnabled` 短路：

```swift
private var cloudSyncDisplayState: CloudSyncState {
    settings.cloudSyncEnabled ? cloudSyncMonitor.state : .disabled
}
```

新增 `CloudSyncState.disabled`，`detail` = "已关闭，仅使用本机数据"，`symbolName` = `"icloud.slash"`。

### 2.9 只读态的两个 UI 缺口 —— **已随 `.cloudDetached` 删除而消失**

| 位置                          | 初版判定                                                                                                      | v2 结论                                                                    |
| --------------------------- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `DraftEditorView.swift:132` | 冻结/解冻按钮 `.disabled(day.status != .execute)` 没判 `isReadOnly` → 只读态下点了必抛 `persistenceReadOnly`         | **不需要修**：`isReadOnly` 的来源是 `!storeMode.allowsSave`（`TodayView.swift:470/610`），恒为 `false` |
| `DraftEditorView.swift:182` | `.onDelete(perform: deleteTasks)` 在非编辑模式下也提供左滑删除 → 只读态下能划出"删除"                                              | **不需要修**：同上                                                             |

**连带清理（可选，独立提交）**：`DraftEditorView.isReadOnly` 参数（`:12`、`:29-30`、`:57`、`:206`、`:209`）
在全仓唯一实参来源是 `!storeMode.allowsSave`，改造后恒为 `false` → 该参数成为死代码。
`TaskEditorSheet.isReadOnly` 另有字面量 `true` 的调用点（`TodayView.swift:198`、`PendingView.swift:152`、
`WeekOverviewView.swift:308`），**不动**。

> 这一条从"要修两处 UI"变成"删掉一个参数"，是 §1.1 删只读机制的直接收益。


### 2.10 Phase F：习惯水位线改推导（**前置条件，必须先做**）

**为什么现在是前置条件**：闸门删掉后，"部分同步导致水位线低估 → 重复物化"不再有第二道防线。必须让物化本身幂等。

**好消息：`HabitTaskMaterializer` 已经有逐日幂等检查。**

```swift
// HabitTaskMaterializer.swift:149-153
if day.tasks.contains(where: { $0.habit?.id == habit.id }) {
    outcome.skippedExistingCount += 1
    advanceWatermark(habit, to: todayKey, outcome: &outcome)
    return
}
```

而且 `createHabitTask`（`:181-183`）**每次物化都会建一条 `HabitDayRecord`**，所以  
`records.map(\.dayId).max()` 天然就是"已处理到哪一天"。

**改动：**

| 位置                                                     | 改动                                                                                                                                                  |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `HabitTaskMaterializer.swift:138`                      | `guard habit.generatedThroughDayId < todayKey else { return }` → `guard !habit.hasProcessed(day: todayKey) else { return }`                         |
| `HabitTaskMaterializer.swift:186-190`                  | **删除** `advanceWatermark`（record 由 `createHabitTask` 建，水位线自动推进）                                                                                     |
| `HabitTaskMaterializer.swift:106`                      | `assignToday` 里的 `habit.generatedThroughDayId = max(...)` **删除**（同上）                                                                                |
| `HabitTaskMaterializer.swift:141` `:151` `:156` `:161` | 相应删除 `advanceWatermark` 调用                                                                                                                          |
| `HabitModel.swift:77`                                  | `generatedThroughDayId` 字段**保留但不再使用**（零 schema 变更，文档 §8.1 已批准）；新增 `func hasProcessed(day: String) -> Bool { records.contains { $0.dayId == day } }` |

**行为变化（有意取舍）**：`blockedCount` 路径（`:154-157`，日已锁定或过了 kill time）现在**不再推进水位线** → 每次 reconcile 都会重试一次。成本 = 一次 `resolveDay` + 一次 `contains`，可忽略；语义上更正确（"没建成就不算处理过"）。

**验证点**：改完后必须确认"用户手动删掉今天的习惯任务后不会复活"这一既有语义仍然成立 —— 删任务不会删 `HabitDayRecord`，所以 `hasProcessed(day:)` 仍为 true → 不复活。✅（需补回归测试）


### 2.11 同步开关、状态呈现与失败反馈（需求 1 + 2）

> 需求原文：iCloud 同步能力是要在用户界面选择是否开启的。如果开启就会面临多端同步和是否有网络  
> 的问题，需要在界面上检查当前同步的状态，并且出现了问题及时反馈给用户，任何一种情况都不可以  
> 阻断用户在软件的任何操作。如果不开，就必须使用本地的数据库自己操作，不需要考虑任何云端同步。

#### 2.11.1 开关（已存在，需强化）

- 位置：`SettingsView.swift:703-717`（"启用 iCloud 同步" Toggle）
- 现状：`cloudSyncEnabled` 存 UserDefaults（`UserSettings.swift:9` / `:23` / `:202` / `:282`），  
  切换走显式迁移流程（`requestCloudSyncChange` → `prepareStoreTransfer` → `completeStoreTransfer`）
- **缺口**：`canRequestCloudSyncChange`（`SettingsView.swift:830-842`）在 `.cloudDetached` 返回  
  `false`、在 `.production` 未 `settled` 时也返回 `false` → **用户在降级态无法关闭同步**。  
  按需求 1，开关是用户的基本权利，**任何状态下都必须可操作**。  
  → 改为：任何 `storeMode` 下都允许切换，只是要额外提示"当前数据仍在等待 iCloud 确认，
  关闭同步后将使用独立的本地库，需要重启生效"。

#### 2.11.2 状态呈现（首页缺失，必须补）

- **现状**：状态行只在设置页（`SettingsView.swift:685-694`）。  
  首页**完全没有**同步状态展示 —— 文档 §4.7 的定项 **#14"首页在闸门期显示 iCloud 状态行"  
  至今未落地**。
- **补**：在 `ContentView` 顶部常驻一条**极简状态条**（不是横幅，不遮挡内容）：
  - `cloudSyncEnabled == false` → 不显示（用户明确不要同步，不该被打扰）
  - 同步正常（`settled`） → 不显示（不要噪音）
  - 同步中 → 细进度条 + "正在同步"
  - **同步异常** → 显示原因 + 可点击直达设置页
- 复用 `CloudSyncState.symbolName` / `detail`，不新造状态模型。

#### 2.11.3 失败反馈（"及时反馈"，不能只躺在设置页）

| 情况                                          | 反馈方式                               |
| ------------------------------------------- | ---------------------------------- |
| 导出/导入事件失败（网络、配额、服务端）                        | 首页状态条转为警告态 + 设置页显示具体错误。**不阻断任何操作** |
| iCloud 存储空间不足                               | 同上，文案明确"iCloud 空间不足，数据已保存在本机"      |
| 账号不可用（`.noAccount` / `.restricted` / 暂时查不到） | 状态条显示"未同步：<原因>"，可点击跳设置页            |
| 身份存疑                                        | 主动弹窗（§2.8），最高优先级                   |

**关键约束（R1/R3 的 UI 侧对应）**：状态条**不承载任何交互式禁用逻辑**。  
它只允许点击跳转设置页，不得包住任何操作控件。

#### 2.11.4 关闭同步时"完全不考虑云端"（需求 2）

- `resolveStoreMode` 第一优先 guard 已是 `cloudSyncEnabled`（`WeekyiiPersistence.swift:128`）→ `.localOnly`
- `.localOnly` = `Weekyii.local.store` + `cloudKitDatabase: .none` → **物理上不接触云端** ✅
- `CloudSyncMonitor` 仍在跑（`WeekyiiApp.swift:585`）→ 它只查询账号状态，不产生任何写入。  
  **但 UI 必须按 §2.8b 修正**，否则会显示"已开启，将通过 iCloud 自动同步"
- **需补测试**：关闭同步时，三选、身份横幅**全部不得出现**


### 2.12 反复开 / 关的幂等性（需求 3）

> 需求原文：即便是用户多次选择开还是关 iCloud 能力，都不可以影响用户在软件内的任何使用状态。

**现状机制**：每次切换都走 `prepareStoreTransfer` → `export` 当前库 + 双库建恢复点 + `importReplacing`  
到目标库 → `settings.cloudSyncEnabled = targetEnabled` → 提示重启。

**必须核实的四点：**

| #      | 风险                                                                                                                                         | 检查点                                                       |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------- |
| **V6** | **反复切换会不会丢数据？** `completeStoreTransfer` 用 `importReplacing`（完整替换）。目标库非空时走 `showingStoreConflict` 让用户确认；为空则直接覆盖。**来回切 N 次后，两个库的内容是否与首次一致？** | 写单元测试：开→关→开→关，每轮后断言两库记录数                                  |
| **V7** | **恢复点会累积吗？** 每次切换给两个库各建一份恢复点（`:867-875`）。反复切换会不会把 `recoveryPointRetentionCount` 撑满、把有价值的旧恢复点挤掉？                                            | 检查 `BackupRecoveryService` 的 prune 策略；必要时对"切换产生的恢复点"单独限流  |
| **V8** | **`cloudSyncEnabled` 的写入时机。** 它在 `completeStoreTransfer` 成功后写（`:917`），失败时不写（`:920-922`）。若 import 成功但写 UserDefaults 失败？                     | 顺序必须"先落库再改开关"（现状正确，补注释锁定）                                 |
| **V9** | **切换过程中被杀进程。** 迁移是"导出 → 建恢复点 → 导入目标库 → 改开关"，非原子。中途被杀会导致"目标库已写入但开关未改"或反之                                                                    | 明确：**下次启动以 `cloudSyncEnabled` 为准**（现状如此），恢复点保证可回滚。补一条人工验收 |

**额外要求**：切换过程中**不得禁用 App 的其他操作**（需求 1）。  
现状 `canRequestCloudSyncChange` 只禁用 Toggle，不禁用别处 —— 基本满足；  
需确认迁移执行期间（`prepareStoreTransfer` 是同步的、可能耗时）UI 是否卡住。若耗时明显，  
改为 async + 进度提示，**但仍不得禁用其他操作**。

---

## 3. 执行顺序（有依赖，不能乱）

```
① Phase F（§2.10）              ← 必须先做：删闸门后物化必须自身幂等
② StoreMode 换态 + resolveStoreMode（§2.1）+ 删只读机制（§1.1）+ settlement 改造（§2.2）
③ 删闸门：StateMachine / WeekyiiApp / TaskPostponeService / TodayViewModel
④ 启动超时（§2.2 的 accountStatusForLaunch(timeout:)）
⑤ 同步状态呈现：首页状态条 + 失败反馈 + 关闭同步的状态行（§2.11 / §2.8b）
⑥ 切账号主动弹窗 + `adoptCloud` 补 `removeStoreFiles` + 新增 mergeWithCloud（§2.8，V4 已核实）
⑦ 开关在任何状态下可操作（§2.11.1）
⑧ 反复开关幂等性验证与加固（§2.12）
⑨ 文档修订（§5）
```

- **② 与 ③ 必须一起提交**：单做 ② 会让 `.cloudUnsynced` 落进旧的闸门逻辑，行为不确定。
- **② 内部顺序**：先删 `.cloudDetached` 的机制（`makeDetachedReadOnlyCopy`、`makeModelContainer` 分支、
  `allowsSave: false`），再加 `.cloudUnsynced`。顺序反了会有一段时间两个只读来源并存。
- **⑥ 的 V4 阻塞已解除**（代码级核实完成，见 §2.8）：修复方向是"给 `adoptCloud` 补 `removeStoreFiles`"，
  不需要新写合并逻辑。
- **原 ⑧「只读态 UI 缺口」已删除**：只读机制不存在了，那两个缺口自动消失（§2.9）。

---

## 4. 测试计划


### 4.1 新增/改写单元测试

| 测试                                            | 断言                                                                                                                           | 反例（改回缺陷必须失败）                                                      |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `resolveStoreMode` 全表                         | 按 §1.3 的 5 行逐条断言                                                                                                             | 把 `.temporarilyUnavailable` 改成任何非 `.production` 的落点 → 必须失败            |
| `.noAccount` → `.production`                  | 且**不得**是 `.localOnly`（防 C4 回归）、**不得**是 `.cloudUnsynced`（身份没变，没理由不挂 CloudKit）                                            | 改回 `.localOnly` → 必须失败                                            |
| `.cloudUnsynced.allowsSave == true`           | 且 `cloudKitContainerIdentifier == nil`                                                                                       | 改成 `false` → 必须失败                                                 |
| `allowsSave` 恒真                                  | 对全部 4 个 case 断言 `allowsSave == true`（R1 在类型层面成立）                                                                            | 给任何 case 加回 `false` → 必须失败                                          |
| `.cloudUnsynced` 容器可写                         | `makeModelContainer(storeMode: .cloudUnsynced)` 后 `save()` 成功                                                                | 挂上 `.private(id)` → 必须失败                                              |
| 身份存疑唯一性                                       | `identityConfirmed == false` 是**唯一**能产出 `.cloudUnsynced` 的输入                                                                  | 新增任何其他触发来源（尤其账号状态）→ 必须失败                                          |
| `reconcile` 无条件跑 Tier-2                       | 注入任意 storeMode，`processCrossDay` / `repair` / GC 都必须执行                                                                       | 把 `if allowsSyncedWrites` 加回来 → 必须失败                              |
| `HabitTaskMaterializer` 幂等                    | 同一 today 连调两次 `sync()` → 第二次 `createdCount == 0`                                                                             | 去掉 `:149` 的 contains 检查 → 必须失败                                    |
| 水位线不回退                                        | 物化后删掉 `generatedThroughDayId`（或让它回退）→ 仍不重复物化                                                                                 | 用回存储字段 → 必须失败                                                     |
| 删除不复活                                         | 物化 → 删任务 → 再 `sync()` → 不重建                                                                                                  | 让 `hasProcessed` 判 `day.tasks` 而非 `records` → 必须失败                |
| `accountStatusForLaunch` 超时                   | 注入永不返回的查询 → 5s 内返回 nil 且 `accountState == .unavailable(.temporarilyUnavailable)`                                             | 去掉超时 → 必须失败（会挂起）                                                  |
| 三选改写身份基线                                      | `performIdentityResolution` 后 `lastSyncedUserRecordIDKey == 新账号`                                                             | 去掉 `:372-376` → 必须失败                                              |
| **关闭同步时零只读**（需求 5）                            | `cloudSyncEnabled == false` 时，任意 `accountStatus` + 任意 `identityConfirmed` → `storeMode == .localOnly` 且 `allowsSave == true` | 把 `guard cloudSyncEnabled` 挪到 `guard identityConfirmed` 之后 → 必须失败 |
| **关闭同步时不显示三选 / 横幅**（需求 5）                     | 关闭同步 + 身份不匹配 → 首页无横幅、设置页无三选                                                                                                  | 去掉三选条件里的 `storeMode == .cloudUnsynced` → 必须失败                     |
| **关闭同步时状态行正确**（需求 2）                          | 关闭同步 + 已登录 → 状态行是"已关闭，仅使用本机数据"，**不得**是"已开启，将通过 iCloud 自动同步"                                                                  | 让 `CloudSyncState.resolve` 忽略 `cloudSyncEnabled` → 必须失败           |
| **任何状态下开关可操作**（需求 1）                     | `canRequestCloudSyncChange == true` 对全部 4 个 `storeMode` × 任意 settlement                                                       | 让任何分支 `return false` → 必须失败                                          |
| **反复开/关幂等**（需求 3）                             | 开→关→开→关 各轮后，两库记录数不变（V6）                                                                                                      | 引入任何"切换时删数据"的路径 → 必须失败                                            |
| **首页状态条不承载禁用**（需求 1）                          | 状态条存在时，TodayView 所有写按钮仍 `.disabled == false`                                                                                   | 让状态条参与 `.disabled` 判定 → 必须失败                                      |
| **`mergeWithCloud` 与 `adoptCloud` 有差异**（需求 4） | 两选项产出的云库路径内容不同                                                                                                               | 让两者走同一实现 → 必须失败                                                   |

> ⚠️ 上面这条测试**在当前代码上会直接失败**——`adoptCloud` 与 `overwriteCloud` 现在就走同一实现（V4 核实结论）。
> 它的角色是"先把缺陷钉成红灯"，再在 ⑥ 里补 `removeStoreFiles` 让它转绿。这正是"改回缺陷必须失败"的对照证据本身。

### 4.2 需要删除/改写的既有测试

| 位置                                                     | 原因                                                  |
| ------------------------------------------------------ | --------------------------------------------------- |
| `ModelTests.swift:124-174`                             | `test_cloudDetachedContainerIsReadOnlyWithoutChangingStoreFiles` —— `.cloudDetached` 已删，只读机制不存在 |
| `ModelTests.swift:91`                                  | `XCTAssertFalse(StoreMode.cloudDetached.allowsSave)` —— 与 §4.1「`allowsSave` 恒真」直接冲突 |
| `ModelTests.swift:164` / `:324`                        | `makeModelContainer(storeMode: .cloudDetached)` / `settlement(storeMode: .cloudDetached)` → 改为 `.cloudUnsynced` |
| `ModelTests.swift:331/362/376/393/430/449/554/563/564` | 断言 `syncedWritesAllowed`（API 已删）→ 改为断言 `settlement` |
| `ModelTests.swift:114`                                 | `cloudSyncEnabled: false → .localOnly` 仍成立，保留       |
| `StateMachineTests.swift:1208/1216`                    | `isAwaitingSyncConfirmation` 已删 → 删除该测试             |
| `StateMachineTests.swift:1545/1570`                    | `allowsSyncedWrites` 参数已删 → 相应改写                    |
| `ModelTests.swift:4492`                                | `allowsSyncedWrites: { false }` → 改写                |

### 4.3 人工验收（真机，不可省）

| 场景                      | 期望                                     |
| ----------------------- | -------------------------------------- |
| **飞行模式冷启动**（已登录）        | 顶部**无**任何横幅；能建任务、能流转；设置页状态行反映"同步暂时不可达" |
| 飞行模式运行中切回 WiFi          | 恢复联网后 CloudKit 自动补传；无需重启               |
| **系统设置里退出 iCloud** 后冷启动 | 数据**全部可见**、可写；不是空白首页                   |
| 退出 iCloud 后重新登录**同一账号** | 身份匹配 → `.production` → 本地改动上传          |
| 退出 iCloud 后登录**另一账号**   | 身份不匹配 → **数据仍可见可写** + 启动即弹 sheet + 首页横幅可点重开 sheet |
| iCloud 存储空间写满           | App 完全可用；设置页显示同步报错；腾出空间后自动补传           |
| 关闭 App 的 iCloud 开关      | 走 §7.1.1 显式迁移（快照 + 导入）→ 重启后数据在新库里      |

---


## 5. 文档修订清单（`2026-09-19-icloud-sync-convergence.md`）

| 位置                                      | 现状                                                                   | 改为                                                               |
| --------------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------- |
| §0 结论                                   | "同步正确性优先，可用性让路"                                                      | 增补用户裁决：基础能力优先，同步为附加                                              |
| §4.2.1 / §4.2.2                         | `.noAccount` → `.localOnly`（切库）                                      | `.noAccount` / `.restricted` → **`.production`**（不切库，挂载失败无妨）；切库仅保留给"用户主动关闭同步" |
| §4.2.2 line 703                         | "运行中退出 iCloud → `noInboundChannel` → 只读 + 提示重启"                      | 改为：运行中退出 → 账号不可用，容器已建 → **照常可用**；重启后落 `.production`（同上，不切库）        |
| §4.5 line 816-826                       | 三条出口（含"设置页手动重试"、"关闭同步逃生"）                                            | 出口简化为一条：**重启**。删掉"逃生口"概念（不再是逃生，而是默认行为）                           |
| §4.7 全文                                 | "闸门期的功能降级"整节                                                         | **删除或改写为"账号不可用时的行为"**：无降级，只有不同步                                  |
| §4.10 / §4.12                           | `setupSucceeded` 必须让 `settled` 不可达                                   | 删除该约束；`setupSucceeded` 降级为纯展示                                    |
| §7.2.1 line 1219                        | "maxWait 内取不到账号 → 只读降级"                                              | 改为"→ `.production`（照常可用，挂载失败无妨）"                                   |
| §7.2.2 line 1226                        | 边界 1：超时 → `cloudDetached` 只读                                         | 改为超时 → `.production`（不因账号查询超时而改变 store）                           |
| §12 裁决 #18                              | "未登录设备切到独立 `.localOnly` store"                                       | **改判**：改为"未登录设备仍用 `.production`（不切库）"，理由：切库会让用户看到空 App（C4）。**同时补一条新裁决**：`cloudDetached` 只读态整体废除，只读不再是任何状态的属性 |
| §13.2 line 1687                         | "飞行模式冷启动 → 只读态"                                                      | 改为"飞行模式冷启动 → 全功能可用，仅不同步"                                         |
| §13.2 line 1717                         | `.production + setupSucceeded == false` → `unsettled` → Tier-2 false | 删除该行                                                             |
| §13.2 line 1733 / 1741                  | 锁定 setup 失败的测试                                                       | 删除或反转为"setup 失败不影响写入"                                            |
| §11 line 1541                           | `accountStatus` 描述为"同步、无网络"                                          | 与 §13.2 统一口径                                                     |
| §4.7 定项 #14                             | "首页在闸门期显示 iCloud 状态行"（**至今未落地**）                                     | 升级为硬交付项：首页状态条（§2.11.2）                                           |
| §4.5 出口 2 line 823                      | "设置页加一个重试按钮"                                                         | 改为首页状态条 + 设置页状态行（§2.11）                                          |
| E-2' 三选（§7 相关 + `SettingsView:728-754`） | 三选，且只在设置页                                                            | 改为**启动即主动弹窗**；选项增加 `mergeWithCloud`（§2.8）                        |
| E-2' `adoptCloud` 文案                    | "本机修改将被丢弃"                                                           | 文案保留，**改实现**：给 `adoptCloud` 补 `removeStoreFiles(at: cloudURL)`（V4 已核实，§2.8） |
| §4.7 / §7.1 开关                          | `canRequestCloudSyncChange` 在降级态禁用开关                                 | 改为任何状态下开关可操作（§2.11.1）                                            |
| 新增章节                                    | —                                                                    | 补"反复开关的幂等性"（§2.12）与"关闭同步时切账号零影响"（§2.8b）                          |

---


## 6. 需要实测 / 核实的问题（不能靠推断）

| #      | 问题                                                                                                         | 影响                                                                                                         | 怎么测                                                             |
| ------ | ---------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| **V1** | 断网时 `CKContainer.accountStatus()` 返回 `.available` 还是别的？                            | **已不是设计分叉点**：新映射表下账号状态不参与 store 选择，任何返回值都落 `.production`。仅影响设置页文案与 `settlement` 展示值 | 真机飞行模式冷启动，看设置页状态行与 `settlementDiagnostics`                      |
| ~~**V2**~~ | ~~用 `cloudKitDatabase: .none` 打开一个此前以 `.private(id)` 打开过的 store，之后切回 `.private(id)`，**Core Data** 是否正常？~~ **提法错误，已撤销** | — | **已撤销**：① 数据层是 **SwiftData**，不是 Core Data；② `cloudKitDatabase` 是**构造期参数**、不落 store 元数据（`2026-09-19-icloud-sync-convergence.md:1115` 已写明），所以不存在"底层异常"问题；③ 真正要交代的语义问题已由 §1.6 的设计消除（三个选项都是整体重写，不依赖 CloudKit 增量导出） |
| **V3** | 离线期间 CloudKit 是否持续发失败事件、把 `lastEventEndedAt` 推着走？                                                          | 只影响 `settlement` 的展示值（闸门已删）                                                                                | 观察 `settlementDiagnostics`                                      |
| ~~**V4**~~ | ~~`adoptCloud` 的实际效果到底是"丢弃本机"还是"LWW 合并"？~~ **已核实（代码级）** | — | **已完成**：两者走同一 `case`、同一函数、同一 archive，**实现完全相同**；archive 是云库快照 → 实际效果是把旧账号数据写回云库并认领给新账号。见 §2.8 V4 核实块 |
| **V5** | `prepareIdentityResolution` 的"已有待决快照则复用"逻辑（`WeekyiiApp.swift:770-772`）在**来回切账号**时会不会复用过期快照？                | 决定来回切换账号时三选用的数据对不对                                                                                         | 单元测试：连续两次身份冲突，断言第二次的快照内容                                        |
| **V6** | 反复开/关同步 N 次后，两个库的内容是否与首次一致？                                                                                | 需求 3 的核心                                                                                                   | 单元测试：开→关→开→关，每轮断言两库记录数                                          |
| **V7** | 反复切换产生的恢复点会不会挤掉有价值的旧恢复点？                                                                                   | 需求 3 的副作用                                                                                                  | 检查 `BackupRecoveryService` prune 策略                             |
| **V8** | `cloudSyncEnabled` 的写入时机（先落库再改开关）                                                                          | 需求 3                                                                                                       | 代码审查 + 注释锁定                                                     |
| **V9** | 迁移中途被杀进程后的恢复行为                                                                                             | 需求 3                                                                                                       | 人工：迁移时强杀，重启看状态                                                  |

**V1 已降级**：`CKContainer.accountStatus()` 是本地判断（语义为"系统能否访问用户的 iCloud 账号"，
离线时设备自己知道账号状态），所以已登录 + 飞行模式预期返回 `.available`。
即便如此，新映射表让账号状态不再参与 store 选择 —— **无论 V1 结果如何，行为一致**。
保留它只是为了确认设置页文案不会说谎。

**V2 已撤销（提法错误）**：原表述把数据层说成 Core Data，且把 `cloudKitDatabase` 当成了 store 元数据。
两处都错。详见 §1.6。**它不再是阻塞项，也不需要实测。**

**V4 已解除阻塞（代码级核实完成）**：`adoptCloud` 与 `overwriteCloud` 是同一实现，而当前实现
的真实语义恰好等于设计中的 `mergeWithCloud`。因此修复方向是**给 `adoptCloud` 补 `removeStoreFiles`**，
让三者（`adoptCloud` / `overwriteCloud` / `mergeWithCloud`）首次真正产生差异，而不是新写一套合并逻辑。

---

## 7. 明确不做 / 已知残余风险

| 项                                          | 状态                                                                                    |
| ------------------------------------------ | ------------------------------------------------------------------------------------- |
| GC 的"离线设备跨 8 周窗口复活"                        | **仍存在**（#20 已裁决接受）。闸门删除后 GC 在离线时也跑，风险窗口不变（回收线是 8 周，不是闸门长度）                            |
| 同日多条 `HabitDayRecord`                      | **不做去重**（文档 §8.2 已撤销）。读路径 `HabitStatistics.rank` 已正确容忍                                |
| `generatedThroughDayId` 字段                 | 保留在 schema 中不使用（零 V9）                                                                 |
| 删除绝不复活                                     | **不做**任何绝对承诺（§13.6 交付项）                                                               |
| `settlementDiagnostics` 的开发者向文案            | `SettingsView.swift:691` 的"结算：unsettled(quiet-until-...)"对用户不可读 → 改为用户向文案，或仅 DEBUG 显示 |
| 新增约 15 处硬编码中文 UI 文案未走 `String(localized:)` | 本次顺带纳入 §2.8 / §2.11 的改动；其余单独处理                                                      |
| **`.cloudUnsynced` 期间的写入不得依赖 CloudKit 增量导出**（原 V2 的残留约束） | **设计约束，写进代码注释**：该状态以 `.none` 打开 `Weekyii.store`，mirroring 未挂载，因此本期间的写入**只能由身份决策路径整体重写来处置**（§1.6 的四个出口）。后续任何人若新增"依赖 CloudKit 自动补传 `.cloudUnsynced` 期间改动"的逻辑，必须先实测 mirroring 重新挂载后是否补传 —— **不要假定它会**。 |

---

## 8. 验收清单

- [ ] 全仓 `grep syncedWritesAllowed` **零命中**
- [ ] 全仓 `grep allowsSyncedWrites` **零命中**
- [ ] `StateMachine.reconcile` 内不再出现任何 `if allowsSyncedWrites` 包裹
- [ ] 全仓 `grep cloudDetached` **零命中**（`StoreMode` case、`makeDetachedReadOnlyCopy`、UI 条件全部清除）
- [ ] 全仓 `grep allowsSave: false` **零命中**（只读机制彻底消失）
- [ ] `StoreMode.allowsSave` **恒为 `true`**（无 `false` 分支）
- [ ] `resolveStoreMode` 中产出 `.cloudUnsynced` 的分支**只有** `guard identityConfirmed`；账号状态**不参与** store 选择
- [ ] `HabitTaskMaterializer` 不再读写 `generatedThroughDayId`
- [ ] 单元测试：`ModelTests` + `StateMachineTests` 全绿
- [ ] 每一条新增回归用例都做过"改回缺陷必须失败"的对照验证
- [ ] §4.3 的 7 条人工验收全部通过
- [ ] 文档 §5 清单全部改完

### 8.1 用户需求逐条对照（交付时必须逐条打勾）

| 需求                         | 判定                              | 验收方式                                                                   |
| -------------------------- | ------------------------------- | ---------------------------------------------------------------------- |
| **1a** iCloud 同步在界面上可选择开关  | 已存在（`SettingsView:703-717`），需强化 | 任何 `storeMode` 下开关可操作（§2.11.1）                                          |
| **1b** 界面上能检查当前同步状态        | **首页缺失**（#14 未落地）               | 首页状态条按 §2.11.2 出现                                                      |
| **1c** 出现问题及时反馈给用户         | 部分（只在设置页）                       | 失败时首页状态条转警告态                                                           |
| **1d** 任何一种情况都不阻断任何操作      | 核心目标                            | 全仓 `syncedWritesAllowed` 零命中 + `allowsSave` 恒为 `true`                  |
| **2a** 不开同步 → 用本地库，不考虑云端   | 已正确（`.localOnly`）               | `resolveStoreMode` 第一 guard 是 `cloudSyncEnabled`                       |
| **2b** 不开同步 → UI 不得声称已开启同步 | **有缺陷**                         | §2.8b 的状态行修正                                                           |
| **3a** 多次开/关不影响使用状态        | 机制已有，幂等性未验证                     | V6 单元测试 + V7/V8/V9                                                     |
| **3b** 切换过程不禁用其他操作         | 基本满足                            | 迁移期间其他按钮不灰                                                             |
| **4a** 开启同步时切账号 → 主动弹窗     | **未实现**（只在设置页）                  | §2.8 改动 ①：启动即弹 sheet                                                   |
| **4b** 选项含"清空当前数据库"        | **实现与文案相反**                     | 给 `adoptCloud` 补 `removeStoreFiles`（V4 已核实）                             |
| **4c** 选项含"本地同步到新云端"       | 覆盖（`overwriteCloud`）            | 保留                                                                     |
| **4d** 选项含"云端非空时的云端+本地同步"  | **缺失**                          | 新增 `mergeWithCloud`                                                    |
| **4e** 来回切换账号都要验证          | 已正确（每次重新判定）                     | V5 核实快照复用                                                              |
| **5a** 不开同步时切账号零影响         | **代码已正确，未声明未测试**                | 补回归测试（见 §4.1）                                                          |
