# Habit Tracker（习惯追踪）实施计划 v2

> ⚠️ **已被 `docs/plans/2026-09-18-habit-tracker-v3.md` 取代（2026-09-18）**：生成语义从"滚动 14 天窗口 + 未来日生成"改为**仅今日物化**（未来点亮不变量），并新增 `HabitDayRecord` 追踪记录实体。本文档以下部分仍被 v3 引用复用：§4.4 冻结 V7 代码块、§4.5-4.7 迁移/锚点/CloudKit 顺序、§5 本地化基线、§6 pbxproj UUID 模式。**不要按本文其余部分（尤其 §2.1 窗口语义、Task 6-8 的 carousel/指定日期加入）实施。**
>
> **执行方式**：本文件是唯一实施依据。严格按 Task 0 → Task 13 顺序执行，每个 Task 以"构建通过 + 测试通过 + commit"收尾；Task 11 做全量回归，Task 12 做人工验收，Task 13 做 CloudKit 发布。
> **v1 说明**：上一版计划（12 个 Task）经对抗性评审确认存在 12 项阻断/语义缺陷，**不可执行**。本版逐项修复；§0 为修复对照表。
> **事实基线**：本计划中所有 API 签名、行号、pbxproj UUID、模型字段均于 2026-09-16 在 `online-chatgpt-develop` 分支上逐项核对（含 `xcrun swift` 实测 ISO 日历行为）。

---

## §0 v1 评审问题 → v2 修复对照

| # | v1 缺陷（评审结论） | v2 修复 |
|---|---|---|
| 1 | 未定义数据模型迁移；直接改 live model 会让已发布 V7 schema 与历史 store 校验和不匹配 | §4：**冻结 V7**（内嵌 9 个模型副本）+ 新增 V8 + `.lightweight` 迁移阶段；Task 0 落地 |
| 2 | 未定义 CloudKit 生产 Schema 发布流程 | §4.6 发布顺序（DEBUG `-initializeCloudKitSchema` → Dashboard 部署生产 → 再发版）；Task 13 |
| 3 | 归档导入导出未兼容新模型（导出后重新导入会丢习惯、任务来源丢失） | Task 4：`Payload.habits`（可选）+ `TaskRecord.habitId` + 校验/插入/删除/摘要全链路；含"旧版归档（schema 7）导入"测试 |
| 4 | 分配任务非幂等，重复触发产生重复任务 | §2.2 幂等顺序（existing → locked → create）；Task 2 `HabitTaskMaterializer` |
| 5 | 未定义"持续重复"还是"批量生成" | §2.1 定为**滚动 14 天窗口 + 只前进水位线**（`generatedThroughDayId`），不回填、可重试 |
| 6 | 示例代码存在编译错误 | §0.1 逐条对照修正；§3/§7 全部代码按实测 API 重写 |
| 7 | 未补齐 Xcode 工程文件注册与迁移测试 | §6 pbxproj UUID 表（C0D3A007–C0D3A012）；Task 0/1 迁移测试；Task 11 全量测试 |
| 8 | 徽章显示范围未与 Project 徽章对齐 | §2.6 徽章范围表（Draft 行 / Focus 暗卡 / Frozen 卡；Complete 不显示） |
| 9 | 删除习惯对既有任务的影响未定义 | §2.5 归档 / 恢复 / 删除语义表 |
| 10 | 连续天数算法未定义（参照日历、宽限、下界） | §2.4 weekday-aware streak 定义 |
| 11 | 生成时机未定义（谁在什么时候调用） | §2.7 触发点（`AppHealthCoordinator.reconcile` + 用户操作后立即物化） |
| 12 | 锁定日判定与既有服务不一致 | §2.3 锁定定义 = `status ∉ {empty, draft}`，与 `TaskPostponeService` 完全一致 |
| +1 | 编辑重复计划后，新 weekday 在窗口内永不补生成 | §2.1 水位线回拨规则；Task 3 `HabitViewModel.updateHabit` |

### §0.1 v1 示例代码编译错误对照（逐条修正）

| v1 代码 | 错误 | v2 修正 |
|---|---|---|
| `Color(hex: habit.color) ?? .green` | `Color.init(hex:)` 不可失败（`Color+Weekyii.swift:1197`） | `Color(hex: habit.color)` |
| `guard let resolvedDay = resolution.day` | `DayResolution.day` 非可选（`WeekCalculator.swift:71`） | 直接使用 `resolution.day` |
| `#expect(...)` 写在 XCTest 文件里 | 本仓库测试使用 XCTest | `XCTAssertEqual` |
| `TaskDraftPayload(title:description:...)` 时省略 `description` | `description` 无默认值（`TaskPostponeService.swift:14`） | 显式传 `description: ""` |
| `Calendar.iso8601` | 不存在该静态常量 | `Calendar(identifier: .iso8601)` |
| 硬编码 `["一","二",...]` 星期标签 | 不随系统语言变化；与系统周首日无关 | `WeekyiiWeekday.localizedShortSymbols`（§3.3） |
| `if day.status == .empty { day.status = .draft }` | `createTask` 已自动提升（`TaskPostponeService.swift:86-88`） | 删除冗余 |
| `habit.badge \(habit.name)` 作为 localized key | key 含动态内容，本地化表无法穷举 | `task.habit.origin` + `String(format:)`（§5） |
| `.sheet(item: $editingHabit)` 直接绑定 @Model | 未实现 `Identifiable` 语义时不安全 | 用 `HabitModel.id` 的 `UUID?` 状态驱动（Task 7） |

---

## §1 目标 / 非目标 / 设计原则

### 目标
- 习惯一次创建、按选定 weekday 自动出现在每日 **Draft 区**的任务流中。
- Extensions Hub 顶部新增横向滚动习惯卡片（Project tile 之上）。
- 任务行/任务卡显示 Habit 来源徽章，视觉层级与 Project 徽章一致。
- 完全兼容现有本地存储、CloudKit 同步、数据归档三项既有能力。

### 非目标（v1 明确不做）
- 不做习惯提醒通知（通知体系已存在，习惯提醒留待 v2）。
- 不做习惯统计图表页（只有 streak 与计数）。
- 不做跨设备实时冲突合并（沿用 CloudKit last-writer-wins）。
- 不改动周视图、Pending 视图等既有版面。

### 设计原则
1. **与既有架构对齐**：`@Model` + `@MainActor @Observable` ViewModel + Service，与 `ExtensionsViewModel` / `MindStampViewModel` 同构。
2. **数据安全第一**：一切自动生成/删除都幂等、可重试；不触碰用户已开始（execute 之后）的任务数据。
3. **迁移冻结原则**：历史 schema 版本必须内嵌 frozen 模型副本（V2/V3 的 "Duplicate version checksums across stages detected" 事故教训）。
4. **最小侵入**：不改既有任务流转逻辑；习惯只是"任务的来源标签 + 自动创建器"。

---

## §2 固定语义（先定语义，再写代码）

### 2.1 生成语义：滚动窗口 + 水位线（"持续重复"的实现方式）

- 每个习惯维护两个锚点字段：
  - `startDayId`：开始日（此前日期永不生成）；
  - `generatedThroughDayId`：已生成到的日期（含）；空串 = 从未生成。
- **窗口**：`horizonDays = 14`。触发时从 `windowStart = max(今天, 水位线 + 1 天)` 生成到 `windowEnd = 今天 + 13 天`。
- **只前进、不回填**：窗口左端不小于"今天"，因此历史日期永远不会被追溯生成；水位线只写"窗口内实际处理过的最晚日期"。
- **两个不同概念，不可混用**：
  - **blocked（锁定日，§2.3）**：永久不可写，跳过该日、**继续向后处理**，水位线越过；
  - **failed（异常，如 save 抛错）**：瞬时故障，水位线冻结在失败日 − 1，下次运行从该日重试。
- **计划回拨**：仅当用户编辑 `scheduleWeekdays` 或 `startDayId` 时，把水位线回拨到「昨天」，使新 weekday 在窗口内的日期于下次触发时补生成。副作用（已记录并接受）：回拨后窗口内**被用户手动删除**的习惯任务会被重新生成，视为"用户重新确认了计划"。
- **删除不复活**：水位线不重访已处理日期，因此窗口内被手动删除的单条任务不会被自动重建。

判定公式（伪代码）：

```
windowStart = max(today, (watermark ?? startDate - 1day) + 1day)
windowEnd   = today + 13day
for date in windowStart...windowEnd:
    if date < startDate: continue
    if isoWeekday(date) not in schedule: continue
    materializeOne(habit, date)   # 幂等，见 §2.2
    watermark 前进到 date（blocked 也前进；failed 冻结在 date - 1）
    watermark 不允许超过 windowEnd
```

### 2.2 幂等物化顺序（`HabitTaskMaterializer.materializeOne`）

对每个 `(habit, date)` 三元判定，顺序固定：

1. **existing**：该日已有 `task.habit?.id == habit.id` 的任务 → 跳过（`skippedExistingCount += 1`，不重复创建）。
2. **locked**：该日**已存在**且 `day.status ∉ {empty, draft}`（§2.3）→ `blocked`，不创建（日不存在时先经 `resolveDay` 创建）。
3. **create**：`WeekDataStore.resolveDay(on:weekStatus:)`（必要时建周/建日）→ `TaskMutationService.createTask(in:payload:zone:.draft, project:nil)` → `task.habit = habit`。`createTask` 内部自动把 `.empty` 提升为 `.draft`（`TaskPostponeService.swift:86-88`），无需重复处理。

- 一次 `materialize` 调用结束前只 `save()` 一次；单日失败不影响其它日期，返回结构：

```swift
struct HabitMaterializeOutcome: Equatable {
    var createdCount: Int = 0
    var skippedExistingCount: Int = 0
    var blockedDayIds: [String] = []   // 锁定日（永久跳过）
    var failedDayIds: [String] = []    // 异常日（水位线冻结）
    var didChange: Bool { createdCount > 0 }
}
```

### 2.3 锁定日规则

- **可写**：`status == .empty` 或 `.draft`。
- **不可写**：`.execute` / `.completed` / `.expired`（单向不可逆，永久锁定）。
- 与 `TaskPostponeService.isAcceptableTargetDayStatus` 完全一致；**不**额外考虑 `isDraftZoneUnlocked`（保持与既有服务一致）。
- 判定结果 = `blocked`，该日不生成、以后也不会再尝试（水位线越过）。

### 2.4 Streak（连续天数）

- 参照 ISO 日历（`Calendar(identifier: .iso8601)`，周一为首日）。
- 只统计**计划内 weekday**；非计划日跳过，不打断。
- 从今天往回遍历，最多 365 天，规则：
  1. `date < startDay` → 停止；
  2. `date` 不在计划 weekday → 跳过（continue）；
  3. 当天（offset == 0）未完成 → 宽限，不计入也不打断；
  4. 计划日且该日存在 `zone == .complete` 的习惯任务 → `+1`；
  5. 计划日且未完成 → 打断（break）。
- 复杂度 O(习惯任务数 + 回溯天数)，数据来源为 `habit.tasks`（relationship 一次取全）。

### 2.5 归档 / 恢复 / 删除语义

| 操作 | `HabitModel` | 已生成任务 | 后续生成 |
|---|---|---|---|
| 归档（`isActive = false`） | 保留（管理页「已停用」分组） | **全部保留**（含关系） | 停止 |
| 恢复（`isActive = true`） | 保留 | 全部保留 | 自动恢复：水位线不动，窗口滑到今天后自然继续（§2.1） |
| 删除 | 删除记录 | `.empty`/`.draft` 日：删除该习惯任务并从 `day.tasks` 移除、重新编号；`.execute`/`.completed`/`.expired` 日：**保留任务**，`task.habit = nil` | 无 |

### 2.6 徽章显示范围（与 Project 徽章逐点对齐）

| 位置 | Project 徽章现状 | Habit 徽章 |
|---|---|---|
| Draft 编辑器任务行（`DraftEditorView:195-198`） | ✅ `showsProjectOrigin: true` | ✅ 同处显示 |
| Focus 大卡（`TodayView:498-501` 内联，暗底） | ✅ `isOnDarkBackground: true` | ✅ 紧随其后，同参数 |
| Frozen 卡（`FrozenZoneView` → `TaskCard`） | ✅ | ✅ |
| Complete 卡（`CompleteZoneView`） | ❌ 当前未开启 | ❌ **保持一致，不显示** |
| 其它 `TaskRowView`/`TaskCard` 调用点 | 默认 `false` | 默认 `false` |

### 2.7 触发点（谁在什么时候调用）

1. **`AppHealthCoordinator.reconcile(trigger:force:)`**（`WeekyiiApp.swift:394-414`）：启动、回前台、跨日、手动同步时调用一次 `materializeHabits(at:)`；有新增时 `appState.bumpDataRevision()`。
2. **用户操作后立即物化**：创建习惯、编辑计划/开始日、恢复习惯（`HabitViewModel` 内部，立即调用 materializer，保证创建后马上在今天的 Draft 区可见）。
3. **进入 Extensions Hub / 习惯管理页**：只 `refresh()` 读取，不生成。

---

## §3 数据设计

### 3.1 `Models/HabitModel.swift`（完整代码，可直接落盘）

```swift
import Foundation
import SwiftData
import SwiftUI

// MARK: - Category

enum HabitCategory: String, CaseIterable, Codable, Identifiable {
    case health
    case fitness
    case learning
    case mindfulness
    case creativity
    case social
    case productivity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .health: return String(localized: "habit.category.health", defaultValue: "健康")
        case .fitness: return String(localized: "habit.category.fitness", defaultValue: "运动")
        case .learning: return String(localized: "habit.category.learning", defaultValue: "学习")
        case .mindfulness: return String(localized: "habit.category.mindfulness", defaultValue: "正念")
        case .creativity: return String(localized: "habit.category.creativity", defaultValue: "创造")
        case .social: return String(localized: "habit.category.social", defaultValue: "社交")
        case .productivity: return String(localized: "habit.category.productivity", defaultValue: "效率")
        }
    }
}

// MARK: - Model

@Model
final class HabitModel {
    var id: UUID = UUID()

    var name: String = ""
    var iconName: String = "repeat.circle.fill"
    var colorHex: String = "#34C759"
    var categoryRaw: String = HabitCategory.health.rawValue

    /// 重复计划位掩码：bit(weekday - 1)，Mon=bit0 ... Sun=bit6。默认周一至周五 = 0b0011111。
    var scheduleWeekdaysRaw: Int = 0b0011111
    /// 开始日（YYYY-MM-DD）；此前日期永不生成。
    var startDayId: String = ""
    /// 已生成到的日期（YYYY-MM-DD，含）；空串 = 从未生成。
    var generatedThroughDayId: String = ""

    var isActive: Bool = true
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, originalName: "tasks", inverse: \TaskItem.habit)
    private var taskRecords: [TaskItem]? = []

    init(
        name: String,
        iconName: String = "repeat.circle.fill",
        colorHex: String = "#34C759",
        category: HabitCategory = .health,
        scheduleWeekdays: Set<Int> = [1, 2, 3, 4, 5],
        startDayId: String,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.categoryRaw = category.rawValue
        self.scheduleWeekdaysRaw = Self.encode(scheduleWeekdays)
        self.startDayId = startDayId
        self.sortOrder = sortOrder
    }

    // MARK: - Relationships

    var tasks: [TaskItem] {
        get { taskRecords ?? [] }
        set { taskRecords = newValue }
    }

    // MARK: - Derived State

    var category: HabitCategory {
        get { HabitCategory(rawValue: categoryRaw) ?? .health }
        set { categoryRaw = newValue.rawValue }
    }

    /// ISO weekday 集合：1 = 周一 ... 7 = 周日。
    var scheduleWeekdays: Set<Int> {
        get { Self.decode(scheduleWeekdaysRaw) }
        set { scheduleWeekdaysRaw = Self.encode(newValue) }
    }

    var startDate: Date? { WeekyiiDayId.date(from: startDayId) }

    var generatedThroughDate: Date? {
        get { WeekyiiDayId.date(from: generatedThroughDayId) }
        set { generatedThroughDayId = newValue?.dayId ?? "" }
    }

    var habitColor: Color { Color(hex: colorHex) }

    var scheduleSummary: String {
        let weekdays = scheduleWeekdays.sorted()
        guard !weekdays.isEmpty else { return "" }
        if weekdays == [1, 2, 3, 4, 5, 6, 7] {
            return String(localized: "habit.schedule.everyday", defaultValue: "每天")
        }
        if weekdays == [1, 2, 3, 4, 5] {
            return String(localized: "habit.schedule.weekdays", defaultValue: "工作日")
        }
        if weekdays == [6, 7] {
            return String(localized: "habit.schedule.weekend", defaultValue: "周末")
        }
        return weekdays
            .map { WeekyiiWeekday.localizedSymbol(for: $0) }
            .joined(separator: " ")
    }

    func isScheduled(on date: Date) -> Bool {
        scheduleWeekdays.contains(date.isoWeekday)
    }

    var activeTaskCount: Int { tasks.filter { $0.zone != .complete }.count }
    var completedTaskCount: Int { tasks.filter { $0.zone == .complete }.count }
    var totalTaskCount: Int { tasks.count }

    // MARK: - Weekday Bitmask

    private static func encode(_ weekdays: Set<Int>) -> Int {
        weekdays.filter { (1...7).contains($0) }.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    private static func decode(_ mask: Int) -> Set<Int> {
        Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 })
    }
}
```

> 说明：
> - 位掩码 `Int` 有默认值 `0b0011111`，满足 CloudKit「非可选属性必须有默认值」约束；后续想扩展成"每 N 天"等规则时，只是新增字段，不触碰既有字段。
> - **不使用** `@Attribute(.unique)`（CloudKit 禁止）。
> - 关系为 `private var taskRecords: [TaskItem]? = []` + `originalName: "tasks"`，与 `ProjectModel` 完全同构。

### 3.2 `Models/TaskItem.swift`（仅 +1 行）

在 `var project: ProjectModel?`（第 26 行）之后追加：

```swift
    var habit: HabitModel?
```

### 3.3 `Shared/Extensions/Date+Weekyii.swift`（追加）

```swift
extension Date {
    /// ISO weekday：1 = 周一 ... 7 = 周日。
    var isoWeekday: Int {
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: self)
        return weekday == 1 ? 7 : weekday - 1
    }
}

/// YYYY-MM-DD ↔ Date 的稳定互转（与 `Date.dayId` 使用同一格式/时区）。
enum WeekyiiDayId {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func date(from dayId: String) -> Date? {
        guard !dayId.isEmpty else { return nil }
        return formatter.date(from: dayId)
    }
}

/// weekday 展示辅助（locale 驱动，Sun-first 数组按 ISO 序号取模）。
enum WeekyiiWeekday {
    /// 当前 locale 的最短星期符号，数组顺序为周日在前（如 zh: 日一二三四五六；en: SMTWTFS）。
    static var localizedShortSymbols: [String] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = .autoupdatingCurrent
        return calendar.veryShortWeekdaySymbols
    }

    static func localizedSymbol(for isoWeekday: Int) -> String {
        let symbols = localizedShortSymbols
        guard !symbols.isEmpty else { return "\(isoWeekday)" }
        return symbols[isoWeekday % 7]
    }
}
```

> 实测（`xcrun swift`，zh_CN 机器）：`Calendar(identifier: .iso8601).firstWeekday == 2`；`.component(.weekday)` 为周日=1…周六=7，故 `isoWeekday = weekday == 1 ? 7 : weekday - 1`；`Calendar.iso8601` 不存在。
>
> **坑（实测）**：`Calendar(identifier:)` 的 `locale` 是固定的 root locale，直接取 `veryShortWeekdaySymbols` **恒为英文** `["S","M","T","W","T","F","S"]`，不随设备语言变化；必须像上面那样显式赋 `locale = .autoupdatingCurrent`，zh 设备才得到 `["日","一","二","三","四","五","六"]`。索引仍是 `isoWeekday % 7`（周日打头）。

> `WeekDataStore.resolveDay(on:weekStatus:)` 已存在（`WeekCalculator.swift:96`），返回 `DayResolution`，其 `day` 字段**非可选**，勿再写 `guard let`；物化服务自带私有 `weekStatus(for:)`（按真实当前时间判定，见 Task 2 代码），**无需**给 `WeekDataStore` 新增 API。

---

## §4 Schema 迁移：冻结 V7 + 新增 V8（阻断问题 #1）

### 4.1 现状与缺陷

`App/WeekyiiPersistence.swift:1459` 当前的 `WeekyiiSchemaV7` 直接引用 **live 模型**：

```swift
enum WeekyiiSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(7, 0, 0) }
    static var models: [any PersistentModel.Type] { [WeekModel.self, DayModel.self, ...] }
}
```

这意味着：**一旦给 live 模型加字段（本计划要加 `TaskItem.habit`），V7 的实体校验和会被追溯性改写**，与用户设备上已落盘的 V7 store 不匹配 → 打开即失败 / 触发 `Duplicate version checksums across stages detected`。这正是 V2/V3 已发生过的事故；V6 之前的历史版本之所以安全，是因为它们全部内嵌了 frozen 副本（`WeekyiiPersistence.swift:1221-1457`）。

### 4.2 修复方案

1. **冻结 V7**：把当前 live 模型的字段形态逐字复制为 `WeekyiiSchemaV7` 的 9 个内嵌 `@Model` 副本（§4.4）。
2. **新增 V8**：`WeekyiiSchemaV8` 引用 live 模型（含新的 `HabitModel`），即当前 V7 的写法迁移到 V8。
3. **迁移阶段**：`WeekyiiSchemaV7 → WeekyiiSchemaV8` 为 `.lightweight`（新增实体 + 新增可选关系，均为轻量级变更）。
4. **硬性规则（写入代码注释）**：`WeekyiiSchemaV8` 从此**冻结不再修改**；一切后续模型变更都必须新建 V9。

### 4.3 V6 → V7 变化核对表（冻结 V7 时的逐字段依据）

V7（CloudKit 兼容改造）相对 V6 的全部差异就是冻结 V7 需要精确还原的内容：

| 模型 | V6（已冻结副本） | V7（= 现 live 模型，即本次冻结目标） |
|---|---|---|
| `WeekModel.weekId` | `@Attribute(.unique) var weekId: String` | `var weekId: String = ""`（去 unique） |
| `WeekModel.days` | `@Relationship(deleteRule: .cascade, inverse: \DayModel.week) var days: [DayModel] = []` | `@Relationship(deleteRule: .cascade, originalName: "days", inverse: \DayModel.week) private var dayRecords: [DayModel]? = []` + `days` 计算属性 |
| `DayModel.dayId` | `@Attribute(.unique)` | `var dayId: String = ""` |
| `DayModel.tasks` | `@Relationship(deleteRule: .cascade, inverse: \TaskItem.day) var tasks: [TaskItem] = []` | `private var taskRecords: [TaskItem]? = []` + `originalName: "tasks"` + `tasks` 计算属性 |
| `TaskItem.id` | `@Attribute(.unique) var id: UUID = UUID()` | `var id: UUID = UUID()` |
| `TaskItem.steps / attachments` | `@Relationship(deleteRule: .cascade) var steps/attachments` | `private var stepRecords/attachmentRecords: [.]? = []`，`originalName: "steps"/"attachments"`，`inverse: \TaskStep.task` / `\TaskAttachment.task` |
| `TaskStep` | 无反向属性 | 新增 `var task: TaskItem?`、`var suspendedTask: SuspendedTaskItem?` |
| `TaskAttachment` | 无反向属性 | 新增 `var task: TaskItem?`、`var suspendedTask: SuspendedTaskItem?` |
| `TaskAttachment.fileName` | `var fileName: String`（无默认值） | `var fileName: String = ""` |
| `ProjectModel.id` | `@Attribute(.unique)` | 无 unique |
| `ProjectModel.tasks` | `@Relationship(deleteRule: .nullify, inverse: \TaskItem.project) var tasks` | `private var taskRecords: [TaskItem]? = []` + `originalName: "tasks"` + 计算属性 |
| `MindStampItem.id` / `SuspendedTaskItem.id` | `@Attribute(.unique)` | 无 unique |
| `SuspendedTaskItem` | 同 V6（`steps`/`attachments` 直接数组） | `private stepRecords/attachmentRecords` + `originalName` + `inverse: \TaskStep.suspendedTask` / `\TaskAttachment.suspendedTask` |
| `TaskTypeDefinition.idRaw` | `@Attribute(.unique)` | `var idRaw: String = ""`（去 unique，注意 V6 副本之外还有一份 V4 副本，不动） |

### 4.4 `App/WeekyiiPersistence.swift` — 冻结后的 `WeekyiiSchemaV7`（整块替换 1459-1475 行）

```swift
// NOTE: WeekyiiSchemaV7 is FROZEN. Never edit these models again.
// They must stay a byte-for-byte field mirror of the shape that shipped as 7.0.0.
enum WeekyiiSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            WeekModel.self,
            DayModel.self,
            TaskItem.self,
            TaskStep.self,
            TaskAttachment.self,
            ProjectModel.self,
            MindStampItem.self,
            SuspendedTaskItem.self,
            TaskTypeDefinition.self,
        ]
    }

    @Model
    final class WeekModel {
        var weekId: String = ""
        var startDate: Date = Date.distantPast
        var endDate: Date = Date.distantPast
        var status: WeekStatus = WeekStatus.pending

        @Relationship(deleteRule: .cascade, originalName: "days", inverse: \DayModel.week)
        private var dayRecords: [DayModel]? = []

        var completedTasksCount: Int = 0
        var expiredTasksCount: Int = 0
        var totalStartedDays: Int = 0

        init(weekId: String, startDate: Date, endDate: Date, status: WeekStatus = .pending) {
            self.weekId = weekId
            self.startDate = startDate
            self.endDate = endDate
            self.status = status
        }

        var days: [DayModel] {
            get { dayRecords ?? [] }
            set { dayRecords = newValue }
        }
    }

    @Model
    final class DayModel {
        var dayId: String = ""
        var date: Date = Date.distantPast
        var dayOfWeek: String = ""
        var status: DayStatus = DayStatus.empty

        var killTimeHour: Int = 23
        var killTimeMinute: Int = 45
        var followsDefaultKillTime: Bool = true

        var initiatedAt: Date?
        var closedAt: Date?
        var executionModeRaw: String = ExecutionMode.strict.rawValue
        var isDraftZoneUnlocked: Bool = false

        var week: WeekModel?

        @Relationship(deleteRule: .cascade, originalName: "tasks", inverse: \TaskItem.day)
        private var taskRecords: [TaskItem]? = []

        var expiredCount: Int = 0

        init(dayId: String, date: Date, status: DayStatus = .empty) {
            self.dayId = dayId
            self.date = date
            self.dayOfWeek = date.dayOfWeekShort
            self.status = status
        }

        var tasks: [TaskItem] {
            get { taskRecords ?? [] }
            set { taskRecords = newValue }
        }
    }

    @Model
    final class TaskItem {
        var id: UUID = UUID()

        var title: String = ""
        var taskType: TaskType = TaskType.regular
        var taskTypeIdRaw: String = TaskType.regular.rawValue
        var order: Int = 0
        var zone: TaskZone = TaskZone.draft

        var taskDescription: String = ""

        @Relationship(deleteRule: .cascade, originalName: "steps", inverse: \TaskStep.task)
        private var stepRecords: [TaskStep]? = []
        @Relationship(deleteRule: .cascade, originalName: "attachments", inverse: \TaskAttachment.task)
        private var attachmentRecords: [TaskAttachment]? = []

        var startedAt: Date?
        var endedAt: Date?
        var completedOrder: Int = 0

        var day: DayModel?
        var project: ProjectModel?

        init(title: String, taskDescription: String = "", taskType: TaskType = .regular, order: Int, zone: TaskZone = .draft) {
            self.title = title
            self.taskDescription = taskDescription
            self.taskType = taskType
            self.taskTypeIdRaw = taskType.rawValue
            self.order = order
            self.zone = zone
        }

        var steps: [TaskStep] {
            get { stepRecords ?? [] }
            set { stepRecords = newValue }
        }

        var attachments: [TaskAttachment] {
            get { attachmentRecords ?? [] }
            set { attachmentRecords = newValue }
        }
    }

    @Model
    final class TaskStep {
        var title: String = ""
        var isCompleted: Bool = false
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var task: TaskItem?
        var suspendedTask: SuspendedTaskItem?

        init(title: String, isCompleted: Bool = false, sortOrder: Int = 0) {
            self.title = title
            self.isCompleted = isCompleted
            self.sortOrder = sortOrder
            self.createdAt = Date()
        }
    }

    @Model
    final class TaskAttachment {
        var id: UUID = UUID()
        @Attribute(.externalStorage) var data: Data?
        var fileName: String = ""
        var fileType: String = "application/octet-stream"
        var createdAt: Date = Date()
        var task: TaskItem?
        var suspendedTask: SuspendedTaskItem?

        init(data: Data?, fileName: String, fileType: String) {
            self.data = data
            self.fileName = fileName
            self.fileType = fileType
            self.createdAt = Date()
        }
    }

    @Model
    final class ProjectModel {
        var id: UUID = UUID()

        var name: String = ""
        var projectDescription: String = ""
        var color: String = "#C46A1A"
        var icon: String = "folder.fill"
        var status: ProjectStatus = ProjectStatus.planning
        var startDate: Date = Date.distantPast
        var endDate: Date = Date.distantPast
        var createdAt: Date = Date()
        var tileSizeRaw: String = ProjectTileSize.medium.rawValue
        var tileOrder: Int = 0

        @Relationship(deleteRule: .nullify, originalName: "tasks", inverse: \TaskItem.project)
        private var taskRecords: [TaskItem]? = []

        init(
            name: String,
            projectDescription: String = "",
            color: String = "#C46A1A",
            icon: String = "folder.fill",
            status: ProjectStatus = .planning,
            startDate: Date,
            endDate: Date
        ) {
            self.name = name
            self.projectDescription = projectDescription
            self.color = color
            self.icon = icon
            self.status = status
            self.startDate = startDate
            self.endDate = endDate
            self.createdAt = Date()
        }

        var tasks: [TaskItem] {
            get { taskRecords ?? [] }
            set { taskRecords = newValue }
        }
    }

    @Model
    final class MindStampItem {
        var id: UUID = UUID()
        var text: String = ""
        @Attribute(.externalStorage) var imageBlob: Data?
        var createdAt: Date = Date()

        init(text: String = "", imageBlob: Data? = nil) {
            self.text = text
            self.imageBlob = imageBlob
            self.createdAt = Date()
        }
    }

    @Model
    final class SuspendedTaskItem {
        var id: UUID = UUID()

        var title: String = ""
        var taskDescription: String = ""
        var taskType: TaskType = TaskType.regular
        var taskTypeIdRaw: String = TaskType.regular.rawValue
        var createdAt: Date = Date()
        var decisionDeadline: Date = Date()
        var preferredCountdownDays: Int = 0
        var snoozeCount: Int = 0
        var statusRaw: String = SuspendedTaskStatus.active.rawValue

        @Relationship(deleteRule: .cascade, originalName: "steps", inverse: \TaskStep.suspendedTask)
        private var stepRecords: [TaskStep]? = []
        @Relationship(deleteRule: .cascade, originalName: "attachments", inverse: \TaskAttachment.suspendedTask)
        private var attachmentRecords: [TaskAttachment]? = []

        init(
            title: String,
            taskDescription: String = "",
            taskType: TaskType = .regular,
            createdAt: Date = Date(),
            decisionDeadline: Date,
            preferredCountdownDays: Int,
            snoozeCount: Int = 0,
            statusRaw: String = SuspendedTaskStatus.active.rawValue
        ) {
            self.title = title
            self.taskDescription = taskDescription
            self.taskType = taskType
            self.taskTypeIdRaw = taskType.rawValue
            self.createdAt = createdAt
            self.decisionDeadline = decisionDeadline
            self.preferredCountdownDays = preferredCountdownDays
            self.snoozeCount = snoozeCount
            self.statusRaw = statusRaw
        }

        var steps: [TaskStep] {
            get { stepRecords ?? [] }
            set { stepRecords = newValue }
        }

        var attachments: [TaskAttachment] {
            get { attachmentRecords ?? [] }
            set { attachmentRecords = newValue }
        }
    }

    @Model
    final class TaskTypeDefinition {
        var idRaw: String = ""
        var name: String = ""
        var iconName: String = "tag"
        var colorHex: String = "#4A90A4"
        var baseKindRaw: String = TaskType.regular.rawValue
        var sortOrder: Int = 0
        var isBuiltIn: Bool = false
        var isArchived: Bool = false

        init(
            idRaw: String = UUID().uuidString,
            name: String,
            iconName: String,
            colorHex: String,
            baseKindRaw: String,
            sortOrder: Int,
            isBuiltIn: Bool = false,
            isArchived: Bool = false
        ) {
            self.idRaw = idRaw
            self.name = name
            self.iconName = iconName
            self.colorHex = colorHex
            self.baseKindRaw = baseKindRaw
            self.sortOrder = sortOrder
            self.isBuiltIn = isBuiltIn
            self.isArchived = isArchived
        }
    }
}
```

### 4.5 新增 `WeekyiiSchemaV8` 与迁移阶段（同文件追加）

在 `WeekyiiSchemaV7` 之后追加：

> Task 0 落地时 `HabitModel` 尚不存在，V8 的 `models` 列表先与 V7 完全相同（9 个模型）；Task 1 再追加 `HabitModel.self`（见 Task 1 Step 3）。

```swift
// NOTE: WeekyiiSchemaV8 is FROZEN once shipped. Any further model change
// requires a new WeekyiiSchemaV9 with its own migration stage.
enum WeekyiiSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(8, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            WeekModel.self,
            DayModel.self,
            TaskItem.self,
            TaskStep.self,
            TaskAttachment.self,
            ProjectModel.self,
            MindStampItem.self,
            SuspendedTaskItem.self,
            TaskTypeDefinition.self,
            HabitModel.self,
        ]
    }
}
```

`WeekyiiMigrationPlan` 两处修改：

```swift
    static var schemas: [any VersionedSchema.Type] {
        [
            WeekyiiSchemaV1.self,
            WeekyiiSchemaV2.self,
            WeekyiiSchemaV3.self,
            WeekyiiSchemaV4.self,
            WeekyiiSchemaV5.self,
            WeekyiiSchemaV6.self,
            WeekyiiSchemaV7.self,
            WeekyiiSchemaV8.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            // ... 既有 V1→V2 ... V6→V7 保持不变 ...
            .lightweight(fromVersion: WeekyiiSchemaV7.self, toVersion: WeekyiiSchemaV8.self),
        ]
    }
```

### 4.6 版本锚点表（必须同步修改，否则行为不一致）

| 文件:行 | 现值 | 改为 |
|---|---|---|
| `App/WeekyiiPersistence.swift:31` | `Schema(versionedSchema: WeekyiiSchemaV7.self)` | `...WeekyiiSchemaV8.self` |
| `App/WeekyiiPersistence.swift:44` | `for: WeekyiiSchemaV7.models` | `for: WeekyiiSchemaV8.models` |
| `App/WeekyiiPersistence.swift:156` | `let preflightReason = "preflight-v7"` | `"preflight-v8"` |
| `App/WeekyiiPersistence.swift:192` | `"schema=7.0.0"` | `"schema=8.0.0"` |
| `App/WeekyiiPersistence.swift:239` | `schemaVersion: "7.0.0"` | `"8.0.0"` |
| `App/WeekyiiPersistence.swift:724` | schemas 数组（V1..V7） | 追加 `WeekyiiSchemaV8.self` |
| `App/WeekyiiPersistence.swift:742` | 最后一个 stage = V6→V7 | 追加 V7→V8 lightweight |
| `Tests/ModelTests.swift:23` | `XCTAssertEqual(schema.version, Schema.Version(7, 0, 0))` | `(8, 0, 0)` |
| `Tests/ModelTests.swift:213/226/235` | 字面量 `"preflight-v7"` | `"preflight-v8"` |
| `Tests/ModelTests.swift:2710` | `Schema(versionedSchema: WeekyiiSchemaV4.self)`（`TaskPostponeServiceTests`） | **不改动**：冻结历史 schema；live 模型比旧实体多出属性/关系是既有常态（`taskTypeIdRaw` 已是先例），新增 `habit` 同样不参与该容器 |
| `Tests/ModelTests.swift:3244` | `makeContainer()` 内 Schema 列表 | 追加 `HabitModel.self` |
| `Tests/StateMachineTests.swift:140-150` | `makeContainer()` 内 Schema 列表 | 追加 `HabitModel.self` |
| `Services/DataArchiveService.swift:47` | `currentSchemaVersion = 7` | `8`（Task 4） |

### 4.7 CloudKit 生产 Schema 发布顺序（阻断问题 #2）

SwiftData + CloudKit 的 schema 是**只追加**的；开发环境（Development）自动演化，但**生产环境必须手动部署**，否则新模型/字段不会在线上生效，iCloud 同步将报错。发版顺序固定为：

1. 本地/真机用 Debug 配置启动一次，并附加启动参数：`-initializeCloudKitSchema`（`WeekyiiApp.swift:477-481` 已实现 `shouldInitializeCloudKitSchema` / `initializeCloudKitDevelopmentSchema()`，仅在 DEBUG 生效）。
2. 打开 CloudKit Dashboard → 容器 `iCloud.com.fluentdesign.Weekyii` → Schema → **Deploy Schema Changes to Production**，确认出现 `CD_HabitModel` 实体与 `CD_TaskItem.habit` 关系。
3. 之后再走 TestFlight / App Store 发版（**先部署 schema，后发版**；顺序颠倒会导致线上用户同步失败）。
4. 发布后回归：两台设备（或一台真机 + 一台模拟器登录同一 iCloud）验证习惯与任务的同步。
5. 无需重新提交审核、无需重新申请 iCloud 能力（沿用既有容器）。

---

## §5 本地化（`Resources/Localizable.xcstrings`）

代码统一使用 `String(localized:defaultValue:)`（中文默认值，与 `SuspendedExpiryPolicy`、`task.project.origin` 的既有约定一致）。Task 10 需要把下列 key 的 **en** 值写入 String Catalog（zh 即 defaultValue，无需重复填写）：

| Key | 中文（defaultValue） | en |
|---|---|---|
| `task.habit.origin` | 习惯 · %@ | Habit · %@ |
| `extensions.module.habits.title` | 习惯追踪 | Habits |
| `extensions.hub.habits.empty` | 还没有习惯，点击创建 | No habits yet. Tap to create one. |
| `habit.schedule.everyday` / `.weekdays` / `.weekend` | 每天 / 工作日 / 周末 | Every day / Weekdays / Weekends |
| `habit.category.*`（7 个） | 健康/运动/学习/正念/创造/社交/效率 | Health/Fitness/Learning/Mindfulness/Creativity/Social/Productivity |
| `habit.streak.unit %lld` | 连续 %lld 天 | %lld-day streak |
| `habit.streak.none` | 尚未开始 | Not started |
| `habit.error.name_empty` | 习惯名称不能为空 | Habit name cannot be empty |
| `habit.error.schedule_empty` | 请至少选择一天 | Pick at least one day |
| `habit.error.day_locked` | 该日期已锁定，无法加入 | That date is locked |
| `habit.error.save_failed` | 保存失败，请重试 | Could not save. Try again. |
| `habits.title` | 我的习惯 | My Habits |
| `habits.subtitle` | 习惯会按重复计划自动出现在每日草稿区 | Habits appear in the draft zone on scheduled days |
| `habits.archived.section` | 已停用 | Archived |
| `habits.empty.title` | 还没有习惯 | No habits yet |
| `habits.empty.action` | 新建习惯 | New Habit |
| `habit.editor.create_title` / `edit_title` | 新建习惯 / 编辑习惯 | New Habit / Edit Habit |
| `habit.editor.name` | 名称 | Name |
| `habit.editor.name_placeholder` | 例如：冥想、跑步 | e.g. Meditation, Running |
| `habit.editor.icon` | 图标 | Icon |
| `habit.editor.color` | 颜色 | Color |
| `habit.editor.category` | 分类 | Category |
| `habit.editor.schedule` | 重复 | Repeat |
| `habit.editor.start_date` | 开始日期 | Start Date |
| `habit.editor.assign_immediately` | 创建后立即加入今天及未来两周 | Add to today and the next two weeks |
| `habit.editor.footer` | 习惯按重复计划自动出现在每日草稿区；已开始的日期不会补写 | Habits appear on scheduled days in the draft zone. Started days are never rewritten. |
| `habit.detail.assign` | 加入指定日期 | Add to a Date |
| `habit.detail.assign_action` | 选择日期 | Pick a Date |
| `habit.detail.stats` | 统计 | Statistics |
| `habit.detail.completed` / `total` | 已完成 / 累计 | Completed / Total |
| `habit.detail.delete` | 删除习惯 | Delete Habit |
| `habit.detail.delete_confirm` | 删除后，未开始日期中的该习惯任务会被移除；已开始的日期仅解除关联。 | Tasks in unstarted days will be removed; started days only lose the link. |
| `habit.assign.title` | 加入日期 | Add to a Date |
| `habit.assign.submit` | 加入 | Add |
| `habit.assign.result.created` | 已加入 %@ | Added to %@ |
| `habit.assign.result.exists` | 该日期已存在 | Already scheduled on that day |
| `habit.action.archive` / `restore` | 停用 / 恢复 | Archive / Restore |
| `habit.carousel.manage` | 管理 | Manage |
| `habit.count.tasks %lld` | %lld 个任务 | %lld tasks |

> `%lld` 用于 `Int` 占位（与既有 `后移 %lld 天` 一致）；`%@` 用于字符串。新文件里的所有 `String(localized:)` 字面量在编译后会自动出现在 String Catalog 中，Task 10 只补 en 列。

---

## §6 Xcode 工程文件注册（阻断问题 #7）

新增 6 个 Swift 文件（全部加入 Weekyii target 的 Sources 阶段）。pbxproj 采用手工注册，UUID 沿用既有模式 `<8位序号>30A0000100BEEF01`（现有最大序号 `C0D3A006`，本项目 ID 段内无冲突）。

| 新文件 | PBXBuildFile UUID | PBXFileReference UUID | 归属 Group | 注册的 Task |
|---|---|---|---|---|
| `Models/HabitModel.swift` | `C0D3A00730A0000100BEEF01` | `C0D3A00830A0000100BEEF01` | Models | Task 1 |
| `Services/HabitTaskMaterializer.swift` | `C0D3A00930A0000100BEEF01` | `C0D3A00A30A0000100BEEF01` | Services | Task 2 |
| `Features/Extensions/HabitViewModel.swift` | `C0D3A00B30A0000100BEEF01` | `C0D3A00C30A0000100BEEF01` | Features/Extensions | Task 3 |
| `Features/Extensions/HabitCarouselView.swift` | `C0D3A00D30A0000100BEEF01` | `C0D3A00E30A0000100BEEF01` | Features/Extensions | Task 6 |
| `Features/Extensions/HabitsFullView.swift` | `C0D3A00F30A0000100BEEF01` | `C0D3A01030A0000100BEEF01` | Features/Extensions | Task 7 |
| `Features/Extensions/HabitEditorSheet.swift` | `C0D3A01130A0000100BEEF01` | `C0D3A01230A0000100BEEF01` | Features/Extensions | Task 8 |

每个 UUID 需要在 pbxproj 的 **4 个位置**出现（以既有 `WeekTopology.swift` 为参照：`project.pbxproj:104`、`:265`、`:401`、`:815`）：

1. `PBXBuildFile` 段（~104 行）：`<buildUUID> /* X.swift in Sources */ = {isa = PBXBuildFile; fileRef = <fileUUID> /* X.swift */; };`
2. `PBXFileReference` 段（~265 行）：`<fileUUID> /* X.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = X.swift; sourceTree = "<group>"; };`
3. 对应 Group 的 `children` 数组（Models ~433 / Services ~465 / Features/Extensions ~559）
4. `PBXSourcesBuildPhase` 的 `files` 数组（~790+）：`<buildUUID> /* X.swift in Sources */,`

**额外注意**：
- `Tests/StateMachineTests.swift:141-150` 与 `Tests/ModelTests.swift:3244` 两处手写 `Schema([...])` 追加 `HabitModel.self`（Task 1）；`:2710` 用的是 `Schema(versionedSchema: WeekyiiSchemaV4.self)`，**不动**。
- 测试文件通过 `WeekyiiPersistence.makeModelContainer(...)` 建容器的地方无需改动（自动跟随 `currentSchema`）。
- 修改 pbxproj 后先在 Xcode 中确认 target membership，再 `xcodebuild` 验证（Task 11）。

---

## §7 任务分解（Task 0 → Task 13）

> 通用约定：
> - 构建：`xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' build`（模拟器名按本机 `xcrun simctl list devices available` 调整）。
> - 测试：同上把 `build` 换成 `test`。
> - 每个 Task 的最后一步是 commit；commit message 用给定文案。
> - **Task 0 与 Task 1 必须连续完成后再运行 App**：Task 0 冻结 schema，Task 1 才引入新字段；中间状态不要跑真机（理由见 §4.1）。

---

### Task 0：冻结 V7 + 新增 V8 + 迁移阶段（阻断 #1）

**Files**
- Modify: `App/WeekyiiPersistence.swift`
- Modify: `Tests/ModelTests.swift`

**Step 1：整块替换 `WeekyiiSchemaV7`**

把 `App/WeekyiiPersistence.swift:1459-1475`（现有 V7 定义）整块替换为 §4.4 的冻结版本（含注释 `NOTE: WeekyiiSchemaV7 is FROZEN...`）。

**Step 2：追加 `WeekyiiSchemaV8` + 迁移阶段**

在 V7 之后追加 §4.5 的 `WeekyiiSchemaV8`。**注意：本步 V8 的 `models` 列表与 V7 完全相同（9 个模型），不要写 `HabitModel.self`**（该模型 Task 1 才存在）。

修改 `WeekyiiMigrationPlan`（`WeekyiiPersistence.swift:715-744`）两处：
- `schemas` 数组追加 `WeekyiiSchemaV8.self`；
- `stages` 数组末尾追加 `.lightweight(fromVersion: WeekyiiSchemaV7.self, toVersion: WeekyiiSchemaV8.self)`。

**Step 3：更新版本锚点**

按 §4.6 表格逐行修改（:31、:44、:156、:192、:239；`Tests/ModelTests.swift:23` 的 `Schema.Version(7, 0, 0)` → `(8, 0, 0)`、:213/:226/:235 的 `"preflight-v7"` → `"preflight-v8"`）。

**Step 4：新增 V7 → V8 迁移测试**

在 `Tests/ModelTests.swift` 中紧跟 `test_publishedV6FixtureMigratesToV7`（:357-424）之后追加：

```swift
    @MainActor
    func test_publishedV7FixtureMigratesToV8() throws {
        let storeURL = try makeTemporaryStoreURL()
        do {
            let legacySchema = Schema(versionedSchema: WeekyiiSchemaV7.self)
            let legacyConfiguration = ModelConfiguration(
                "Weekyii",
                schema: legacySchema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfiguration)
            let context = legacyContainer.mainContext
            let week = WeekyiiSchemaV7.WeekModel(
                weekId: "2026-W40",
                startDate: Date(timeIntervalSince1970: 1_790_000_000),
                endDate: Date(timeIntervalSince1970: 1_790_518_400),
                status: .present
            )
            let day = WeekyiiSchemaV7.DayModel(
                dayId: "2026-09-28",
                date: Date(timeIntervalSince1970: 1_790_000_000),
                status: .draft
            )
            let project = WeekyiiSchemaV7.ProjectModel(
                name: "V7 project",
                startDate: Date(timeIntervalSince1970: 1_790_000_000),
                endDate: Date(timeIntervalSince1970: 1_790_518_400)
            )
            let task = WeekyiiSchemaV7.TaskItem(
                title: "V7 task",
                taskDescription: "carried over",
                taskType: .ddl,
                order: 1,
                zone: .draft
            )
            task.steps.append(WeekyiiSchemaV7.TaskStep(title: "V7 step", isCompleted: true, sortOrder: 1))
            task.attachments.append(WeekyiiSchemaV7.TaskAttachment(data: Data([7, 7, 7]), fileName: "v7.bin", fileType: "application/octet-stream"))
            task.project = project
            day.tasks.append(task)
            week.days.append(day)
            context.insert(week)
            context.insert(project)
            context.insert(WeekyiiSchemaV7.MindStampItem(text: "V7 stamp", imageBlob: Data([9, 9])))
            context.insert(WeekyiiSchemaV7.SuspendedTaskItem(title: "V7 suspended", decisionDeadline: Date(timeIntervalSince1970: 1_790_600_000), preferredCountdownDays: 3))
            context.insert(WeekyiiSchemaV7.TaskTypeDefinition(idRaw: "custom-v7", name: "V7 Type", iconName: "cloud", colorHex: "#445566", baseKindRaw: TaskType.regular.rawValue, sortOrder: 10))
            try context.save()
        }

        let container = try WeekyiiPersistence.makeModelContainer(storeURL: storeURL)
        let context = container.mainContext
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let projects = try context.fetch(FetchDescriptor<ProjectModel>())
        let stamps = try context.fetch(FetchDescriptor<MindStampItem>())
        let suspended = try context.fetch(FetchDescriptor<SuspendedTaskItem>())
        let taskTypes = try context.fetch(FetchDescriptor<TaskTypeDefinition>())

        XCTAssertEqual(tasks.map(\.title), ["V7 task"])
        XCTAssertEqual(tasks.first?.steps.map(\.title), ["V7 step"])
        XCTAssertEqual(tasks.first?.attachments.first?.data, Data([7, 7, 7]))
        XCTAssertEqual(tasks.first?.project?.name, "V7 project")
        XCTAssertEqual(projects.map(\.name), ["V7 project"])
        XCTAssertEqual(stamps.map(\.text), ["V7 stamp"])
        XCTAssertEqual(suspended.map(\.title), ["V7 suspended"])
        XCTAssertTrue(taskTypes.contains { $0.idRaw == "custom-v7" })
    }
```

**Step 5：构建 + 全量测试**

```
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' test
```
预期：全部通过，尤其：
- 既有 `test_publishedV6FixtureMigratesToV7`（V6 → V7 → V8 全链路仍可迁移）；
- 新增 `test_publishedV7FixtureMigratesToV8`；
- 既有 preflight 测试（改字面量后）。

**Step 6：真机/模拟器冒烟（冻结校验和的唯一实证手段）**

在**已安装旧版本、存有真实 V7 数据**的模拟器/真机上直接运行 Debug 构建，确认 App 正常启动、既有数据完整可读。
> 若此处崩溃或报 "Duplicate version checksums across stages detected"，说明冻结副本与线上 V7 存在字段级偏差 → 对照 §4.3 核对表逐字段修正后再试。

**Step 7：Commit**

```bash
git add App/WeekyiiPersistence.swift Tests/ModelTests.swift
git commit -m "refactor: freeze WeekyiiSchemaV7 and introduce WeekyiiSchemaV8 migration stage"
```

---

### Task 1：HabitModel + TaskItem.habit + 测试容器（阻断 #1/#7）

**Files**
- Create: `Models/HabitModel.swift`
- Modify: `Models/TaskItem.swift`
- Modify: `App/WeekyiiPersistence.swift`（V8 models 列表）
- Modify: `Tests/ModelTests.swift`、`Tests/StateMachineTests.swift`
- Modify: `Weekyii.xcodeproj/project.pbxproj`

**Step 1：落盘 `Models/HabitModel.swift`**

内容 = §3.1 全量代码。

**Step 2：`Models/TaskItem.swift` 加一行**

在 `var project: ProjectModel?`（第 26 行）之后追加 `var habit: HabitModel?`（§3.2）。

**Step 3：V8 追加新实体**

`WeekyiiSchemaV8.models` 末尾追加 `HabitModel.self`。（V7 冻结块**绝不**改动。）

**Step 4：注册 pbxproj**

按 §6 表注册 `Models/HabitModel.swift`（BuildFile `C0D3A007…`、FileReference `C0D3A008…`，4 个插入点）。

**Step 5：两处测试容器补 HabitModel**

- `Tests/StateMachineTests.swift:141-150` `makeContainer()`；
- `Tests/ModelTests.swift:3244` `makeContainer()`。

> `Tests/ModelTests.swift:2710`（`TaskPostponeServiceTests`）用的是 `Schema(versionedSchema: WeekyiiSchemaV4.self)`——冻结历史 schema，**不改动**。live 模型比旧实体多属性是既有常态（`taskTypeIdRaw` 就不在 V4 实体里），新增 `habit` 关系同样不参与该容器，无需处理。

**Step 6：单元测试**

追加到 `Tests/ModelTests.swift`：

```swift
    @MainActor
    func test_habitRelationshipRoundTripsThroughContext() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Date().startOfDay
        let day = DayModel(dayId: today.dayId, date: today, status: .draft)
        let habit = HabitModel(name: "冥想", category: .mindfulness, scheduleWeekdays: [1, 3, 5], startDayId: today.dayId)
        let task = TaskItem(title: "冥想", order: 1)
        task.day = day
        task.habit = habit
        day.tasks.append(task)
        context.insert(day)
        context.insert(habit)
        try context.save()

        let habits = try context.fetch(FetchDescriptor<HabitModel>())
        XCTAssertEqual(habits.count, 1)
        XCTAssertEqual(habits.first?.tasks.map(\.title), ["冥想"])
        XCTAssertEqual(habits.first?.scheduleWeekdays, [1, 3, 5])
        XCTAssertEqual(habits.first?.category, .mindfulness)
    }

    func test_habitWeekdayBitmaskEncodesISOWeekdays() throws {
        let habit = HabitModel(name: "Test", scheduleWeekdays: [7], startDayId: "2026-01-01")
        XCTAssertEqual(habit.scheduleWeekdays, [7])          // 只选周日
        habit.scheduleWeekdaysRaw = 0b0011111
        XCTAssertEqual(habit.scheduleWeekdays, [1, 2, 3, 4, 5])  // 工作日
        habit.scheduleWeekdaysRaw = 0
        XCTAssertEqual(habit.scheduleWeekdays, [])
        XCTAssertEqual(habit.scheduleSummary, "")
    }
```

**Step 7：构建 + 测试**

```
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' test
```

**Step 8：Commit**

```bash
git add Models/HabitModel.swift Models/TaskItem.swift App/WeekyiiPersistence.swift Tests/ModelTests.swift Tests/StateMachineTests.swift Weekyii.xcodeproj/project.pbxproj
git commit -m "feat: add HabitModel with weekday schedule and TaskItem.habit relationship"
```

---

### Task 2：幂等物化服务 + streak 计算（阻断 #4/#5/#10）

**Files**
- Create: `Services/HabitTaskMaterializer.swift`
- Modify: `Shared/Extensions/Date+Weekyii.swift`（§3.3）
- Modify: `Tests/ModelTests.swift`
- Modify: `Weekyii.xcodeproj/project.pbxproj`

**Step 1：日期工具扩展**

按 §3.3 追加 `Date.isoWeekday`、`WeekyiiDayId`、`WeekyiiWeekday`。

**Step 2：落盘 `Services/HabitTaskMaterializer.swift`**

```swift
import Foundation
import SwiftData

struct HabitMaterializeOutcome: Equatable {
    var createdCount: Int = 0
    var skippedExistingCount: Int = 0
    var blockedDayIds: [String] = []
    var failedDayIds: [String] = []
    var saveFailed: Bool = false

    var didChange: Bool { createdCount > 0 }
}

enum HabitAssignOutcome: Equatable {
    case created
    case alreadyExists
    case dayLocked
    case failed(String)
}

/// 幂等物化：把习惯按重复计划写入每日草稿区。
/// 语义见计划 §2.1 / §2.2 / §2.3。
@MainActor
struct HabitTaskMaterializer {
    static let horizonDays = 14

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 窗口物化

    @discardableResult
    func materialize(habits: [HabitModel], today: Date = Date()) -> HabitMaterializeOutcome {
        var outcome = HabitMaterializeOutcome()
        let todayStart = today.startOfDay
        let windowEnd = todayStart.addingDays(Self.horizonDays - 1)

        for habit in habits where habit.isActive {
            materializeWindow(habit: habit, todayStart: todayStart, windowEnd: windowEnd, outcome: &outcome)
        }

        if outcome.didChange {
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                outcome.saveFailed = true
                outcome.createdCount = 0
            }
        }
        return outcome
    }

    /// AppHealthCoordinator 入口：读取全部激活习惯后物化。
    @discardableResult
    func materializeAllHabits(today: Date = Date()) -> HabitMaterializeOutcome {
        let descriptor = FetchDescriptor<HabitModel>(sortBy: [SortDescriptor(\.sortOrder)])
        let habits = (try? modelContext.fetch(descriptor)) ?? []
        return materialize(habits: habits, today: today)
    }

    /// 手动把习惯加入某一天（不改动水位线）。仅允许今天及未来日期。
    @discardableResult
    func assign(habit: HabitModel, to date: Date, today: Date = Date()) -> HabitAssignOutcome {
        guard date.startOfDay >= today.startOfDay else { return .dayLocked }
        do {
            switch try materializeOne(habit: habit, date: date, today: today) {
            case .created:
                try modelContext.save()
                return .created
            case .alreadyExists:
                return .alreadyExists
            case .blocked:
                return .dayLocked
            }
        } catch {
            modelContext.rollback()
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - 内部实现

    private enum SingleDayResult {
        case created
        case alreadyExists
        case blocked
    }

    private func materializeWindow(
        habit: HabitModel,
        todayStart: Date,
        windowEnd: Date,
        outcome: inout HabitMaterializeOutcome
    ) {
        let schedule = habit.scheduleWeekdays
        guard !schedule.isEmpty else { return }

        let habitStart = habit.startDate?.startOfDay ?? todayStart
        let resume = habit.generatedThroughDate.map { $0.startOfDay.addingDays(1) } ?? habitStart
        var cursor = max(todayStart, resume)
        var lastProcessed: Date?

        while cursor <= windowEnd {
            let date = cursor
            cursor = cursor.addingDays(1)

            guard date >= habitStart, schedule.contains(date.isoWeekday) else { continue }

            do {
                switch try materializeOne(habit: habit, date: date, today: todayStart) {
                case .created:
                    outcome.createdCount += 1
                    lastProcessed = date
                case .alreadyExists:
                    outcome.skippedExistingCount += 1
                    lastProcessed = date
                case .blocked:
                    // 锁定日永久跳过，水位线越过（不回填）
                    outcome.blockedDayIds.append(date.dayId)
                    lastProcessed = date
                }
            } catch {
                // 瞬时故障：水位线冻结在失败日 − 1，下次重试该日
                outcome.failedDayIds.append(date.dayId)
                break
            }
        }

        if let lastProcessed {
            let current = habit.generatedThroughDate?.startOfDay ?? .distantPast
            if lastProcessed > current {
                habit.generatedThroughDate = lastProcessed
            }
        }
    }

    private func materializeOne(habit: HabitModel, date: Date, today: Date) throws -> SingleDayResult {
        let resolution = try WeekDataStore(modelContext: modelContext)
            .resolveDay(on: date, weekStatus: weekStatus(for: date))
        let day = resolution.day

        if day.tasks.contains(where: { $0.habit?.id == habit.id }) {
            return .alreadyExists
        }
        guard day.status == .empty || day.status == .draft else {
            return .blocked
        }

        let payload = TaskDraftPayload(
            title: habit.name,
            description: "",
            type: .regular,
            taskTypeIdRaw: nil,
            steps: [],
            attachments: []
        )
        let task = try TaskMutationService(modelContext: modelContext)
            .createTask(in: day, payload: payload, zone: .draft, project: nil)
        task.habit = habit
        return .created
    }

    /// 以"真实当前时间"判定周状态，避免测试注入 today 时把未来周创建为 .present。
    private func weekStatus(for date: Date) -> WeekStatus {
        let now = Date().startOfDay
        if date.weekId == now.weekId { return .present }
        return date.startOfDay < now ? .past : .pending
    }
}

// MARK: - Streak

@MainActor
struct HabitStreakCalculator {
    static func streakDays(for habit: HabitModel, today: Date = Date(), maxLookbackDays: Int = 365) -> Int {
        let schedule = habit.scheduleWeekdays
        guard !schedule.isEmpty else { return 0 }

        let completedDayIds = Set(habit.tasks.compactMap { task -> String? in
            guard task.zone == .complete, let dayId = task.day?.dayId else { return nil }
            return dayId
        })

        let calendar = Calendar(identifier: .iso8601)
        let todayStart = today.startOfDay
        let startDate = habit.startDate?.startOfDay

        var streak = 0
        for offset in 0..<maxLookbackDays {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { break }
            if let startDate, date < startDate { break }
            guard schedule.contains(date.isoWeekday) else { continue }

            if completedDayIds.contains(date.dayId) {
                streak += 1
            } else if offset > 0 {
                break
            }
            // offset == 0 且未完成 → 今天宽限：不计入也不打断
        }
        return streak
    }
}
```

**Step 3：注册 pbxproj**

按 §6 表注册 `Services/HabitTaskMaterializer.swift`（`C0D3A009…` / `C0D3A00A…`）。

**Step 4：单元测试（追加到 `Tests/ModelTests.swift`）**

```swift
    @MainActor
    func test_habitMaterializerFillsHorizonIdempotently() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Date().startOfDay
        let habit = HabitModel(name: "跑步", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: today.dayId)
        context.insert(habit)
        try context.save()

        let materializer = HabitTaskMaterializer(modelContext: context)
        let first = materializer.materialize(habits: [habit], today: today)
        XCTAssertEqual(first.createdCount, 10)                       // 14 天窗口恒含 10 个工作日
        // 水位线 = 窗口内最后一个计划日（今天为周日时为 today+12，其余为 today+13）
        let lastScheduled = (0..<14).map { today.addingDays($0) }.last { (1...5).contains($0.isoWeekday) }
        XCTAssertEqual(habit.generatedThroughDayId, lastScheduled?.dayId)

        // 回拨水位线后重跑：只跳过、不重复创建（幂等）
        habit.generatedThroughDate = nil
        let second = materializer.materialize(habits: [habit], today: today)
        XCTAssertEqual(second.createdCount, 0)
        XCTAssertEqual(second.skippedExistingCount, 10)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.count, 10)
        XCTAssertTrue(tasks.allSatisfy { $0.habit?.id == habit.id && $0.zone == .draft })
        XCTAssertTrue(tasks.allSatisfy { ($0.day?.status ?? .empty) == .draft })
    }

    @MainActor
    func test_habitMaterializerSkipsLockedDayWithoutBackfill() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Date().startOfDay
        let habit = HabitModel(name: "阅读", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: today.dayId)
        context.insert(habit)

        // 锁定窗口内第一个工作日（模拟"今天已 start"）
        let lockedDate = try XCTUnwrap((0..<7).map { today.addingDays($0) }.first { (1...5).contains($0.isoWeekday) })
        let lockedDay = DayModel(dayId: lockedDate.dayId, date: lockedDate, status: .execute)
        context.insert(lockedDay)
        try context.save()

        let outcome = HabitTaskMaterializer(modelContext: context).materialize(habits: [habit], today: today)
        XCTAssertEqual(outcome.blockedDayIds, [lockedDate.dayId])
        XCTAssertEqual(outcome.createdCount, 9)
        XCTAssertTrue(lockedDay.tasks.isEmpty)                       // 锁定日一个都不写
        // 不回填：水位线仍推进到窗口内最后一个计划日
        let lastScheduled = (0..<14).map { today.addingDays($0) }.last { (1...5).contains($0.isoWeekday) }
        XCTAssertEqual(habit.generatedThroughDayId, lastScheduled?.dayId)
    }

    @MainActor
    func test_habitMaterializerDoesNotRecreateDeletedTask() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Date().startOfDay
        let habit = HabitModel(name: "喝水", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: today.dayId)
        context.insert(habit)
        try context.save()

        let materializer = HabitTaskMaterializer(modelContext: context)
        _ = materializer.materialize(habits: [habit], today: today)

        let target = try XCTUnwrap(habit.tasks.first)
        let targetDay = try XCTUnwrap(target.day)
        targetDay.tasks.removeAll { $0.id == target.id }
        context.delete(target)
        try context.save()

        let second = materializer.materialize(habits: [habit], today: today)
        XCTAssertEqual(second.createdCount, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TaskItem>())
            .filter { $0.day?.dayId == targetDay.dayId && $0.habit?.id == habit.id }.isEmpty)
    }

    @MainActor
    func test_habitStreakIsWeekdayAwareWithTodayGrace() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        // 固定为周三（2026-09-16），避免在周末运行测试时"今天"不在计划内导致断言漂移
        let today = try XCTUnwrap(WeekyiiDayId.date(from: "2026-09-16"))
        // 逆推最近 6 个工作日
        var workdays: [Date] = []
        var cursor = today
        while workdays.count < 6 {
            if (1...5).contains(cursor.isoWeekday) { workdays.append(cursor) }
            cursor = cursor.addingDays(-1)
        }
        let habit = HabitModel(name: "冥想", scheduleWeekdays: [1, 2, 3, 4, 5], startDayId: workdays.last!.dayId)
        context.insert(habit)
        // 最近 4 个工作日已完成；今天（第 0 个）未完成 → 宽限
        for date in workdays[1...4] {
            let day = DayModel(dayId: date.dayId, date: date, status: .completed)
            let task = TaskItem(title: "冥想", order: 1, zone: .complete)
            task.day = day
            task.habit = habit
            day.tasks.append(task)
            context.insert(day)
        }
        try context.save()

        // 今天宽限 + 连续 4 天
        XCTAssertEqual(HabitStreakCalculator.streakDays(for: habit, today: today), 4)
        // 若今天已完成则为 5
        let todayDay = DayModel(dayId: today.dayId, date: today, status: .completed)
        let todayTask = TaskItem(title: "冥想", order: 1, zone: .complete)
        todayTask.day = todayDay
        todayTask.habit = habit
        todayDay.tasks.append(todayTask)
        context.insert(todayDay)
        try context.save()
        XCTAssertEqual(HabitStreakCalculator.streakDays(for: habit, today: today), 5)
    }
```

> 说明：`workdays[1...4]` 取的是「昨天起往前 4 个工作日」，第 5 个（`workdays[5]`）刻意未完成以验证打断。

**Step 5：构建 + 测试**

```
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' test
```

**Step 6：Commit**

```bash
git add Services/HabitTaskMaterializer.swift Shared/Extensions/Date+Weekyii.swift Tests/ModelTests.swift Weekyii.xcodeproj/project.pbxproj
git commit -m "feat: add idempotent habit materializer with rolling horizon and streak calculator"
```

---

### Task 3：HabitViewModel（阻断 #9/#11 的业务入口）

**Files**
- Create: `Features/Extensions/HabitViewModel.swift`
- Modify: `Tests/ModelTests.swift`
- Modify: `Weekyii.xcodeproj/project.pbxproj`

**Step 1：落盘 `Features/Extensions/HabitViewModel.swift`**

```swift
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class HabitViewModel {
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let materializer: HabitTaskMaterializer

    var habits: [HabitModel] = []
    var errorMessage: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.materializer = HabitTaskMaterializer(modelContext: modelContext)
    }

    var activeHabits: [HabitModel] { habits.filter(\.isActive) }
    var archivedHabits: [HabitModel] { habits.filter { !$0.isActive } }

    func refresh() {
        let descriptor = FetchDescriptor<HabitModel>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        habits = (try? modelContext.fetch(descriptor)) ?? []
    }

    func streakDays(for habit: HabitModel, today: Date = Date()) -> Int {
        HabitStreakCalculator.streakDays(for: habit, today: today)
    }

    // MARK: - Create

    @discardableResult
    func createHabit(
        name: String,
        iconName: String,
        colorHex: String,
        category: HabitCategory,
        scheduleWeekdays: Set<Int>,
        startDate: Date = Date()
    ) -> HabitModel? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "habit.error.name_empty", defaultValue: "习惯名称不能为空")
            return nil
        }
        guard !scheduleWeekdays.isEmpty else {
            errorMessage = String(localized: "habit.error.schedule_empty", defaultValue: "请至少选择一天")
            return nil
        }

        let habit = HabitModel(
            name: trimmed,
            iconName: iconName,
            colorHex: colorHex,
            category: category,
            scheduleWeekdays: scheduleWeekdays,
            startDayId: startDate.dayId,
            sortOrder: (habits.map(\.sortOrder).max() ?? 0) + 1
        )
        modelContext.insert(habit)
        guard save() else { return nil }
        refresh()

        // 立即物化：创建后马上出现在今天/未来两周的草稿区（§2.7-2）
        materializer.materialize(habits: [habit], today: Date())
        refresh()
        return habit
    }

    // MARK: - Update

    func updateHabit(
        _ habit: HabitModel,
        name: String,
        iconName: String,
        colorHex: String,
        category: HabitCategory,
        scheduleWeekdays: Set<Int>,
        startDate: Date
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !scheduleWeekdays.isEmpty else {
            errorMessage = String(localized: "habit.error.schedule_empty", defaultValue: "请至少选择一天")
            return
        }

        let planChanged = habit.scheduleWeekdays != scheduleWeekdays || habit.startDayId != startDate.dayId
        habit.name = trimmed
        habit.iconName = iconName
        habit.colorHex = colorHex
        habit.category = category
        habit.scheduleWeekdays = scheduleWeekdays
        habit.startDayId = startDate.dayId

        if planChanged {
            // 计划变化 → 水位线回拨到昨天，使新 weekday 在窗口内补生成（§2.1）
            habit.generatedThroughDate = Date().startOfDay.addingDays(-1)
        }
        guard save() else { return }
        refresh()
        materializer.materialize(habits: [habit], today: Date())
        refresh()
    }

    // MARK: - Archive / Restore

    func setActive(_ habit: HabitModel, isActive: Bool) {
        habit.isActive = isActive
        guard save() else { return }
        refresh()
        if isActive {
            // 恢复：水位线不动，窗口滑到今天后自然继续（§2.5）
            materializer.materialize(habits: [habit], today: Date())
            refresh()
        }
    }

    // MARK: - Delete

    func deleteHabit(_ habit: HabitModel) {
        let taskMutation = TaskMutationService(modelContext: modelContext)
        _ = taskMutation // 保留引用以便未来复用；删除与重编号在本方法内完成
        var daysToRenumber: Set<DayModel> = []

        for task in habit.tasks {
            guard let day = task.day else {
                modelContext.delete(task)
                continue
            }
            switch day.status {
            case .empty, .draft:
                day.tasks.removeAll { $0.id == task.id }
                modelContext.delete(task)
                daysToRenumber.insert(day)
            default:
                // 已开始的日期：保留任务，仅解除关联（§2.5）
                task.habit = nil
            }
        }

        for day in daysToRenumber {
            for (index, task) in day.sortedDraftTasks.enumerated() {
                task.order = index + 1
            }
        }

        modelContext.delete(habit)
        guard save() else { return }
        refresh()
    }

    // MARK: - Manual Assign

    func assign(_ habit: HabitModel, to date: Date) -> HabitAssignOutcome {
        let outcome = materializer.assign(habit: habit, to: date, today: Date())
        refresh()
        return outcome
    }

    // MARK: - Save

    @discardableResult
    private func save() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            errorMessage = String(localized: "habit.error.save_failed", defaultValue: "保存失败，请重试")
            return false
        }
    }
}
```

> 注：`deleteHabit` 第一行的 `_ = taskMutation` 只是占位说明——若实现时不使用 `TaskMutationService`，直接删掉这两行与 `let taskMutation` 声明，避免编译警告（重编号在下方循环内手工完成）。

**Step 2：注册 pbxproj**

按 §6 表注册 `Features/Extensions/HabitViewModel.swift`（`C0D3A00B…` / `C0D3A00C…`）。

**Step 3：单元测试（追加到 `Tests/ModelTests.swift`）**

```swift
    @MainActor
    func test_habitDeleteRemovesDraftTasksButKeepsStartedDayTasks() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Date().startOfDay
        let viewModel = HabitViewModel(modelContext: context)

        let habit = try XCTUnwrap(viewModel.createHabit(
            name: "拉伸", iconName: "figure.flexibility", colorHex: "#34C759",
            category: .fitness, scheduleWeekdays: [1, 2, 3, 4, 5], startDate: today
        ))
        XCTAssertFalse(habit.tasks.isEmpty)

        // 追加一个"已开始"日期上的关联任务（用昨天：在窗口外、必未被物化，避免 dayId 撞车）
        let startedDate = today.addingDays(-1)
        let startedDay = DayModel(dayId: startedDate.dayId, date: startedDate, status: .execute)
        let startedTask = TaskItem(title: "拉伸", order: 1, zone: .focus)
        startedTask.day = startedDay
        startedTask.habit = habit
        startedDay.tasks.append(startedTask)
        context.insert(startedDay)
        try context.save()

        let draftDayIds = Set(habit.tasks.compactMap { $0.day?.dayId })
        viewModel.deleteHabit(habit)

        let remaining = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(remaining.map(\.title), ["拉伸"])
        XCTAssertNil(remaining.first?.habit)                    // 已开始日期：任务保留、解除关联
        XCTAssertEqual(remaining.first?.zone, .focus)
        XCTAssertTrue(draftDayIds.allSatisfy { id in
            !remaining.contains { $0.day?.dayId == id && $0.habit != nil }
        })
        XCTAssertTrue(try context.fetch(FetchDescriptor<HabitModel>()).isEmpty)
        // 删除后草稿任务重新编号从 1 开始（空草稿区应得 []，而非 [1]）
        for day in try context.fetch(FetchDescriptor<DayModel>()) {
            XCTAssertEqual(day.sortedDraftTasks.map(\.order), day.sortedDraftTasks.indices.map { $0 + 1 })
        }
    }

    @MainActor
    func test_habitArchiveKeepsTasksAndStopsGeneration() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Date().startOfDay
        let viewModel = HabitViewModel(modelContext: context)
        let habit = try XCTUnwrap(viewModel.createHabit(
            name: "日记", iconName: "book.fill", colorHex: "#007AFF",
            category: .creativity, scheduleWeekdays: [1, 2, 3, 4, 5], startDate: today
        ))
        let taskCountBeforeArchive = habit.tasks.count

        viewModel.setActive(habit, isActive: false)
        XCTAssertEqual(habit.tasks.count, taskCountBeforeArchive)   // 归档保留任务

        let outcome = HabitTaskMaterializer(modelContext: context).materializeAllHabits(today: today)
        XCTAssertEqual(outcome.createdCount, 0)                     // 归档停止生成

        viewModel.setActive(habit, isActive: true)
        XCTAssertEqual(habit.tasks.count, taskCountBeforeArchive)   // 恢复不重复生成既有日期
    }

    @MainActor
    func test_habitUpdateRewindsWatermarkWhenPlanChanges() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let today = Date().startOfDay
        let viewModel = HabitViewModel(modelContext: context)
        let habit = try XCTUnwrap(viewModel.createHabit(
            name: "晨跑", iconName: "figure.run", colorHex: "#FF9500",
            category: .fitness, scheduleWeekdays: [1], startDate: today
        ))
        let beforeTaskCount = habit.tasks.count

        viewModel.updateHabit(
            habit, name: "晨跑", iconName: "figure.run", colorHex: "#FF9500",
            category: .fitness, scheduleWeekdays: [1, 2, 3, 4, 5], startDate: today
        )

        // 原计划只有周一 → 14 天窗口内恒为 2 个任务；改计划后补齐为 10 个工作日
        XCTAssertEqual(beforeTaskCount, 2)
        XCTAssertEqual(habit.tasks.count, 10)
    }
```

**Step 4：构建 + 测试**

```
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' test
```

**Step 5：Commit**

```bash
git add Features/Extensions/HabitViewModel.swift Tests/ModelTests.swift Weekyii.xcodeproj/project.pbxproj
git commit -m "feat: add HabitViewModel with archive/restore/delete semantics and manual assign"
```

---

### Task 4：归档导入/导出兼容 V8（阻断 #3）

**Files**
- Modify: `Services/DataArchiveService.swift`
- Modify: `Tests/ModelTests.swift`（`import CryptoKit`）

**Step 1：版本与结构体**

```swift
    static let currentSchemaVersion = 8          // :47，7 → 8
```

`Inspection`（:49-60）增加字段与摘要：

```swift
    struct Inspection: Equatable {
        let exportedAt: Date
        let weekCount: Int
        let dayCount: Int
        let taskCount: Int
        let projectCount: Int
        let habitCount: Int
        let taskTypeCount: Int

        var conciseSummary: String {
            "\(weekCount) 周 · \(dayCount) 天 · \(taskCount) 个任务 · \(projectCount) 个项目 · \(habitCount) 个习惯 · \(taskTypeCount) 个标签"
        }
    }
```

`Payload`（:72-82）在 `taskTypes` 之后插入 **可选** 的 `habits`（旧归档无此键 → 解密为 nil）：

```swift
    struct Payload: Codable {
        let weeks: [WeekRecord]
        let days: [DayRecord]
        let tasks: [TaskRecord]
        let projects: [ProjectRecord]
        let mindStamps: [MindStampRecord]
        let suspendedTasks: [SuspendedTaskRecord]
        let taskTypes: [TaskTypeRecord]
        let habits: [HabitRecord]?     // schema ≤ 7 的旧归档为 nil
        let settings: SettingsRecord
        let appState: AppStateRecord
    }
```

新增 `HabitRecord`，并给 `TaskRecord` 追加 `habitId`（**可选**；旧归档无此键 → nil）：

```swift
    struct HabitRecord: Codable {
        let id: UUID; let name: String; let iconName: String; let colorHex: String
        let categoryRaw: String; let scheduleWeekdaysRaw: Int
        let startDayId: String; let generatedThroughDayId: String
        let isActive: Bool; let createdAt: Date; let sortOrder: Int
    }

    struct TaskRecord: Codable {
        let id: UUID; let dayId: String?; let projectId: UUID?; let habitId: UUID?   // ← 新增
        let title: String; let taskDescription: String
        let taskType: TaskType; let taskTypeIdRaw: String; let order: Int; let zone: TaskZone
        let startedAt: Date?; let endedAt: Date?; let completedOrder: Int
        let steps: [StepRecord]; let attachments: [AttachmentRecord]
    }
```

**Step 2：导出映射**

`makePayload`（:193-212）新增 habits 抓取并在 `Payload(...)` 中赋值；`taskRecord(_:)`（:214-216）追加 `habitId: task.habit?.id`：

```swift
        let habits = try modelContext.fetch(FetchDescriptor<HabitModel>())
        // ...
            habits: habits.map { .init(
                id: $0.id, name: $0.name, iconName: $0.iconName, colorHex: $0.colorHex,
                categoryRaw: $0.categoryRaw, scheduleWeekdaysRaw: $0.scheduleWeekdaysRaw,
                startDayId: $0.startDayId, generatedThroughDayId: $0.generatedThroughDayId,
                isActive: $0.isActive, createdAt: $0.createdAt, sortOrder: $0.sortOrder
            ) },
```

**Step 3：`Inspection` 构造点（2 处）**

`inspect`（:149-156）与 `importReplacing`（:183-190）都追加 `habitCount: (payload.habits ?? []).count`。

**Step 4：校验 `validate`（:235-248）追加**

```swift
        try requireUnique((payload.habits ?? []).map(\.id), name: "习惯 ID")
        let habitIds = Set((payload.habits ?? []).map(\.id))
        guard payload.tasks.allSatisfy({ $0.habitId == nil || habitIds.contains($0.habitId!) }) else {
            throw WeekyiiArchiveError.invalidData("存在找不到所属习惯的任务。")
        }
```

**Step 5：`deleteAllData`（:254-267）追加**

```swift
        try deleteAll(HabitModel.self, in: context)
```

**Step 6：`insert`（:279-319）先插入习惯，再让任务挂接**

```swift
        var habits: [UUID: HabitModel] = [:]
        for record in payload.habits ?? [] {
            let item = HabitModel(
                name: record.name, iconName: record.iconName, colorHex: record.colorHex,
                category: HabitCategory(rawValue: record.categoryRaw) ?? .health,
                scheduleWeekdays: [], startDayId: record.startDayId, sortOrder: record.sortOrder
            )
            item.id = record.id
            item.scheduleWeekdaysRaw = record.scheduleWeekdaysRaw
            item.generatedThroughDayId = record.generatedThroughDayId
            item.isActive = record.isActive
            item.createdAt = record.createdAt
            context.insert(item)
            habits[record.id] = item
        }
```

任务循环内追加：

```swift
            if let habitId = record.habitId { item.habit = habits[habitId] }
```

**Step 7：测试（`Tests/ModelTests.swift` 顶部加 `import CryptoKit`）**

```swift
    @MainActor
    func test_dataArchiveRoundTripsHabitsAndTaskLinks() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let suiteName = "ModelTests.ArchiveHabits.\(UUID().uuidString)"
        let settings = UserSettings(defaults: UserDefaults(suiteName: suiteName)!)
        Self.retainedUserSettings.append(settings)
        let appState = AppState()

        let today = Date().startOfDay
        let habit = HabitModel(name: "冥想", iconName: "brain.head.profile", colorHex: "#AF52DE",
                               category: .mindfulness, scheduleWeekdays: [1, 3, 5], startDayId: today.dayId)
        habit.generatedThroughDayId = today.addingDays(6).dayId
        let day = DayModel(dayId: today.dayId, date: today, status: .draft)
        let task = TaskItem(title: "冥想", order: 1)
        task.day = day
        task.habit = habit
        day.tasks.append(task)
        context.insert(habit)
        context.insert(day)
        try context.save()

        let archive = try WeekyiiDataArchiveService.export(modelContext: context, settings: settings, appState: appState)
        XCTAssertEqual(try WeekyiiDataArchiveService.inspect(archive).habitCount, 1)

        _ = try WeekyiiDataArchiveService.importReplacing(
            archive,
            modelContext: context,
            settings: settings,
            appState: appState,
            storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("store")
        )

        let habits = try context.fetch(FetchDescriptor<HabitModel>())
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(habits.map(\.name), ["冥想"])
        XCTAssertEqual(habits.first?.scheduleWeekdays, [1, 3, 5])
        XCTAssertEqual(habits.first?.generatedThroughDayId, today.addingDays(6).dayId)
        XCTAssertEqual(tasks.first?.habit?.name, "冥想")
    }

    @MainActor
    func test_dataArchiveImportsLegacySchema7PayloadWithoutHabits() throws {
        let container = try WeekyiiPersistence.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let suiteName = "ModelTests.ArchiveLegacy.\(UUID().uuidString)"
        let settings = UserSettings(defaults: UserDefaults(suiteName: suiteName)!)
        Self.retainedUserSettings.append(settings)
        let appState = AppState()

        let today = Date().startOfDay
        let habit = HabitModel(name: "旧习惯", scheduleWeekdays: [2], startDayId: today.dayId)
        let day = DayModel(dayId: today.dayId, date: today, status: .draft)
        let task = TaskItem(title: "旧任务", order: 1)
        task.day = day
        task.habit = habit
        day.tasks.append(task)
        context.insert(habit)
        context.insert(day)
        try context.save()

        let modern = try WeekyiiDataArchiveService.export(modelContext: context, settings: settings, appState: appState)
        let legacy = try Self.downgradeArchiveToSchema7(modern)

        _ = try WeekyiiDataArchiveService.importReplacing(
            legacy,
            modelContext: context,
            settings: settings,
            appState: appState,
            storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("store")
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<HabitModel>()).isEmpty)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.map(\.title), ["旧任务"])
        XCTAssertNil(tasks.first?.habit)
    }

    /// 把 V8 归档降级成 schema 7 形态：去掉 habits 键与 task.habitId，重算 SHA256。
    private static func downgradeArchiveToSchema7(_ data: Data) throws -> Data {
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payloadBase64 = try XCTUnwrap(envelope["payload"] as? String)
        let payloadData = try XCTUnwrap(Data(base64Encoded: payloadBase64))
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])

        payload.removeValue(forKey: "habits")
        if let tasks = payload["tasks"] as? [[String: Any]] {
            payload["tasks"] = tasks.map { task -> [String: Any] in
                var task = task
                task.removeValue(forKey: "habitId")
                return task
            }
        }

        let downgraded = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        envelope["payload"] = downgraded.base64EncodedString()
        envelope["payloadSHA256"] = SHA256.hash(data: downgraded).map { String(format: "%02x", $0) }.joined()
        envelope["schemaVersion"] = 7
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }
```

**Step 8：构建 + 测试**

```
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' test
```

**Step 9：Commit**

```bash
git add Services/DataArchiveService.swift Tests/ModelTests.swift
git commit -m "feat: extend data archive with habit records and schema-8 compatibility"
```

---

### Task 5：Habit 来源徽章 + 任务视图接入（阻断 #8）

**Files**
- Modify: `Shared/Components/TaskRowView.swift`、`Shared/Components/TaskCard.swift`、`Features/Today/DraftEditorView.swift`、`Features/Today/TodayView.swift`、`Features/Today/FrozenZoneView.swift`（及任何渲染 `TaskCard` 的 Zone 视图）

**Step 1：新增 `TaskHabitOriginBadge`（`TaskRowView.swift`，紧跟 `TaskProjectOriginBadge`）**

```swift
struct TaskHabitOriginBadge: View {
    let habit: HabitModel?
    var isOnDarkBackground: Bool = false

    var body: some View {
        if let habit {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: habit.iconName)
                    .font(.caption2)
                Text(
                    String(
                        format: String(localized: "task.habit.origin", defaultValue: "习惯 · %@"),
                        habit.name
                    )
                )
                .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(isOnDarkBackground ? Color.white.opacity(0.95) : Color.textSecondary)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(isOnDarkBackground ? Color.white.opacity(0.16) : Color.backgroundTertiary, in: Capsule())
            .accessibilityIdentifier("taskHabitOriginBadge")
        }
    }
}
```

**Step 2：`TaskRowView` 增加参数**

- 属性区（:11 `showsProjectOrigin` 之后）加 `let showsHabitOrigin: Bool`；
- `init`（:19-29）加 `showsHabitOrigin: Bool = false` 并赋值；
- `body` 的项目徽章（:49-51）之后加：

```swift
                if showsHabitOrigin {
                    TaskHabitOriginBadge(habit: task.habit)
                }
```

**Step 3：`TaskCard` 增加参数**

- 属性区（:8 `showsProjectOrigin` 之后）加 `let showsHabitOrigin: Bool`；
- `init`（:16）加 `showsHabitOrigin: Bool = false`；
- `cardContent` 的项目徽章（:62-64）之后加同样两行（徽章放同一视觉槽位）。

**Step 4：调用点接线（规则：凡当前传 `showsProjectOrigin: true` 的调用点，同传 `showsHabitOrigin: true`；其余保持默认 false）**

- `DraftEditorView`（:195-198）：`TaskRowView(... showsProjectOrigin: true, showsHabitOrigin: true ...)`。
- `TodayView` Focus 大卡（:498-501）：在 `TaskProjectOriginBadge(project:isOnDarkBackground: true)` 之后加
  `TaskHabitOriginBadge(habit: focusTask.habit, isOnDarkBackground: true)`。
- `FrozenZoneView`：加 `var showsHabitOrigin: Bool = false`，透传给 `TaskCard`；`TodayView` 的 `FrozenZoneView(...)` 调用（:620-622）加 `showsHabitOrigin: true`（`showsProjectOrigin: true` 已存在）。
- 其它 Zone 视图（如存在 Step 4 规则命中的调用点）同理处理；**Complete 区不显示**（§2.6）。

**Step 5：构建 + 人工验证**

构建通过后，在模拟器中确认：Draft 行、Focus 大卡、Frozen 卡上都能看到「习惯 · 名称」徽章，且与项目徽章同行/同风格；Complete 区不出现。

**Step 6：Commit**

```bash
git add Shared/Components/TaskRowView.swift Shared/Components/TaskCard.swift Features/Today/DraftEditorView.swift Features/Today/TodayView.swift Features/Today/FrozenZoneView.swift
git commit -m "feat: show habit origin badge on draft rows, focus card and frozen cards"
```

---

### Task 6：Hub 横向习惯卡片 + 导航（v1 保留项）

**Files**
- Create: `Features/Extensions/HabitCarouselView.swift`
- Modify: `Features/Extensions/ExtensionsHubView.swift`
- Modify: `Weekyii.xcodeproj/project.pbxproj`

**Step 1：落盘 `Features/Extensions/HabitCarouselView.swift`**

```swift
import SwiftUI

struct HabitCarouselView: View {
    let viewModel: HabitViewModel
    let animationsActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            NavigationLink {
                HabitsFullView(viewModel: viewModel)
            } label: {
                HStack(spacing: WeekSpacing.xs) {
                    Image(systemName: "repeat.circle.fill")
                        .font(.caption.weight(.bold))
                    Text(String(localized: "extensions.module.habits.title", defaultValue: "习惯追踪"))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(String(localized: "habit.carousel.manage", defaultValue: "管理"))
                        .font(.caption2)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Color.accentGreen)
                .padding(.horizontal, WeekSpacing.base)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("extensionsHabitsSeeAllButton")

            if viewModel.activeHabits.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WeekSpacing.md) {
                        ForEach(viewModel.activeHabits) { habit in
                            NavigationLink {
                                HabitDetailView(habit: habit, viewModel: viewModel)
                            } label: {
                                HabitCarouselCard(habit: habit, streak: viewModel.streakDays(for: habit))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("habitCarouselCard_\(habit.name)")
                        }
                    }
                    .padding(.horizontal, WeekSpacing.base)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var emptyState: some View {
        NavigationLink {
            HabitsFullView(viewModel: viewModel)
        } label: {
            HStack(spacing: WeekSpacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentGreen)
                Text(String(localized: "extensions.hub.habits.empty", defaultValue: "还没有习惯，点击创建"))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
            .padding(WeekSpacing.md)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
            .padding(.horizontal, WeekSpacing.base)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("extensionsHabitsEmptyButton")
    }
}

// MARK: - Card

private struct HabitCarouselCard: View {
    let habit: HabitModel
    let streak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
            HStack(spacing: WeekSpacing.sm) {
                Image(systemName: habit.iconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(habit.habitColor)
                    .frame(width: 28, height: 28)
                    .background(habit.habitColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(habit.category.displayName)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(streak > 0 ? habit.habitColor : Color.textTertiary)
                Text(streak > 0
                     ? String(format: String(localized: "habit.streak.unit %lld", defaultValue: "连续 %lld 天"), streak)
                     : String(localized: "habit.streak.none", defaultValue: "尚未开始"))
                    .font(.caption2)
                    .foregroundStyle(streak > 0 ? Color.textSecondary : Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(WeekSpacing.md)
        .frame(width: 150, height: 96, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                .stroke(habit.habitColor.opacity(0.14), lineWidth: 1)
        )
    }
}
```

> `animationsActive` 暂时不参与布局（保留参数以便后续对齐 Project tile 的动画节奏）；若实现时未使用，可删除该参数及其传参，避免编译警告。

**Step 2：Hub 接入（`ExtensionsHubView.swift`）**

- 状态区（:24-26）加 `@State private var habitViewModel: HabitViewModel?`；
- `body` 的 `if let mindStampViewModel, let viewModel { ... }` 块内、`ProjectsModulePreview`（:49）**之前**插入：

```swift
                        if let habitViewModel {
                            HabitCarouselView(viewModel: habitViewModel, animationsActive: moduleTilesActive)
                        }
```

- `.onAppear`（:63-72）加：

```swift
            if habitViewModel == nil {
                habitViewModel = HabitViewModel(modelContext: modelContext)
            }
            habitViewModel?.refresh()
```

- `.refreshOnStateTransitions`（:73-76）加 `habitViewModel?.refresh()`；
- 错误提示：仿照既有写法增加 `.onChange(of: habitViewModel?.errorMessage) { _, newValue in if let newValue { errorMessage = newValue } }`。

**Step 3：注册 pbxproj**

按 §6 表注册 `Features/Extensions/HabitCarouselView.swift`（`C0D3A00D…` / `C0D3A00E…`）。

**Step 4：构建 + 人工验证**

进入 Extensions Hub：无习惯时显示空态入口；有习惯时显示横向卡片与 streak；点击卡片进详情、点「管理」进列表。

**Step 5：Commit**

```bash
git add Features/Extensions/HabitCarouselView.swift Features/Extensions/ExtensionsHubView.swift Weekyii.xcodeproj/project.pbxproj
git commit -m "feat: add habit carousel section to extensions hub"
```

---

### Task 7：习惯管理页 + 详情 + 指定日期加入（阻断 #9 的 UI 面）

**Files**
- Create: `Features/Extensions/HabitsFullView.swift`（含 `HabitDetailView`、`HabitAssignDatesSheet`）
- Modify: `Weekyii.xcodeproj/project.pbxproj`

**Step 1：落盘 `Features/Extensions/HabitsFullView.swift`**

```swift
import SwiftUI
import SwiftData

// MARK: - List

struct HabitsFullView: View {
    let viewModel: HabitViewModel

    @State private var editorTarget: HabitEditorTarget?

    var body: some View {
        List {
            if viewModel.activeHabits.isEmpty && viewModel.archivedHabits.isEmpty {
                Section {
                    VStack(spacing: WeekSpacing.md) {
                        Image(systemName: "repeat.circle")
                            .font(.largeTitle)
                            .foregroundStyle(Color.textTertiary)
                        Text(String(localized: "habits.empty.title", defaultValue: "还没有习惯"))
                            .foregroundStyle(Color.textSecondary)
                        Button(String(localized: "habits.empty.action", defaultValue: "新建习惯")) {
                            editorTarget = HabitEditorTarget(id: UUID(), habit: nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentGreen)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WeekSpacing.lg)
                }
            }

            if !viewModel.activeHabits.isEmpty {
                Section {
                    ForEach(viewModel.activeHabits) { habit in
                        NavigationLink {
                            HabitDetailView(habit: habit, viewModel: viewModel)
                        } label: {
                            HabitListRow(habit: habit, streak: viewModel.streakDays(for: habit))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.setActive(habit, isActive: false)
                            } label: {
                                Label(String(localized: "habit.action.archive", defaultValue: "停用"), systemImage: "archivebox")
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "habits.subtitle", defaultValue: "习惯会按重复计划自动出现在每日草稿区"))
                        .font(.caption)
                }
            }

            if !viewModel.archivedHabits.isEmpty {
                Section(String(localized: "habits.archived.section", defaultValue: "已停用")) {
                    ForEach(viewModel.archivedHabits) { habit in
                        HabitListRow(habit: habit, streak: 0)
                            .opacity(0.55)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    viewModel.setActive(habit, isActive: true)
                                } label: {
                                    Label(String(localized: "habit.action.restore", defaultValue: "恢复"), systemImage: "arrow.uturn.backward")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "habits.title", defaultValue: "我的习惯"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = HabitEditorTarget(id: UUID(), habit: nil)
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.accentGreen)
                }
                .accessibilityIdentifier("habitsCreateButton")
            }
        }
        .sheet(item: $editorTarget) { target in
            HabitEditorSheet(viewModel: viewModel, habit: target.habit)
        }
    }
}

struct HabitEditorTarget: Identifiable {
    let id: UUID
    let habit: HabitModel?
}

// MARK: - Row

private struct HabitListRow: View {
    let habit: HabitModel
    let streak: Int

    var body: some View {
        HStack(spacing: WeekSpacing.sm) {
            Image(systemName: habit.iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(habit.habitColor)
                .frame(width: 36, height: 36)
                .background(habit.habitColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: WeekSpacing.xs) {
                    Text(habit.category.displayName)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                    Text("·")
                        .foregroundStyle(Color.textTertiary)
                    Text(habit.scheduleSummary)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            if streak > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(habit.habitColor)
                    Text("\(streak)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(habit.habitColor)
                }
            }
        }
        .padding(.vertical, WeekSpacing.xs)
    }
}

// MARK: - Detail

struct HabitDetailView: View {
    let habit: HabitModel
    let viewModel: HabitViewModel

    @State private var showingEditor = false
    @State private var showingAssignSheet = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        List {
            Section {
                HStack(spacing: WeekSpacing.sm) {
                    Image(systemName: habit.iconName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(habit.habitColor)
                        .frame(width: 48, height: 48)
                        .background(habit.habitColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.name)
                            .font(.title3.weight(.bold))
                        Text("\(habit.category.displayName) · \(habit.scheduleSummary)")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.vertical, WeekSpacing.xs)
            }

            Section(String(localized: "habit.detail.stats", defaultValue: "统计")) {
                LabeledContent(String(localized: "habit.streak.none", defaultValue: "尚未开始"),
                               value: String(format: String(localized: "habit.streak.unit %lld", defaultValue: "连续 %lld 天"),
                                             viewModel.streakDays(for: habit)))
                LabeledContent(String(localized: "habit.detail.completed", defaultValue: "已完成"),
                               value: "\(habit.completedTaskCount)")
                LabeledContent(String(localized: "habit.detail.total", defaultValue: "累计"),
                               value: "\(habit.totalTaskCount)")
            }

            Section {
                Button {
                    showingAssignSheet = true
                } label: {
                    Label(String(localized: "habit.detail.assign_action", defaultValue: "选择日期"),
                          systemImage: "calendar.badge.plus")
                }
                .disabled(!habit.isActive)

                Button {
                    showingEditor = true
                } label: {
                    Label(String(localized: "habit.editor.edit_title", defaultValue: "编辑习惯"),
                          systemImage: "pencil")
                }

                Button {
                    viewModel.setActive(habit, isActive: !habit.isActive)
                } label: {
                    Label(habit.isActive
                          ? String(localized: "habit.action.archive", defaultValue: "停用")
                          : String(localized: "habit.action.restore", defaultValue: "恢复"),
                          systemImage: habit.isActive ? "archivebox" : "arrow.uturn.backward")
                }
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label(String(localized: "habit.detail.delete", defaultValue: "删除习惯"), systemImage: "trash")
                }
            }
        }
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            HabitEditorSheet(viewModel: viewModel, habit: habit)
        }
        .sheet(isPresented: $showingAssignSheet) {
            HabitAssignDatesSheet(habit: habit, viewModel: viewModel)
        }
        .confirmationDialog(
            String(localized: "habit.detail.delete", defaultValue: "删除习惯"),
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "habit.detail.delete", defaultValue: "删除习惯"), role: .destructive) {
                viewModel.deleteHabit(habit)
            }
            Button(String(localized: "action.cancel", defaultValue: "取消"), role: .cancel) { }
        } message: {
            Text(String(localized: "habit.detail.delete_confirm",
                        defaultValue: "删除后，未开始日期中的该习惯任务会被移除；已开始的日期仅解除关联。"))
        }
    }
}

// MARK: - Assign sheet

struct HabitAssignDatesSheet: View {
    let habit: HabitModel
    let viewModel: HabitViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date = Date()
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        String(localized: "habit.detail.assign_action", defaultValue: "选择日期"),
                        selection: $selectedDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                }

                if let resultMessage {
                    Section {
                        Text(resultMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Section {
                    Button(String(localized: "habit.assign.submit", defaultValue: "加入")) {
                        submit()
                    }
                    .disabled(!habit.isActive)
                }
            }
            .navigationTitle(String(localized: "habit.assign.title", defaultValue: "加入日期"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel", defaultValue: "取消")) { dismiss() }
                }
            }
        }
    }

    private func submit() {
        switch viewModel.assign(habit, to: selectedDate) {
        case .created:
            resultMessage = String(
                format: String(localized: "habit.assign.result.created", defaultValue: "已加入 %@"),
                selectedDate.dayId
            )
        case .alreadyExists:
            resultMessage = String(localized: "habit.assign.result.exists", defaultValue: "该日期已存在")
        case .dayLocked:
            resultMessage = String(localized: "habit.error.day_locked", defaultValue: "该日期已锁定，无法加入")
        case .failed(let message):
            resultMessage = message
        }
    }
}
```

**Step 2：注册 pbxproj**

按 §6 表注册 `Features/Extensions/HabitsFullView.swift`（`C0D3A00F…` / `C0D3A010…`）。

**Step 3：构建 + 人工验证**

Hub → 管理 → 列表；点行 → 详情；详情 → 「选择日期」→ 选日期 → 「加入」→ 结果提示正确（新建 / 已存在 / 锁定）；滑动归档 / 恢复。

**Step 4：Commit**

```bash
git add Features/Extensions/HabitsFullView.swift Weekyii.xcodeproj/project.pbxproj
git commit -m "feat: add habit management list, detail and date assign sheet"
```

---

### Task 8：习惯编辑表单（去批量语义）

**Files**
- Create: `Features/Extensions/HabitEditorSheet.swift`
- Modify: `Weekyii.xcodeproj/project.pbxproj`

**Step 1：落盘 `Features/Extensions/HabitEditorSheet.swift`**

> 与 v1 的差异：**删除**「未来 N 天」Stepper。生成语义由滚动窗口自动承担（§2.1），表单只负责计划本身，避免"批量生成"与"持续重复"混淆（评审问题 #5 的 UI 面）。

```swift
import SwiftUI

struct HabitEditorSheet: View {
    let viewModel: HabitViewModel
    let habit: HabitModel?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var iconName: String = "repeat.circle.fill"
    @State private var colorHex: String = "#34C759"
    @State private var category: HabitCategory = .health
    @State private var selectedWeekdays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var startDate: Date = Date()

    private let availableIcons = [
        "repeat.circle.fill", "heart.fill", "figure.run", "book.fill", "brain.head.profile",
        "drop.fill", "moon.fill", "flame.fill", "leaf.fill", "dumbbell.fill",
        "pencil.and.outline", "music.note", "bicycle", "fork.knife"
    ]

    private let availableColors = [
        "#34C759", "#007AFF", "#FF9500", "#FF3B30",
        "#AF52DE", "#FF2D55", "#5AC8FA", "#FFCC00"
    ]

    private var isEditing: Bool { habit != nil }
    private var previewColor: Color { Color(hex: colorHex) }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                iconSection
                colorSection
                categorySection
                scheduleSection
                startDateSection
            }
            .navigationTitle(isEditing
                ? String(localized: "habit.editor.edit_title", defaultValue: "编辑习惯")
                : String(localized: "habit.editor.create_title", defaultValue: "新建习惯"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel", defaultValue: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing
                           ? String(localized: "action.save", defaultValue: "保存")
                           : String(localized: "action.create", defaultValue: "创建")) {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedWeekdays.isEmpty)
                }
            }
            .onAppear {
                guard let habit else { return }
                name = habit.name
                iconName = habit.iconName
                colorHex = habit.colorHex
                category = habit.category
                selectedWeekdays = habit.scheduleWeekdays
                startDate = habit.startDate ?? Date()
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section(String(localized: "habit.editor.name", defaultValue: "名称")) {
            TextField(String(localized: "habit.editor.name_placeholder", defaultValue: "例如：冥想、跑步"), text: $name)
        }
    }

    private var iconSection: some View {
        Section(String(localized: "habit.editor.icon", defaultValue: "图标")) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: WeekSpacing.md) {
                ForEach(availableIcons, id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .foregroundStyle(iconName == icon ? previewColor : Color.textSecondary)
                        .background(iconName == icon ? previewColor.opacity(0.16) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { iconName = icon }
                        .accessibilityIdentifier("habitIcon_\(icon)")
                }
            }
            .padding(.vertical, WeekSpacing.xs)
        }
    }

    private var colorSection: some View {
        Section(String(localized: "habit.editor.color", defaultValue: "颜色")) {
            HStack(spacing: WeekSpacing.md) {
                ForEach(availableColors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().stroke(Color.textPrimary, lineWidth: colorHex == hex ? 2 : 0)
                        )
                        .contentShape(Circle())
                        .onTapGesture { colorHex = hex }
                        .accessibilityIdentifier("habitColor_\(hex)")
                }
            }
            .padding(.vertical, WeekSpacing.xs)
        }
    }

    private var categorySection: some View {
        Section(String(localized: "habit.editor.category", defaultValue: "分类")) {
            Picker(String(localized: "habit.editor.category", defaultValue: "分类"), selection: $category) {
                ForEach(HabitCategory.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.menu)
            .tint(previewColor)
        }
    }

    private var scheduleSection: some View {
        Section {
            HStack(spacing: WeekSpacing.sm) {
                ForEach(1...7, id: \.self) { weekday in
                    let isSelected = selectedWeekdays.contains(weekday)
                    Text(WeekyiiWeekday.localizedSymbol(for: weekday))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            isSelected ? previewColor.opacity(0.18) : Color.backgroundTertiary,
                            in: RoundedRectangle(cornerRadius: WeekRadius.small, style: .continuous)
                        )
                        .foregroundStyle(isSelected ? previewColor : Color.textSecondary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelected { selectedWeekdays.remove(weekday) } else { selectedWeekdays.insert(weekday) }
                        }
                        .accessibilityIdentifier("habitWeekday_\(weekday)")
                }
            }
            .padding(.vertical, WeekSpacing.xs)
        } header: {
            Text(String(localized: "habit.editor.schedule", defaultValue: "重复"))
        } footer: {
            Text(String(localized: "habit.editor.footer", defaultValue: "习惯按重复计划自动出现在每日草稿区；已开始的日期不会补写。"))
        }
    }

    private var startDateSection: some View {
        Section(String(localized: "habit.editor.start_date", defaultValue: "开始日期")) {
            DatePicker(
                String(localized: "habit.editor.start_date", defaultValue: "开始日期"),
                selection: $startDate,
                displayedComponents: .date
            )
            .accessibilityIdentifier("habitStartDatePicker")
        }
    }

    // MARK: - Save

    private func save() {
        let weekdays = selectedWeekdays.isEmpty ? [1, 2, 3, 4, 5] : Array(selectedWeekdays).sorted()

        if let habit {
            viewModel.updateHabit(
                habit,
                name: name,
                iconName: iconName,
                colorHex: colorHex,
                category: category,
                scheduleWeekdays: Set(weekdays),
                startDate: startDate
            )
        } else {
            viewModel.createHabit(
                name: name,
                iconName: iconName,
                colorHex: colorHex,
                category: category,
                scheduleWeekdays: Set(weekdays),
                startDate: startDate
            )
        }
        dismiss()
    }
}
```

**Step 2：注册 pbxproj**

按 §6 表注册 `Features/Extensions/HabitEditorSheet.swift`（`C0D3A011…` / `C0D3A012…`）。

**Step 3：构建 + 人工验证**

新建：选图标/颜色/分类/重复日/开始日期 → 创建 → 关闭后今天的 Draft 区应立刻出现该习惯任务（若今天在计划内且未开始）。编辑：改重复日 → 保存 → 窗口内应补齐新增 weekday。

**Step 4：Commit**

```bash
git add Features/Extensions/HabitEditorSheet.swift Weekyii.xcodeproj/project.pbxproj
git commit -m "feat: add habit editor sheet with weekday schedule and start date"
```

---

### Task 9：AppHealthCoordinator 触发 + `AppStateStore.bumpDataRevision`（阻断 #11）

**Files**
- Modify: `Services/StateMachine.swift`（协议）
- Modify: `App/WeekyiiApp.swift`（`AppHealthCoordinator.reconcile`）
- Modify: `Tests/StateMachineTests.swift`（`TestAppState`）

**Step 1：协议补方法**

`Services/StateMachine.swift:4-14`：

```swift
protocol AppStateStore: AnyObject {
    var systemStartDate: Date? { get set }
    var lastProcessedDate: Date? { get set }
    var lastRolloverAt: Date? { get set }
    var runtimeErrorMessage: String? { get set }
    var stateTransitionRevision: Int { get set }
    var dataRevision: Int { get set }          // ← 新增
    func save()
    func markProcessed(at date: Date)
    func incrementDaysStarted()
    func bumpStateTransitionRevision()
    func bumpDataRevision()                    // ← 新增
}
```

- `AppState`（`App/AppState.swift`）已实现 `dataRevision` 与 `bumpDataRevision()`，无需改动。
- `Tests/StateMachineTests.swift:11-31` `TestAppState` 增加：

```swift
        var dataRevision: Int = 0

        func bumpDataRevision() {
            dataRevision += 1
        }
```

- 全局搜索确认 `AppStateStore` 没有其它 conformer（除 `AppState`、`TestAppState` 外）。

**Step 2：`AppHealthCoordinator.reconcile` 接入物化**

`App/WeekyiiApp.swift:394-414`，在 `stateMachine.reconcile(...)` 与 `rescheduleNotificationsAfterReconcile()` 之后插入：

```swift
        let habitOutcome = HabitTaskMaterializer(modelContext: modelContainer.mainContext)
            .materializeAllHabits(today: timeProvider.now)
        if habitOutcome.didChange || habitOutcome.saveFailed {
            appState.bumpDataRevision()
        }
```

> 说明：`reconcile` 是启动 / 回前台 / 跨日 / 手动同步的统一入口（§2.7-1），无新增定时器；`didChange` 为 false 时不触发 UI 刷新，避免无意义的重绘。

**Step 3：构建 + 测试**

```
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' test
```

**Step 4：人工验证**

杀掉 App → 创建一个明天生效的习惯 → 重新启动 App → 明天（或把窗口内某一天）应已生成任务，且列表/今日页刷新。

**Step 5：Commit**

```bash
git add Services/StateMachine.swift App/WeekyiiApp.swift Tests/StateMachineTests.swift
git commit -m "feat: materialize habits during app health reconcile"
```

---

### Task 10：本地化落地

**Files**
- Modify: `Resources/Localizable.xcstrings`

**Step 1：把 §5 表格的 key 补齐**

优先方式：在 Xcode 中打开 String Catalog，先 `Cmd+B` 让编译器提取所有 `String(localized:defaultValue:)`（未落库的 key 会以中文 default 出现在列表中），再按 §5 表格逐条填 `en`。若手工编辑 JSON，请沿用文件内既有条目的结构（`extractionState` / `localizations.<lang>.stringUnit.{state,value}`），不要改动其它条目。

**Step 2：验证**

- `Cmd+B` 无警告；
- 切换系统语言为 English 运行，检查：Hub 区块标题、卡片、编辑表单、管理页、详情页、指派 sheet、徽章文案全部为英文；
- `%lld` 占位在英文下正确替换（`habit.streak.unit %lld`、无多余格式符）。

**Step 3：Commit**

```bash
git add Resources/Localizable.xcstrings
git commit -m "chore: add habit tracker localization entries"
```

---

### Task 11：全量验证（阻断 #7 的收口）

**Step 1：构建**

```
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' clean build
```

**Step 2：全量测试**

```
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' test
```

预期（对照 §8 测试矩阵）：全部通过，无新增跳过。

**Step 3：遗留物检查**

```bash
grep -rn "Calendar.iso8601" Weekyii/ || true          # 应为空
grep -rn "?? .green" Weekyii/Features/Extensions/ || true   # 应为空
grep -rn "HabitModel.self" Weekyii/App/WeekyiiPersistence.swift   # V8 列表 + 迁移计划各一处
```

**Step 4：Commit（如有修正）**

```bash
git add -A
git commit -m "chore: habit tracker verification fixes"
```

---

### Task 12：人工验收（必须逐条勾选）

| # | 场景 | 期望 |
|---|---|---|
| 1 | 在**已装有旧版本、含真实数据**的设备/模拟器上升级运行 | 数据完整、无迁移报错（V7 冻结的实证） |
| 2 | 已有习惯，跨日（改系统日期到明天）后重启 App | 新一天按计划生成；昨天的已完成任务不受影响 |
| 3 | 今天已 `start`（execute）后再创建习惯 | 今天不写入；明天起按计划写入 |
| 4 | 删除某天已生成的习惯任务后重启 App | 该任务**不复活** |
| 5 | 编辑重复日（如周一 → 周一~周五） | 窗口内新增的工作日补齐；已删除任务可能重建（§2.1 已声明） |
| 6 | 归档 → 恢复 | 归档停止生成且任务保留；恢复后不重复生成既有日期 |
| 7 | 删除习惯（含 draft 日与 execute 日） | draft 日任务消失且顺序重排；execute 日任务保留、无习惯徽章 |
| 8 | 详情 →「选择日期」加入未来某天 | 该天出现任务；重复加入提示"已存在"；选定过去日期不可选 |
| 9 | 两台设备（同 iCloud） | 习惯、任务、徽章同步一致 |
| 10 | Light/Dark 主题、中/英语言 | 徽章与卡片样式正确，无截断 |
| 11 | 归档导出 → 清空数据 → 导入 | 习惯、任务、关联关系全部还原；旧版本导出的归档也能导入（习惯为空） |

---

### Task 13：CloudKit 发布与发版

1. Debug 构建带 `-initializeCloudKitSchema` 启动一次（真机，登录 iCloud）。
2. CloudKit Dashboard 检查并 **Deploy Schema Changes to Production**（§4.7）：确认 `CD_HabitModel`、`CD_TaskItem.habit` 已上生产。
3. 归档 / TestFlight 发版（版本号按既有节奏递增）。
4. 发布后回归 Task 12 第 9、11 项。
5. 不需要重新提交审核、不需要重新申请 iCloud 能力。

---

## §8 测试矩阵（新增测试 → 覆盖的评审问题）

| 测试 | 位置 | 覆盖 |
|---|---|---|
| `test_publishedV7FixtureMigratesToV8` | ModelTests | #1 迁移链 |
| `test_habitRelationshipRoundTripsThroughContext` | ModelTests | #1 关系/逆关系 |
| `test_habitWeekdayBitmaskEncodesISOWeekdays` | ModelTests | #6 位掩码正确性 |
| `test_habitMaterializerFillsHorizonIdempotently` | ModelTests | #4 幂等、#5 窗口 |
| `test_habitMaterializerSkipsLockedDayWithoutBackfill` | ModelTests | #12 锁定日、#5 不回填 |
| `test_habitMaterializerDoesNotRecreateDeletedTask` | ModelTests | #5 删除不复活 |
| `test_habitStreakIsWeekdayAwareWithTodayGrace` | ModelTests | #10 streak |
| `test_habitDeleteRemovesDraftTasksButKeepsStartedDayTasks` | ModelTests | #9 删除语义 |
| `test_habitArchiveKeepsTasksAndStopsGeneration` | ModelTests | #9 归档/恢复 |
| `test_habitUpdateRewindsWatermarkWhenPlanChanges` | ModelTests | #5 计划回拨 |
| `test_dataArchiveRoundTripsHabitsAndTaskLinks` | ModelTests | #3 归档 |
| `test_dataArchiveImportsLegacySchema7PayloadWithoutHabits` | ModelTests | #3 向后兼容 |
| 既有 `test_publishedV6FixtureMigratesToV7`、preflight、archive 测试 | ModelTests | 回归 |

---

## §9 验收清单（Definition of Done）

- [ ] `WeekyiiSchemaV7` 已冻结为内嵌副本；`WeekyiiSchemaV8` 含 `HabitModel`；V7→V8 为 lightweight 阶段；§4.6 锚点全部更新。
- [ ] Task 12 第 1 项（真实 V7 数据升级）通过。
- [ ] 12 个新测试全部通过；既有测试零回归。
- [ ] 6 个新文件已注册进 pbxproj，`clean build` 通过。
- [ ] 归档导出/导入（新→新、旧→新）通过。
- [ ] 徽章范围与 Project 徽章一致（Draft / Focus / Frozen），Complete 不显示。
- [ ] CloudKit 生产 schema 已部署，双设备同步验证通过。
- [ ] 中英文界面文案完整。

---

## §10 风险与回滚

| 风险 | 触发信号 | 缓解 / 回滚 |
|---|---|---|
| 冻结副本与线上 V7 存在字段级偏差 | 旧数据设备启动失败 / "Duplicate version checksums" | 对照 §4.3 表格逐字段修正（同一 Task 内）；不推进到 Task 1 |
| CloudKit 未部署生产 schema | 线上同步报错、习惯不跨设备 | Task 13 顺序（先部署后发版）；已漏则补部署即可，不改代码 |
| 物化在窗口内创建大量 DayModel | Pending 周内出现意外日子 | 14 天窗口上限 + 幂等；如需收缩，改 `horizonDays` 一处即可 |
| 计划回拨导致已删除任务重建 | 用户反馈重复 | §2.1 已声明为设计取舍；必要时改为"仅补新增 weekday 的日期" |
| 归档缺少 habits 字段 | 导入旧归档丢习惯 | `Payload.habits` 为可选 + 校验引用；已有专门测试 |
| 整体回滚 | 上线后严重问题 | 回滚代码到 Task 0 之前；store 已迁移到 V8 → 不可逆，需用 preflight 备份恢复（`BackupRecoveryService` 快照，preflight-v8 命名） |

---

## §11 文件变更总表

| Action | 文件 | Task |
|---|---|---|
| Modify | `App/WeekyiiPersistence.swift` | 0（冻结 V7 + V8 + 锚点）、1（V8 加模型） |
| Create | `Models/HabitModel.swift` | 1 |
| Modify | `Models/TaskItem.swift` | 1 |
| Modify | `Tests/StateMachineTests.swift` | 1（容器）、9（TestAppState） |
| Create | `Services/HabitTaskMaterializer.swift` | 2 |
| Modify | `Shared/Extensions/Date+Weekyii.swift` | 2 |
| Create | `Features/Extensions/HabitViewModel.swift` | 3 |
| Modify | `Services/DataArchiveService.swift` | 4 |
| Modify | `Shared/Components/TaskRowView.swift` | 5 |
| Modify | `Shared/Components/TaskCard.swift` | 5 |
| Modify | `Features/Today/DraftEditorView.swift` | 5 |
| Modify | `Features/Today/TodayView.swift` | 5 |
| Modify | `Features/Today/FrozenZoneView.swift` | 5 |
| Create | `Features/Extensions/HabitCarouselView.swift` | 6 |
| Modify | `Features/Extensions/ExtensionsHubView.swift` | 6 |
| Create | `Features/Extensions/HabitsFullView.swift` | 7 |
| Create | `Features/Extensions/HabitEditorSheet.swift` | 8 |
| Modify | `Services/StateMachine.swift` | 9 |
| Modify | `App/WeekyiiApp.swift` | 9 |
| Modify | `Resources/Localizable.xcstrings` | 10 |
| Modify | `Tests/ModelTests.swift` | 0/1/2/3/4 |
| Modify | `Weekyii.xcodeproj/project.pbxproj` | 1/2/3/6/7/8 |

**总计**：6 个新文件、16 个修改文件、14 个提交（Task 0–13）。

