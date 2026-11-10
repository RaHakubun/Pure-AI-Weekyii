# 专注区倒计时（Focus Countdown）——改动范围、级联影响与实施计划

> 评估日期：2026-09-18（**21:30 重核过一轮**，见 §11）
> 状态：**仅评估，未改任何代码**
> 约束：不修改任何数据模型；不改动任何现有代码文件
> 基线：分支 `online-chatgpt-develop`，HEAD `df220f3`，SwiftData Schema **V8**（archive formatVersion 1）

---

## 0. 结论摘要

**功能本身合理，架构代价低（纯内存、零模型改动），但它不是一个"小改动"。**

有三件事必须先修，否则功能会在核心场景下**静默失效**或**响错时间**：

| # | 阻塞项 | 证据 | 后果 |
|---|---|---|---|
| **P1** | 全工程**没有** `UNUserNotificationCenterDelegate` | `willPresent` 出现 0 次 | App 在前台时通知**不弹横幅、不响铃**。而"盯着专注区等倒计时"正是主场景 → 闹钟静默失败 |
| **P2** | 通知层只有**分钟级**触发器 | `NotificationService.swift:399` 用 `UNCalendarNotificationTrigger`，`dateComponents` 未含 `.second` | 10:03:40 起算的 25 分钟倒计时，实际在 10:28:**00** 响，**早 40 秒** |
| **P3** | 内存态在后台被冻结 | `WeekyiiApp.swift:579-586` 分钟定时器带 `scenePhase == .active` 门控（`scenePhase == .active` 在 `:581`） | 不能用递减计数器；必须存**绝对结束时刻**，回前台重算 |

**你问的两件事，答案都是明确的：**

1. **"总专注时长"功能已经存在，而且已经在用** —— 见 §1。它和新倒计时是两套语义，可以干净分离，但**必须在 UI 上区分**。
2. **"高级订阅"目前不存在真实购买能力** —— `premiumThemeUnlocked` 只是个开发者调试开关，全工程 0 处 StoreKit。见 §2。

**改动规模**：新增 3 个文件，修改 6 个文件（其中 4 处是小改），**不动任何 `@Model`、不动持久化层、不动状态机、不动 Widget/Live Activity**。

---

## 1. 先回答：已有的"总专注时长"

### 1.1 它确实存在，链路完整

**数据来源**：`TaskItem.startedAt` / `endedAt`（`Models/TaskItem.swift:21-22`），都是持久化字段。

```
TaskItem.startedAt ──┐
                     ├─→ TaskItem.duration = endedAt - startedAt     (Analytics+Extensions.swift:7-10)
TaskItem.endedAt   ──┘        │
                              ├─→ TaskItem.durationMinutes / durationFormatted / startPeriod  (:13-36)
                              │
                              ├─→ DayModel.totalFocusDuration        (:43-45)
                              │     └─→ DayModel.focusDurationFormatted / completionRate      (:48-70)
                              │
                              ├─→ WeekModel.totalFocusDuration       (:84-86)
                              │
                              └─→ PastAnalyticsService.totalFocusDuration(tasks:)             (PastAnalyticsService.swift:59-61)
                                    └─→ OverviewStats.totalFocusHours / averageTaskMinutes    (:100-101, 113-114)
                                          └─→ 展示在「过去」页概览统计
```

**写入点**（倒计时功能必须只读、绝不写这几个字段）：

| 位置 | 动作 |
|---|---|
| `TodayViewModel.swift:223` | `startDay()` 给首个任务写 `startedAt` |
| `TodayViewModel.swift:242-243` | `doneFocus()` 写 `endedAt` + `completedOrder` |
| `TodayViewModel.swift:340-346` | `exchangeFocusWithFirstDraft()` 清空旧焦点、给新焦点写 `startedAt` |
| `TaskPostponeService.swift:313-314` | 后移任务时清空 `startedAt`/`endedAt` |
| `TaskPostponeService.swift:423-424` | 后移后提升下一个焦点，补写 `startedAt` |
| `SettingsView.swift:1825-1826` | 演示数据填充 |

**展示点**：`TodayView.swift:509-517` 和 `TaskCard.swift:67-75` 显示 `startedAt` 的时刻（"10:30 开始"），不是时长；时长本身只在「过去」页统计里出现。

### 1.2 与倒计时的语义边界（**这是本功能最容易被用户混淆的地方**）

| 维度 | 已有：专注时长 | 新增：倒计时 |
|---|---|---|
| 性质 | **事后统计**（记录发生了什么） | **事前约束**（计划发生什么） |
| 数据来源 | `startedAt` / `endedAt`，持久化 | 纯内存，**不落盘** |
| 时间方向 | 从已发生的两点反推 | 从现在向未来倒数 |
| 更新时机 | 只在 `doneFocus()` 时定稿 | 每帧刷新 |
| 上限 | 无 | **kill time**（硬上限） |
| 副作用 | 无（只读） | 触发提醒 / 闹钟 |

**关键设计决定：倒计时到点不写 `endedAt`。**

理由：`endedAt` 只在 `doneFocus()` 写入（`TodayViewModel.swift:242`）。如果倒计时到点就写 `endedAt`，会**污染既有的专注时长统计**——用户没点"完成"的任务会被算成已完成，`completedTasks` 的过滤条件（`zone == .complete`）也会被绕开。

所以正确语义是：
- **已专注时长** = `now - startedAt`，一直累加，直到用户点"完成"或过期
- **倒计时剩余** = `endDate - now`，到 0 就停，可以续期
- 两者**并行存在，互不写入**。倒计时超时后，"已专注"继续走（这正是超时提醒的意义）

**UI 上必须避免歧义**：倒计时文案用「专注倒计时 · 剩余 12:34」，不要用「已专注」。建议在倒计时视图里同时展示 `startedAt` 的实际开始时刻，让"计划 vs 实际"一眼可分。

---

## 2. 再回答：高级订阅的现状

### 2.1 没有 StoreKit，只有调试开关

`premiumThemeUnlocked` 是 `UserSettings` 里的一个 `@Published var Bool`（`UserSettings.swift:140-142`），落 UserDefaults + App Group。

**全工程搜索 `StoreKit` / `Product.` / `purchase`：0 命中。**

唯一设置入口是开发者调试区：

```swift
// SettingsView.swift:806-817
if settings.developerSettingsEnabled {
    Toggle(isOn: Binding(
        get: { settings.premiumThemeUnlocked },
        set: { settings.premiumThemeUnlocked = $0 }
    )) {
        Text("解锁魔戒主题")
        Text("本地调试用，不代表真实购买状态")   // ← 文案自己写明了
    }
}
```

### 2.2 这直接影响本功能的定义

"高级订阅功能"有两种解释，代价差一个数量级：

| 方案 | 内容 | 代价 |
|---|---|---|
| **(a) 复用现有 flag 做门控** | 倒计时功能受 `premiumThemeUnlocked` 控制；未解锁时显示锁图标 + 引导文案 | 极小。**推荐 v1 采用** |
| **(b) 真接 StoreKit 2 订阅** | 产品配置、`Product.products(for:)`、`Transaction.updates` 监听、收据校验、恢复购买、App Store Connect 配置、沙盒测试 | **独立大工程**，不该和倒计时塞进同一个改动 |

**建议**：v1 走 (a)，把 `premiumThemeUnlocked` 当门控开关；真实的 IAP 另开一单，因为它的验收标准（订阅状态跨设备同步、退款处理、家庭共享）和倒计时的验收标准毫无交集。

**注意**：现有 flag 的语义是"解锁魔戒主题"，复用它做倒计时门控会让这个字段名变得名不副实。如果选 (a)，要么接受这个技术债并在注释里写明，要么把字段改名——但**改名会碰 `DataArchiveService.SettingsRecord`**（见 §4.6），所以 v1 建议**接受技术债 + 注释说明**。

---

## 3. 现有代码的真实运作方式

### 3.1 专注区怎么进、怎么出

**进入**：`TodayViewModel.startDay()`（`:206-232`）
- 前置：`day.status == .draft`，`sortedDraftTasks` 非空
- 首个草稿任务 → `zone = .focus` + `startedAt = now`
- 其余 → `zone = .frozen`
- `day.status = .execute`，`day.initiatedAt = now`，`executionMode` 取自设置

**渲染**：`TodayView.executeStateContent(day:viewModel:)`（`:478-673`；`TodayView.swift` 现在 1808 行）
- 焦点卡片在 `:480-590`，是一个 `WeekCard(useGradient: true)`
- 内部三个操作：**后移**（`:528-539`）、**交换**（`:543-566`，仅 flexible 模式）、**完成**（`:568-582`）
- 卡片内已有 `startedAt` 的展示位（`:517-525`）——倒计时可以紧挨着它放，视觉上天然分组
- 卡片内还有 `TaskHabitOriginBadge`（`:507-513`，`df220f3` 新增）和 `TaskProjectOriginBadge`（`:499-505`），倒计时视图应插在标题行与操作行之间，**不要挤进这两个 badge 所在的 HStack**

**退出**（4 条路径，倒计时必须全部挂钩）：

| 路径 | 位置 | 倒计时该做什么 |
|---|---|---|
| 点"完成" | `doneFocus()` `:234-258` | 取消并清理（同时 `HabitRecordService.stageCompletion` 被调用，`:244`） |
| 点"后移" | `TaskPostponeService.execute` `:313-314, 423-424` | 取消；若焦点被换成下一个任务则重置 |
| flexible 模式"交换" | `exchangeFocusWithFirstDraft()` `:333-357` | 取消并重置（绑定的 taskID 变了） |
| kill time 到点 | `expire()` `:465-473` | 取消；**任务本身会被 `modelContext.delete` 删除**（`:475-481`） |

> **注意 `expire()` 会真的删除任务对象**：`removeTasks(in: [.draft, .focus, .frozen])` → `modelContext.delete(task)`。如果倒计时持有 `TaskItem` 引用而不是 `UUID`，过期后会拿到已删除对象。**建议只存 `taskID: UUID` + 纯值类型状态。**

### 3.2 kill time 的三条过期路径（硬上限的执行者）

| 路径 | 位置 | 触发条件 |
|---|---|---|
| 分钟级 reconcile | `TodayViewModel.updateNotificationSchedule` `:613-642` | `now >= killDate` → `expire()` |
| 状态机 reconcile | `StateMachine.processKillTime` `:230+` | 同上；由 `AppHealthCoordinator` 在启动/回前台/分钟 tick 调用 |
| 手动改早 | `TodayViewModel.changeKillTime` `:370-399` | 新时间已过 → 立即 `expire()` |

`killDate` 的算法是 `day.date` 的年月日 + `killTimeHour/Minute`，秒固定为 0（`TodayViewModel.swift:439-445`，`DayModel.killTime` 在 `DayModel.swift:39-41`）。

**⚠️ `killDate(for:)` 目前是 `private`**，倒计时拿不到。要么暴露它，要么在 `TodayViewModel` 上加一个 `var focusDeadline: Date?` 计算属性（后者更收敛，不扩大 API 面）。

### 3.3 通知层的能力边界

```swift
// NotificationService.swift:49-55
protocol NotificationScheduling {
    func scheduleKillTimeNotification(for day: DayModel, reminderMinutes: Int, fixedReminder: DateComponents?)
    func cancelKillTimeNotification(for day: DayModel)
    func removeDeliveredKillTimeNotifications(for day: DayModel)
    func scheduleSuspendedTaskNotifications(for task: SuspendedTaskItem)
    func cancelSuspendedTaskNotifications(for task: SuspendedTaskItem)
}
```

**能用的**：`UNCalendarNotificationTrigger`，但秒被丢弃（`:399-402`）；`content.sound = .default`（`:398`）；授权只申请 `[.alert, .sound]`（`:90`）。

**没有的**：
- `UNTimeIntervalNotificationTrigger` —— **0 处**。倒计时需要它才能做到秒级精确
- `UNUserNotificationCenterDelegate` / `willPresent` —— **0 处**。前台不响（P1）
- Critical Alert 权限 —— 未申请。**所以"闹钟"无法穿透静音模式和专注模式**

`schedule(plan:)` 是 `private`（`:393-406`），倒计时**不能复用**，需要新增公开方法。

另外 `dedupedAndSorted`（`:408-428`）用 `seenMinute` 做分钟级去重，但**只在单个 plan 内部生效**。如果倒计时结束时刻恰好落在 kill-time 提醒的同一分钟，会产生**两条通知**。

### 3.4 生命周期与刷新节奏

**三个会打断倒计时内存态的机制**：

1. **分钟级全量刷新**
   `WeekyiiApp.swift:579-586` 的 `minuteTimer` → `AppHealthCoordinator.reconcile` → `StateMachine.reconcile` → `appState.bumpStateTransitionRevision()`（`StateMachine.swift:120`）→ `TodayView.refreshOnStateTransitions` → `viewModel.refresh()` → **`today = fetchDay(...)` 换成新对象**（`:644-645`）。
   → 倒计时状态**不能**挂在 `day` 上，也不能以 `day` 为 key 派生。

2. **`.id(appState.dataRevision)` 会销毁所有 Tab 的 `@State`**
   `ContentView.swift:70`。`bumpDataRevision()` 只在 3 处调用：数据导入（`DataArchiveService.swift:197`）、清空/填充演示数据（`SettingsView.swift:889, 912`）、Live Activity 动作路由（`WeekyiiApp.swift:288`）。
   → 前两者是"重置一切"，清掉倒计时合理；第三个是用户点了灵动岛的"完成"/"+1天"，清掉也**正确**。可接受。

3. **后台冻结**
   `scenePhase != .active` 时分钟定时器直接跳过。所以**必须存绝对 `endDate`**，回前台用 `now` 重算。

### 3.5 可复用的既有范式（不要重造）

| 范式 | 位置 | 为什么该抄 |
|---|---|---|
| 内存态、视图作用域、可取消的计时 | `LiveModuleTile.swift:49-52, 77-94` | `.task(id:)` + `Task.sleep(for:)` + `Task.isCancelled`，且已处理 `reduceMotion`。**倒计时循环照这个写** |
| 依赖注入协议 | `LiveActivityManaging`（`WeekyiiApp.swift:27-44`） | 倒计时也应定义 `FocusCountdownManaging`，便于测试与灵动岛路由共用 |
| 可注入时钟 | `TimeProviding` / `MockTimeProvider`（`TimeProvider.swift:4-41`） | 倒计时逻辑**必须走它**，不能用 `Date()`，否则测不了钳制逻辑 |
| 双档渲染 | `ThemeStatusArtwork(theme:renderingMode:)`（`.animated` / `.staticImage`） | "到点"的视觉表现可沿用同样的双档思路 |
| 通知协议 | `NotificationScheduling` | 新方法加到这个协议上，而不是另起一套 |

---

## 4. 级联影响（7 条，逐条给证据与对策）

### 4.1 【阻塞】前台通知不响 —— P1

**证据**：全工程 `willPresent` 0 命中、`UNUserNotificationCenterDelegate` 0 命中。
**后果**：iOS 默认在前台收到本地通知时不呈现。用户正盯着专注区看倒计时归零 → **什么都不发生**。这会让功能在最主要的使用场景下彻底失效。
**对策**：新增一个 `UNUserNotificationCenterDelegate`，`willPresent` 返回 `[.banner, .sound, .list]`，并在 `WeekyiiApp` 的 `onAppear`（已有初始化块，`:530-543`）里赋值给 `UNUserNotificationCenter.current().delegate`。
**范围**：1 个新文件 + 1 行赋值。**不碰数据模型。**

> ⚠️ 该 `onAppear` 内所有副作用都被 `guard !Self.isRunningTests else { return }` 保护（`WeekyiiApp.swift:531`）。注册 delegate 应放在**这个 guard 之外**（即 `.onAppear {` 之后、`guard` 之前），否则单测环境下前台通知路径测不到。注册本身无副作用（`isRunningTests` 时 App 也不启动 `AppHealthCoordinator`），放外面是安全的。

### 4.2 【阻塞】通知只能精确到分钟 —— P2

**证据**：`NotificationService.swift:399-402`。
**后果**：±59 秒误差。对 25 分钟倒计时是 4% 偏差，对 5 分钟短倒计时是 20% 偏差，不可接受。
**对策**：在 `NotificationScheduling` 上新增 `scheduleFocusCountdown(taskID:title:fireAt:)`，内部用 `UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireAt.timeIntervalSinceNow), repeats: false)`。标识符用 `"focus-countdown-\(taskID.uuidString)"`，便于取消。
**范围**：`NotificationService.swift` 加 1 个协议方法 + 1 个实现 + 1 个标识符常量。

### 4.3 续期不能越界，且不能改 kill time

**证据**：`day.killTimeHour/Minute` 是 `DayModel` 的持久化字段（`DayModel.swift:11-12`）；改它要走 `changeKillTime()`，且有"改到过去立即过期"的分支（`:375-391`）。
**对策**：
- 续期**只改内存里的 `endDate`**，硬钳制 `endDate = min(endDate + delta, killDate)`
- 达到上限时禁用 +1 按钮，并提示"已到今日截止时间 23:45"
- **绝不自动调 `changeKillTime`**。用户若想真正延后，走既有的 `KillTimeEditor`（`TodayView.swift:372-380`），那是显式操作

### 4.4 倒计时与 kill-time 提醒会撞车

**证据**：`dedupedAndSorted` 的 `seenMinute` 只作用于单 plan 内部（`:409, 422-424`）。
**后果**：倒计时若被钳制到正好等于 `killDate`，会和 `kill-time` 提醒在同一分钟各响一次。
**对策**：**当钳制后的剩余时长 ≤ 0（或落在 `killDate` 所在分钟内）时，不调度倒计时通知** —— 那一刻的提醒已经由既有 kill-time 通知承担，重复无意义。

### 4.5 任务对象会被物理删除

**证据**：`expire()` → `removeTasks(in:)` → `modelContext.delete(task)`（`:465-481`）。
**对策**：倒计时状态**只持有 `taskID: UUID` + 值类型**（`endDate`、`durationMinutes`、`phase`），不持有 `TaskItem` 引用。渲染时用 `day.tasks.first { $0.id == taskID }` 查，查不到就当作已结束并清理。

### 4.6 不要新增 `UserSettings` 字段

**证据**：
- `DataArchiveService` 的 `Envelope` 带 `formatVersion`，`:249` 严格校验（`!=` 即抛 `unsupportedVersion`）
- `SettingsRecord`（`:131-138`）是**全部非可选**的严格 `Codable`，含 `premiumThemeUnlocked`
- `currentFormatVersion = 1`、`currentSchemaVersion = 8`（`:46-47`）；`schemaVersion` 用 `<=`（`:250`），比 `formatVersion` 宽松

**⚠️ 21:30 重核修正**：commit `02641f1 feat: extend data archive with habits and day records for schema 8` 给 `Payload` 加了 `let habits: [HabitRecord]?`（`:81`）—— **可选字段，且没有升 `formatVersion`**。Swift 合成的 `Codable` 对 optional 用 `decodeIfPresent`，旧归档照常解码。

也就是说工程里已有「加可选字段、不升版本」的既定做法，我原先"加设置项必然牵连归档版本"的说法过重。修正为：

**后果**：写成 optional 的话解码向后兼容，但会改变导出 payload 形状；写成非可选则会破坏旧归档解码。
**对策**：v1 **零新增设置项**（理由从"会破坏归档"改为"没必要"）。
- 门控复用已有的 `premiumThemeUnlocked`
- 倒计时时长用**内存常量集合**（如 10/15/25/45 分钟），选择结果只存在当次会话，不持久化
- 若将来确实需要持久化默认时长，照 `Payload.habits` 的做法：**写成 `let x: T?`，不升 `formatVersion`**，并补一条「旧归档导入后该字段为 nil」的测试

### 4.7 Live Activity 会出现两个不同的"剩余"

**证据**：`TodayActivityAttributes.ContentState.remainingSeconds` 是**到 kill time** 的秒数（`WeekyiiWidgetSupport.swift:72`），灵动岛/锁屏显示"剩余"（`WeekyiiWidget.swift:101-102, 149` 与 `:215-216, 220`）。而 `TodayActivitySnapshotBuilder` 在 `WeekyiiApp.swift:58+` 构建它。
**后果**：App 内显示"任务倒计时剩余 12:34"，灵动岛显示"剩余 6:20"（到截止）。**同一个词，两个含义**。
**对策（v1）**：
- **不改 `ContentState`** —— 它是 ActivityKit 跨进程序列化的 payload，加字段会让运行中的 Live Activity 失效，属于超出本次范围的风险
- App 内倒计时的文案必须带限定词：「**本任务**倒计时」
- 在文档/评审里记为已知不对称，作为后续独立改动项

---

## 5. 合理性评估

### 5.1 成立的部分

- **"纯内存、不改数据模型"完全可行**。倒计时是纯粹的会话态，没有任何必须持久化的理由——App 被杀后用户回来，重新点一次即可，而且 kill time 本身就是天然的"重置点"。
- **"不能覆盖截止时间"这个约束是对的**，而且工程已经有三条独立的过期路径在强制执行它（§3.2），倒计时只要**读**这个边界，不需要新增任何守卫。
- **和既有专注时长的分离是干净的**。因为 `endedAt` 只在 `doneFocus()` 写，倒计时不碰它，就不会污染 `PastAnalyticsService` 的统计。
- **放在专注区（`executeStateContent` 的焦点卡片内）是正确位置**。那里已有 `startedAt` 展示位（`:517-525`）和三个操作按钮，视觉与交互都天然成组。

### 5.2 需要修正的部分

| 你的设想 | 修正 |
|---|---|
| "播放一个提醒闹钟" | 用 `UNTimeIntervalNotificationTrigger` + `.default` 声音。**不是真正的闹钟**：无法穿透静音/专注模式（需要 Apple 特批的 Critical Alerts 权限，本次不做）。**要在文案上诚实**——写"提醒"而不是"闹钟" |
| "可以续期" | 续期只动内存 `endDate`，硬钳制到 `killDate`；**不联动改 kill time**（§4.3） |
| "不需要涉及数据模型的更改" | ✅ 成立。但**额外**要求：也不要碰 `UserSettings` / `DataArchiveService`（§4.6）和 `TodayActivityAttributes`（§4.7） |
| "高级订阅功能" | 现有工程**没有** IAP。v1 用 `premiumThemeUnlocked` 做门控，真实订阅另开一单（§2.2） |

### 5.3 一个必须提前想清楚的产品问题

**倒计时到点之后，任务状态不变。** 用户会看到：闹钟响了、倒计时停在 00:00、"已专注"还在往上走、任务还在焦点位。

这是**有意**的（倒计时是约束不是状态），但需要一个明确的"到点后"表现，否则用户以为卡住了。建议三选一：

- **(A) 停在 00:00 + 高亮脉冲 + 两个操作**：「续期 +10 分钟」/「标记完成」 —— 最贴合"倒计时是工具"的定位，**推荐**
- (B) 自动标记完成 —— ❌ 会写 `endedAt`，污染专注时长统计，违背 §1.2
- (C) 自动切换到下一个任务 —— ❌ 属于 flexible 模式的"交换"语义，会和 `exchangeFocusWithFirstDraft` 抢职责

---

## 6. 改动范围清单

### 6.1 新增文件（3 个）

| 文件 | 内容 | 为什么是新文件 |
|---|---|---|
| `Services/FocusCountdownService.swift` | `FocusCountdownManaging` 协议；`FocusCountdownSession` 值类型（`taskID: UUID`、`startedAt: Date`、`endDate: Date`、`plannedMinutes: Int`、`phase: idle/running/expired`）；`FocusCountdownService` 实现（`start/extend/cancel/deadline(for:)`，全部走 `TimeProviding`） | 纯内存域，和 `TodayViewModel` 的生命周期解耦 |
| `Shared/Components/FocusCountdownView.swift` | 倒计时 UI：进度环 + `mm:ss` + 续期/取消/完成按钮 + 到点态。用 `.task(id:)` + `Task.sleep` 驱动（照 `LiveModuleTile`），尊重 `\.weekyiiReduceMotion` | 新组件，不塞进已经 1808 行的 `TodayView` |
| `App/NotificationPresentationDelegate.swift` | `UNUserNotificationCenterDelegate`，`willPresent` → `[.banner, .sound, .list]` | 修 P1。独立文件便于单测 |

### 6.2 修改文件（6 个，均为小改）

| 文件 | 改动 | 规模 |
|---|---|---|
| `Services/NotificationService.swift` | `NotificationScheduling` 加 `scheduleFocusCountdown(...)` / `cancelFocusCountdown(taskID:)`；实现用 `UNTimeIntervalNotificationTrigger`；加标识符常量 | +约 30 行 |
| `Features/Today/TodayView.swift` | 焦点卡片（`:480-590`）内嵌入 `FocusCountdownView`，插在标题行与操作行之间；`applyPendingTodayKillTime`（`:1007`）后做一次倒计时钳制 | +约 20 行 |
| `Features/Today/TodayViewModel.swift` | 暴露 `focusDeadline: Date?`（复用 private `killDate(for:)` `:439`）；`doneFocus`(`:234`) / `expire`(`:465`) / `exchangeFocusWithFirstDraft`(`:333`) 三处回调取消倒计时 | +约 15 行 |
| `App/WeekyiiApp.swift` | `onAppear`(`:530`) 里注册通知 delegate（放在 `guard` 之前）；创建并注入 `FocusCountdownService` | +约 8 行 |
| `Tests/StateMachineTests.swift` | `TestNotificationService`（`:33`）补新协议方法的空实现 | +2 行 |
| `Tests/ModelTests.swift` | `TestNotificationService`（`:3944`）同上 | +2 行 |

> ⚠️ 后两条是**编译必需**，不是可选项：`NotificationScheduling` 加方法后，两个测试 mock 不补实现会直接编译失败。

### 6.3 明确不动（重要）

- ❌ 所有 `@Model`（`TaskItem` / `DayModel` / `WeekModel` / `HabitModel` / …）
- ❌ `App/WeekyiiPersistence.swift`（Schema V8、迁移计划）
- ❌ `Services/StateMachine.swift`、`DataInvariantRepairService`
- ❌ `Services/TaskPostponeService.swift`
- ❌ `Models/Analytics+Extensions.swift`、`Features/Past/PastAnalyticsService.swift`（专注时长统计）
- ❌ `Shared/WidgetSupport/WeekyiiWidgetSupport.swift`（`TodayActivityAttributes.ContentState`）
- ❌ `WeekyiiWidget/*`（Widget 与 Live Activity）
- ❌ `Resources/UserSettings.swift`、`Services/DataArchiveService.swift`（归档格式）
- ❌ `TaskItem.startedAt` / `endedAt` 的读写

---

## 7. 分阶段实施计划

### Phase 0 —— 前置修复（**必须先做，否则后面全白干**）

1. 新增 `NotificationPresentationDelegate`，`willPresent` 返回 `[.banner, .sound, .list]`
2. `WeekyiiApp.onAppear` 注册 delegate

**验收**：App 在前台时，手动触发一条本地通知能弹出横幅并响铃。
**不做这一步的后果**：Phase 2 的闹钟在用户盯着屏幕时完全静默。

### Phase 1 —— 纯内存倒计时状态机 + UI（无通知）

1. `FocusCountdownService`：`start(taskID:deadline:minutes:)`、`extend(by:)`、`cancel()`、`session` 只读属性
2. 钳制规则集中在 `start`/`extend` 内部：`endDate = min(now + minutes, killDate)`；`killDate` 由调用方传入（不在 service 内查库）
3. `FocusCountdownView`：进度环 + `mm:ss`；用 `.task(id: session?.endDate)` 驱动秒级刷新；`.background` 时不做假设，回前台按 `now` 重算
4. 到点态：停 00:00 + 脉冲 + 「续期 +10 分钟」/「标记完成」

**验收**：
- 25 分钟倒计时能正常倒数
- 把手机切后台 2 分钟再回来，剩余时间**正确减少了 2 分钟**（证明用的是绝对时刻而非递减计数）
- kill time 只剩 5 分钟时选 25 分钟 → 钳制为 5 分钟并提示

**可单测**（用 `MockTimeProvider`）：钳制、续期不越界、到点态、`cancel` 幂等。

### Phase 2 —— 通知集成

1. `NotificationScheduling` 加 `scheduleFocusCountdown(taskID:title:fireAt:)` / `cancelFocusCountdown(taskID:)`
2. 实现用 `UNTimeIntervalNotificationTrigger`
3. 补两个测试 mock
4. 钳制后剩余 ≤ 0 时**不调度**（§4.4）

**验收**：倒计时结束时刻与系统通知触发时刻**误差 < 1 秒**（对照 `xcrun simctl` 或真机通知中心）。
**回归**：`StateMachineTests` / `ModelTests` 全绿；`NotificationServiceTests` 现有 13 个用例不受影响。

### Phase 3 —— 生命周期挂钩与 kill time 联动

1. `doneFocus()` / `expire()` / `exchangeFocusWithFirstDraft()` 三处取消倒计时
2. `applyPendingTodayKillTime` 之后重新钳制；若新 `killDate` 已过则直接作废
3. 任务被删除（`deleteExecutionTasks` / 后移）后，渲染层查不到 `taskID` 就自清理

**验收**：逐条走 §3.1 的 4 条退出路径，确认倒计时都能正确清理、无残留通知。
**回归重点**：`DraftReorderUITests`（807 行 UI 测试）+ 后移任务后 `startedAt/endedAt` 仍被正确清空。

### Phase 4 —— Premium 门控

1. 用 `premiumThemeUnlocked` 做门控
2. 未解锁时显示锁图标 + 引导（照抄 `SettingsView.swift:480-483` 的 `Image(systemName: "lock.fill")` + `.secondary` 样式；主题列表里同一套门控写法在 `:467` 的 `isLocked`）
3. 在代码注释里写明"此字段当前兼作倒计时门控，真实 IAP 待接入"

**验收**：关掉开发者开关后倒计时入口消失；打开后恢复。**归档导入导出仍正常**（`formatVersion` 未变）。

### Phase 5 ——（可选，**建议另开一单**）

真实 StoreKit 2 订阅：产品配置、交易监听、恢复购买、跨设备状态。
**理由**：验收标准与倒计时零交集，混在一起会让两个都难测。

---

## 8. 测试策略

### 8.1 单测（`ModelTests` / 新增用例，全部用 `MockTimeProvider`）

| 用例 | 断言 |
|---|---|
| 正常启动 | `endDate == now + minutes` |
| 钳制到 kill time | kill 剩 5 分钟、选 25 分钟 → `endDate == killDate` |
| 续期不越界 | `extend(by: 30)` 后 `endDate <= killDate` |
| kill time 改早后作废 | `killDate < now` → `session == nil` |
| 后台跨过结束点 | `now > endDate` → `phase == .expired`，不补动画 |
| 幂等取消 | 连续两次 `cancel()` 不崩、不重复清理 |
| 不写 `endedAt` | 倒计时结束后 `task.endedAt == nil`（**关键回归断言**） |

### 8.2 必须有牙齿的回归

倒计时最大的风险是**污染既有专注时长统计**。必须有一条测试：
- 启动倒计时 → 推进 mock 时间越过结束点 → 断言 `task.endedAt == nil` 且 `DayModel.totalFocusDuration` 不变
- **先故意把缺陷写进去（让到点逻辑写 `endedAt`），看它失败，再恢复**

### 8.3 UI 测试

`WeekyiiUITests/DraftReorderUITests.swift` 已有 `-uiTesting` + `-uiTestingSeedFlexibleExecution` 范式（见 `TodayViewModel.swift:108-150`，会造一个带 `startedAt` 的焦点任务）。可复用这套种子，加一条"进入执行态 → 启动倒计时 → 断言倒计时视图存在"的用例。

**注意**：`-uiTesting` 走 in-memory 容器（`WeekyiiApp.swift:494-507`），每次启动都是空库 —— 这对倒计时测试反而是优势（干净的内存态）。

### 8.4 不能红的既有测试

- `ModelTests`（139 个用例，含 `test_theme...` 系列）
- `StateMachineTests`（46 个）
- `NotificationServiceTests`（13 个）
- 两个 `TestNotificationService` mock 必须同步补实现

---

## 9. 明确不做（有意排除）

| 项 | 原因 |
|---|---|
| 真正的"闹钟"（穿透静音/专注模式） | 需 Apple 特批 Critical Alerts 权限。文案改为"提醒"，不承诺穿透 |
| 倒计时状态持久化 | 用户明确要求内存态；且 kill time 是天然重置点 |
| 到点自动完成 / 自动切换任务 | 会写 `endedAt` 污染统计，或与 `exchangeFocusWithFirstDraft` 抢职责（§5.3） |
| Live Activity 展示任务级倒计时 | 需改 `TodayActivityAttributes.ContentState`，会失效运行中的活动（§4.7） |
| 新增 `UserSettings` 设置项 | 没必要（§4.6）；真要做需写成 optional 字段，照 `Payload.habits` 的先例 |
| 真实 StoreKit 订阅 | 独立工程，另开一单（§7 Phase 5） |
| 倒计时历史记录 / 统计 | 需持久化，与"纯内存"约束冲突 |
| 修改 kill time 的入口 | 已有 `KillTimeEditor`，不重复造 |

---

## 10. 待你确认的决策点

1. **到点后的表现**：采用 §5.3 的方案 (A)（停在 00:00 + 续期/完成两个操作）吗？
2. **倒计时时长选项**：内存常量集合给哪几档？建议 `10 / 15 / 25 / 45` 分钟。
3. **续期步长**：建议 `+5 分钟`（或 `+10`），到 kill time 封顶。
4. **门控方式**：确认 v1 复用 `premiumThemeUnlocked`（接受字段名不精确的技术债），还是先不做门控？
5. **Phase 0 是否纳入本次范围**：不做的话，Phase 2 的闹钟在主场景下静默失效。
6. **是否要"到点前 N 分钟预提醒"**：会多一条通知，也会多一处和 kill-time 提醒撞车的可能。建议 v1 不做。

---

## 附：一页速览

```
现有能力
  ✅ 专注时长统计：TaskItem.startedAt/endedAt → duration → Day/Week 汇总 → 过去页
  ✅ 日级倒计时：Live Activity 的 remainingSeconds（到 kill time）
  ✅ 三条 kill time 过期路径（TodayViewModel / StateMachine / changeKillTime）
  ✅ 可注入时钟 TimeProviding / MockTimeProvider
  ✅ 内存态计时范式 LiveModuleTile（.task + Task.sleep + isCancelled）
  ❌ 前台通知呈现（无 delegate）        ← P1，必须补
  ❌ 秒级精确通知（只有 calendar trigger） ← P2，必须补
  ❌ 真实 IAP（只有调试开关）            ← 另开一单

新增范围
  新文件 3：FocusCountdownService / FocusCountdownView / NotificationPresentationDelegate
  改文件 6：NotificationService / TodayView / TodayViewModel / WeekyiiApp
           + 两个测试 mock（编译必需）
  不动：所有 @Model、Persistence、StateMachine、PostponeService、
        Analytics、WidgetSupport、Widget 扩展、UserSettings、DataArchiveService

核心不变式
  endDate <= killDate                  （硬钳制，续期不越界）
  倒计时不写 startedAt / endedAt        （不污染专注时长统计）
  状态只存 taskID + 值类型              （任务可能被物理删除）
  绝对时刻而非递减计数                  （后台冻结后回前台仍正确）
```

---

## 11. 重核记录（2026-09-18 21:30）

工作区在评估期间被另一个代理持续提交，HEAD 从 `244f89f` 推进到 `df220f3`。本节记录重核结果。

### 11.1 期间新增的 commit

| commit | 内容 | 对本计划的影响 |
|---|---|---|
| `02641f1` | `feat: extend data archive with habits and day records for schema 8` | **修正 §4.6**：`Payload.habits` 是可选的且未升 `formatVersion`，提供了"加可选字段不升版本"的先例 |
| `f7a8ebc` | `fix: place project origin badge on the task title row` | 无（仅 badge 位置） |
| `df220f3` | `feat: show habit origin badge on draft rows, focus card and frozen cards` | **影响 §3.1/§6.2**：焦点卡片新增 `TaskHabitOriginBadge`（`TodayView.swift:507-513`），插入点需避让 |

### 11.2 三个阻塞项的复检结果

| 阻塞项 | 复检 | 结论 |
|---|---|---|
| P1 无 `UNUserNotificationCenterDelegate` | 全仓 `willPresent` **0 命中**、`UNUserNotificationCenterDelegate` **0 命中** | ✅ 仍成立 |
| P2 无秒级触发器 | `UNTimeIntervalNotificationTrigger` **0 命中**；`UNCalendarNotificationTrigger` **仅 1 处**（`NotificationService.swift:399`） | ✅ 仍成立 |
| P3 后台冻结 | `Timer.publish` 仅 1 处（`WeekyiiApp.swift:473`），`onReceive` 在 `:579`，`scenePhase == .active` 门控在 `:581` | ✅ 仍成立 |

### 11.3 行号漂移（已全部更正）

| 引用 | 原值 | 现值 |
|---|---|---|
| `WeekyiiApp.swift` `.symbolVariant` | 527 | **529** |
| `WeekyiiApp.swift` `onAppear` 块 / guard | 528-541 / — | **530-543 / 531** |
| `WeekyiiApp.swift` `onReceive(minuteTimer)` | 577-584 | **579-586** |
| `WeekyiiApp.swift` `LiveActivityManaging` | 26-43 | **27-44** |
| `WeekyiiApp.swift` `TodayActivitySnapshotBuilder` | 61-105 | **58+** |
| `TodayView.swift` 总行数 | 1794 | **1808** |
| `TodayView.swift` 焦点卡片 | 481-581 | **480-590** |
| `TodayView.swift` `startedAt` 展示位 | 509-517 | **517-525** |
| `TodayView.swift` 后移 / 交换 / 完成按钮 | 521-534 / 536-558 / 560-577 | **528-539 / 543-566 / 568-582** |
| `Tests/ModelTests.swift` `TestNotificationService` | 3920 | **3944** |

**零漂移**（可放心引用）：`NotificationService.swift` 全部（49-55 / 87-94 / 393-406 / 398 / 399 / 408-428）、
`TodayViewModel.swift` 全部（206 / 234 / 333 / 439 / 465 / 475 / 613）、`StateMachine.swift:230`、
`TaskPostponeService.swift:313-314, 423-424`、`DayModel.swift:11-12, 39-41, 47-49`、`TaskItem.swift:21-22`、
`Analytics+Extensions.swift` 全部、`PastAnalyticsService.swift:59`、`ContentView.swift:70`、
`UserSettings.swift:140`、`AppState.swift:60`、`TimeProvider.swift:4-41`、`LiveModuleTile.swift:49-94`、
`WeekyiiWidgetSupport.swift:72`、`WeekyiiWidget.swift:101-102, 149`、`SettingsView.swift:467, 480-483, 808-809`、
`DataArchiveService.swift:131-138, 249`、`Tests/StateMachineTests.swift:33`。

### 11.4 一个插入点上的新约束

`df220f3` 之后，焦点卡片的标题行 HStack 里已经挤了 **两个 badge**（`TaskProjectOriginBadge` `:499-505`、`TaskHabitOriginBadge` `:507-513`）。
倒计时视图**不要**再往那个 HStack 里塞东西（`TodayView` 是 1808 行的巨型文件，横向空间也已紧张）。

建议插在**标题行与操作行之间**（即 `:514` 的 HStack 结束之后、`:517` 的 `startedAt` 行之前），或者紧贴 `startedAt` 行下方作为一行独立的倒计时条。后者更稳：`startedAt` 行本身是 `HStack` + `Spacer` + 三个按钮，加东西容易挤压按钮。

### 11.5 未受影响

- 所有 `@Model` 定义、Schema V8、迁移计划
- 专注时长统计链路（§1.1）逐行核对无变化
- `NotificationScheduling` 协议与两个 mock 的位置（`StateMachineTests.swift:33` 未漂移）
- `premiumThemeUnlocked` 的门控现状（`SettingsView.swift:808-809` 仍是开发者开关）
- 未提交的 `WeekyiiApp.swift` +89 行是启动动画 `WeekyiiLaunchOverlay`（`.overlay` 挂在 `ContentView` 上，启动后约 3 秒覆盖全屏），**与倒计时无关**，无需处理

