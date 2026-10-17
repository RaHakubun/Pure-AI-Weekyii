# Habit Tracker（习惯追踪）实施计划 v3 —— 仅今日物化 + 习惯记录

> **状态**：待评审后执行。本文件取代 `docs/plans/2026-09-16-habit-tracker.md`（v2）的**生成语义与 UI 范围**；v2 的 Schema 冻结/迁移/锚点/CloudKit 顺序仍然有效并被本文引用。
> **v3 核心变化（相对 v2）**：取消"滚动 14 天窗口 + 未来日生成"（违反"未来只能由用户显式点亮"不变量）；改为**只在当天首次协调时物化今日任务**；新增 `HabitDayRecord` 实体记录每日完成/漏做，供追踪页统计。**追加（2026-09-18 对齐）**：重复规则三选一（按星期 / 按月 / 不重复）；详情页为**完整时间线**（中断日显式标注）；习惯任务**不可后移**（确认前即拦截）。
> **执行方式**：严格按 Task 0 → Task 15 顺序执行，每个 Task 以"构建通过 + 测试通过 + commit"收尾。
> **事实基线**：本文所有行号、签名、pbxproj UUID 于 2026-09-18 在 `online-chatgpt-develop` 分支上逐项实测核对（相关文件当前无未提交改动）。

---

## §0 设计决策（用户未决问题 → 已采纳方案，评审可推翻）

| # | 分叉 | 采纳方案 | 理由 |
|---|---|---|---|
| D1 | 追踪历史怎么存？ | **新增 `HabitDayRecord` 实体**（pending/completed/missed 三态，一日一条） | 关键事实：日过期时 `StateMachine.expire` 会**删除** draft/focus/frozen 任务（`StateMachine.swift:273-290`），`TodayViewModel.expire` 同样（`:464-480`）。漏做的习惯实例在任务被删后不留任何痕迹，仅靠任务反推无法统计"漏做"。 |
| D2 | 未记录日（App 当天未打开 / 晚于 kill time / 日期锁定）怎么算？ | **跳过，不打断连续**；也不计入完成率分母 | 不可靠归因（无法区分"用户放弃这个习惯一阵子"还是"那天没打开 App"）；漏做只认"实际生成过但未完成"的日子，口径诚实。 |
| D3 | 重复规则？（2026-09-18 用户对齐后修订） | **三种重复方式，用户自选**：① 按星期（多选 ISO 周一~周日，含 每天/工作日/周末 快捷预设）；② 按月（多选 1–31 日；所选日在当月不存在时**该月跳过**不生成）；③ 不重复（仅开始日生成一次）。落盘 = `scheduleKindRaw` + 两个位掩码，随 V8 首版落地，**无追加迁移**。 | 用户原话："可以按照星期几重复，或者月份重复，或者不重复，用户自行选择月份的具体天数或者星期几"。早前 D3 仅含"按星期"，"每月固定日"曾被推迟到后续，本轮已并入。 |
| D4 | 详情页历史怎么呈现？（2026-09-18 用户补充要求） | **每个习惯一条完整时间线**（自开始日至今天，倒序、按月分组，不截断）；漏做日**显式标注「中断」**；**时间线取代月历网格 + 最近 30 条列表**（月历与时间线承载同一数据，双份视图违反"少卡片、单焦点"基调） | 用户原话："习惯追踪的任务历史，不要彻底遗忘……标记为当天这个习惯中断了……为每个习惯维护一条时间线。这样去做界面设计。" |

补充已定语义（v2 沿用或今日新定）：
- 生成范围**仅今天**，任何情况下不写未来日期、不创建未来周/日（未来点亮不变量）。
- 触发点：`AppHealthCoordinator.reconcile`（启动/回前台/分钟 tick/手动同步）+ 用户创建/编辑/恢复习惯后立即同步；不新增背景任务（iOS 无法保证 00:00 执行；用户不打开 App 时任务本就不需要）。
- 删除习惯任务后**当天不复活**（水位线）；用户主动"加入今日"可补回。
- 完成钩子挂在 `TodayViewModel.doneFocus`（`:241` 是全局唯一 `zone = .complete` 赋值点），与任务完成**同一次 save**，原子落盘。

---

## §1 目标 / 非目标 / 影响范围

### 目标
- Extensions 界面新增"习惯追踪"模块（Hub tile + 管理页 + 详情统计页 + 编辑表单）。
- 习惯定义重复规则；**当天**首次协调时把今日实例物化进今日草稿区（常规任务 + 来源徽章）。
- 追踪页：当前连续 / 最长连续 / 完成率 / 累计完成 / 今日状态 / **每个习惯一条完整时间线**（自开始日至今天逐日、倒序、按月分组；中断日显式标注「中断」，历史不遗忘）。
- 徽章覆盖：草稿行、专注大卡（暗底）、冻结卡；与 Project 徽章逐点对齐（Complete 区不显示）。
- 完全兼容现有本地存储、CloudKit 同步、数据归档三项既有能力。

### 非目标（v1 明确不做）
- 不做习惯提醒通知、不做背景任务（BGTaskScheduler）。
- 不做打卡备注/数值型目标（如"每天喝 8 杯水"）、不做手动补记历史。
- 不做跨设备实时冲突合并（承接既有 last-writer-wins）。
- 不改动任务流转逻辑本体（仅 doneFocus 内加一行"暂存记录"）、不改周视图/Pending 版面。

### 影响既有功能的边界（改动前清单）
| 类别 | 文件/行为 | 影响 |
|---|---|---|
| 数据 Schema | `App/WeekyiiPersistence.swift` | 冻结 V7 + 新增 V8（11 模型）+ 轻量迁移；**最高风险项** |
| 任务完成路径 | `Features/Today/TodayViewModel.swift:234-257` | +1 行暂存记录（同事务），完成行为本身不变 |
| 协调入口 | `App/WeekyiiApp.swift:404` | +3 行调用习惯同步（不额外触发全量刷新，见 §2.5） |
| 推迟守卫 | `Services/TaskPostponeService.swift:335-349`、`Models/WeekyiiError.swift` | 预览（:254）与执行（:292）前均拒绝习惯任务后移（+1 错误 case + 文案）；普通任务零变化 |
| 模型 | `Models/TaskItem.swift` | +1 关系 `habit`（可选，默认 nil；旧数据不受影响） |
| 归档 | `Services/DataArchiveService.swift` | schema 7 → 8，新增 habits/dayLogs 可选键（旧归档仍可导入） |
| 徽章 | `TaskRowView`/`TaskCard`/`FrozenZoneView`/`TodayView`/`DraftEditorView` | 新增参数默认 `false` → 现有调用点行为不变 |
| Hub | `Features/Extensions/ExtensionsHubView.swift` | +1 模块 tile（不改既有 3 个模块） |
| **绝不动** | 「过去」版块、任务流转、项目、周拓扑、通知、Live Activity、主题、既有 UI 测试基线 | — |

---

## §2 固定语义

### 2.1 仅今日物化 + 水位线（防无限创建）

- 每个习惯一个水位线 `generatedThroughDayId`（"已处理到的日期"，含；空串 = 从未处理）。
- 触发时：`guard habit.generatedThroughDayId < today.dayId`，否则跳过该习惯（**当天只处理一次**）。
- 处理结果无论 created / skippedExisting / blocked，水位线都推进到今天（仅 `failed` 不推进，留待重试）。
- **删除不复活**：当天物化后水位线 = 今天，用户手动删除今日任务后再次触发（60 秒 tick）不会重建。
- **计划回拨**：用户编辑重复星期 / 开始日期时，把水位线回拨到"昨天"，使今天可被重新评估（用户重新确认了计划）；对今天已被删除的任务会重新生成——这是声明过的取舍。
- 未来永远不写：循环体只有"今天"一个日期，不存在窗口。

### 2.2 幂等顺序（`materializeToday`）

对每个 isActive 习惯，顺序固定：

1. `!hasSchedule`（按星期/按月均未选日）→ 跳过；`startDayId > todayKey` → 跳过（未生效，水位线不动）。
2. `generatedThroughDayId >= todayKey` → 跳过（当天已处理）。
3. `!isScheduled(on: today)`（按星期未命中 / 按月该日不存在或不在选中集 / 不重复且非开始日）→ 推进水位线，跳过。
4. `existing`：今日 day 已存在 `task.habit?.id == habit.id` 的任务 → `skippedExisting`，推进水位线。
5. `locked`：今日 day 状态 ∉ {empty, draft}，或 `now >= killDate(today)` → `blocked`，推进水位线（不写任务、不写记录）。
6. `create`：`WeekDataStore.resolveDay(on: today, weekStatus: .present)` → `TaskMutationService.createTask(in:payload:zone:.draft, project:nil)`（内部自动把 `.empty` 提升为 `.draft`，`TaskPostponeService.swift:86-88`）→ `task.habit = habit` → 建 `HabitDayRecord(status: .pending, dayId: todayKey, createdAt: now)`，推进水位线。
7. 异常（save 抛错）→ `failedCount += 1`，水位线不动（下次重试）。

- 一次 `sync` 结束前只 `save()` 一次；失败则 `rollback()` 并置 `saveFailed = true`（created/missed 计数清零）。
- 任务负载：`TaskDraftPayload(title: habit.name, description: "", type: .regular, taskTypeIdRaw: nil, steps: [], attachments: [])`——常规类型，与用户"默认创建作为一个常规任务"一致。

### 2.3 记录（`HabitDayRecord`）三态与补记

| 状态 | 产生时机 | 说明 |
|---|---|---|
| `pending` | 物化今日任务时 | 今日已生成、未完成；只可能存在于"今天" |
| `completed` | `doneFocus` 完成该任务时（`HabitRecordService.stageCompletion`，同事务） | `completedAt` 记完成时刻；迟到的"后移任务"在别的日期完成也按 `task.day.dayId` 归账 |
| `missed` | **下一天及以后**首次 `sync` 的 sweep：`status == pending && dayId < todayKey` → `missed` | 无论当日是 expire（任务被删）还是手动删除任务，pending 最终都会补记为 missed |

- **显式可见（2026-09-18 用户要求）**：missed 在详情页时间线上显式标注为「中断」——**习惯历史不适用"过期即遗忘"**；「中断」（已生成未完成）与「未记录」（未生成，D2）在时间线上**必须视觉可区分**，避免不可靠归因误伤。
- **范围限定（2026-09-18 对齐）**：文案与语义改动**仅限习惯追踪域**（`habit.*` 键、习惯任务、习惯详情页）。「过去」版块与常规任务流的"过期 / 遗忘项"记录方式与文案**保持原样，一律不动**。
- **不落盘"未生成"**：无记录 + 计划内日期 ⇒ 未记录（D2 跳过）。落盘会带来不可靠归因。
- `habit.records` 由习惯级联删除（删除习惯即删除全部记录与统计）。
- 多设备重复记录容忍：读取时按 `dayId` 去重，取"最有利"状态（completed > missed > pending）。

### 2.4 完成钩子（`doneFocus`）

```swift
        let now = timeProvider.now
        let completedCount = day.completedTasks.count
        focusTask.zone = .complete
        focusTask.endedAt = now
        focusTask.completedOrder = completedCount + 1
        HabitRecordService.stageCompletion(for: focusTask, at: now)   // ← 新增（不 save）
```

- 位置：`TodayViewModel.swift:240-243` 之后、`try modelContext.save()`（:254）之前 → 与完成操作同一事务。
- `task.habit == nil` → 空操作；`task.day == nil` → 空操作。
- LiveActivity 完成路径经由同一 `doneFocus`（`WeekyiiApp.swift:273-274`），自动覆盖。

### 2.5 触发点

1. **`AppHealthCoordinator.reconcile`**（`WeekyiiApp.swift:393-414`）——`stateMachine.reconcile` 之后、`rescheduleNotificationsAfterReconcile` 之前插入习惯同步（无需返回值处理）。**不额外 `bumpDataRevision`**（P4 复核结论）：同一次调用内 `stateMachine.reconcile` 已提升 `stateTransitionRevision`（`StateMachine.swift:120`；仅同分钟去重时跳过，`:377-384`），Habit 相关视图全部以 `refreshOnStateTransitions` 订阅该字段；`dataRevision` 会触发 `ContentView` 的 `.id` 全量重建（`ContentView.swift:70`）重置导航栈，得不偿失。
2. **用户操作后立即同步**：创建习惯、编辑计划/开始日、恢复习惯、手动"加入今日"（`HabitViewModel` 内部）；成功后 `appState.bumpStateTransitionRevision()` 让 Today 等 VM 驱动视图即时刷新（`View+Modifiers.swift:8` 监听该字段）。
3. 进入 Hub / 习惯页只读取，不生成。

### 2.6 统计口径（`HabitStatisticsCalculator`）

- 数据源：`habit.records`（按 dayId 去重后）+ 重复计划（`scheduleKind` / `scheduleWeekdays` / `scheduleMonthDays`）+ `startDayId`。
- **当前连续**：自今天回溯最多 365 天；`date < startDay` 停止；非计划日跳过；执行中：`completed → +1`、`missed → 断`、`pending/无记录 → 跳过`（今天 pending 即"宽限"）。
- **最长连续**：自 startDay 到今天的计划日按时间正序扫描，规则同上，取最大连击。
- **完成率**：`completed / (completed + missed)`；分母 0 显示"—"；今日 pending 不计入分母。
- **累计完成**：completed 记录条数。
- **今日状态**：completed / pending / notGenerated（计划内但无记录：晚开、锁定、超时）/ notScheduled（今日不在计划）。
- **时间线（详情页主视图，决策 D4，取代原"月历 + 最近 30 条"方案）**：`startDayId` → 今天之间的全部**计划日**逐日成节点，倒序、按月分组（组头 "2026 年 9 月"），`LazyVStack` 懒加载、**不截断**；非计划日不出现。节点状态四选一：
  - `已完成`：实心习惯色圆点 + "已完成 08:12"（`habit.record.completed_at %@`）；
  - `中断`：警示色空心圆点 + "中断"（来自 missed 记录，用户要求显式标注，不遗忘）；
  - `待完成`：描边高亮，仅今天 pending 节点；
  - `未记录`：淡显空心点 + "未记录"（计划内无记录，D2 跳过口径；**与「中断」视觉可区分**）。
  - 脚注解释「中断」与「未记录」的口径差异（`habit.timeline.footer`）。

### 2.7 记录维度评估（用户问题："追踪页面的记录还有哪些要考虑？"）

| 维度 | v1 是否落盘 | 结论与理由 |
|---|---|---|
| 完成（含 `completedAt`） | ✅ | 打卡时间展示 + 未来趋势图基础，无需再加字段 |
| 漏做（missed，自动补记） | ✅ | 唯一的"失败"可见性来源（任务会被删除） |
| 待完成（pending） | ✅ | 今日状态 + 完成率分母排除今日 |
| 未生成（无记录） | ⛔ 由"计划内 + 无记录"推导 | 不可靠归因；D2 跳过口径；时间线上以淡显「未记录」呈现，与「中断」视觉可区分 |
| 时间线（每习惯完整历史） | ✅ 纯推导（无新增落盘字段） | 2026-09-18 用户要求："不要彻底遗忘、标记中断、每个习惯一条时间线"；数据源 = startDay→today 计划日 × 记录状态 |
| 水位线（每日是否已处理） | ✅（`generatedThroughDayId`，非用户可见） | 防无限创建/删除不复活 |
| 任务级绑定（taskId） | ⛔ | 任务可删除/后移；`habit + dayId` 已唯一，避免悬空引用 |
| 打卡备注 / 数值目标 | ⛔（后续 V9 迁移再加） | 需要新的输入与目标语义，v1 先验证使用频次 |
| 手动补记历史 | ⛔ | 时间线保留历史（不遗忘），但不支持把已过去的日子改写成"完成"；先观察真实需求 |
| 周报/趋势图 | ⛔（数据已具备，只差 UI） | completedAt/dayId 足够，后续纯 UI 迭代不需迁移 |
| 多设备重复记录 | ⚠️ 容忍 + 读取去重 | CloudKit last-writer-wins；去重成本低 |

### 2.8 归档 / 恢复 / 编辑 / 删除语义

| 操作 | HabitModel | 已生成任务 | 记录 | 后续生成 |
|---|---|---|---|---|
| 停用（`isActive = false`） | 保留（"已停用"分组） | 全部保留 | 全部保留 | 停止 |
| 恢复 | 保留 | 保留 | 保留 | 立即同步：今日匹配且可写则生成（水位线 < 今天，与"新建"一致） |
| 编辑计划/开始日 | 更新；水位线回拨为昨天 | 保留（不删除已生成任务） | 保留 | 今日重新评估：匹配则补建（已存在则跳过） |
| 删除 | 删除（记录级联删除） | `.empty`/`.draft` 日：删除该习惯任务并重新编号；`.execute` 及以后：保留任务、解除关联 | 随习惯级联删除 | 无 |
| 手动删除今日任务 | — | 删除 | pending 保留 → 次日 sweep 记 missed | 当天不复活；"加入今日"可补回 |

### 2.9 手动"加入今日"

- 详情页按钮；仅当习惯 isActive、今日在计划内、今日可写（status ∈ {empty, draft} 且未过 kill time）时成功。
- 绕过水位线（用户显式意图）；已有今日任务 → `.alreadyExists`；成功后水位线推进到今天。
- 结果枚举映射到提示文案（见 §6 的 `habit.action.add_today*` / `habit.error.*`）。

---

## §3 数据模型（完整代码，可直接落盘）

### 3.1 `Models/HabitModel.swift`（新建）

```swift
import Foundation
import SwiftData
import SwiftUI

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

enum HabitScheduleKind: String, CaseIterable, Codable, Identifiable {
    case weekly
    case monthly
    case once

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return String(localized: "habit.schedule.kind.weekly", defaultValue: "按星期")
        case .monthly: return String(localized: "habit.schedule.kind.monthly", defaultValue: "按月")
        case .once: return String(localized: "habit.schedule.kind.once", defaultValue: "不重复")
        }
    }
}

enum HabitError: LocalizedError, Equatable {
    case nameEmpty
    case scheduleEmpty
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .nameEmpty: return String(localized: "habit.error.name_empty", defaultValue: "习惯名称不能为空")
        case .scheduleEmpty: return String(localized: "habit.error.schedule_empty", defaultValue: "请至少选择一天")
        case .saveFailed: return String(localized: "habit.error.save_failed", defaultValue: "保存失败，请重试")
        }
    }
}

@Model
final class HabitModel {
    var id: UUID = UUID()

    var name: String = ""
    var iconName: String = "repeat.circle.fill"
    var colorHex: String = "#34C759"
    var categoryRaw: String = HabitCategory.health.rawValue

    /// 重复方式：weekly / monthly / once（不重复）。
    var scheduleKindRaw: String = HabitScheduleKind.weekly.rawValue
    /// 按星期位掩码：bit(weekday - 1)，Mon=bit0 ... Sun=bit6。默认周一至周五 = 0b0011111。
    var scheduleWeekdaysRaw: Int = 0b0011111
    /// 按月位掩码：bit(day - 1)，1 日=bit0 ... 31 日=bit30。默认空。
    var scheduleMonthDaysRaw: Int = 0
    /// 生效开始日（YYYY-MM-DD）；此前日期永不生成。
    var startDayId: String = ""
    /// 已处理到的日期（YYYY-MM-DD，含）；空串 = 从未处理。仅前进；用户编辑计划时回拨为昨天。
    var generatedThroughDayId: String = ""

    var isActive: Bool = true
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, originalName: "tasks", inverse: \TaskItem.habit)
    private var taskRecords: [TaskItem]? = []
    @Relationship(deleteRule: .cascade, originalName: "dayLogs", inverse: \HabitDayRecord.habit)
    private var recordEntries: [HabitDayRecord]? = []

    init(
        name: String,
        iconName: String = "repeat.circle.fill",
        colorHex: String = "#34C759",
        category: HabitCategory = .health,
        scheduleKind: HabitScheduleKind = .weekly,
        scheduleWeekdays: Set<Int> = [1, 2, 3, 4, 5],
        scheduleMonthDays: Set<Int> = [],
        startDayId: String,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.categoryRaw = category.rawValue
        self.scheduleKindRaw = scheduleKind.rawValue
        self.scheduleWeekdaysRaw = Self.encode(scheduleWeekdays)
        self.scheduleMonthDaysRaw = Self.encodeMonthDays(scheduleMonthDays)
        self.startDayId = startDayId
        self.sortOrder = sortOrder
    }

    var tasks: [TaskItem] {
        get { taskRecords ?? [] }
        set { taskRecords = newValue }
    }

    var records: [HabitDayRecord] {
        get { recordEntries ?? [] }
        set { recordEntries = newValue }
    }

    var category: HabitCategory {
        get { HabitCategory(rawValue: categoryRaw) ?? .health }
        set { categoryRaw = newValue.rawValue }
    }

    /// ISO weekday 集合：1 = 周一 ... 7 = 周日。
    var scheduleWeekdays: Set<Int> {
        get { Self.decode(scheduleWeekdaysRaw) }
        set { scheduleWeekdaysRaw = Self.encode(newValue) }
    }

    var scheduleKind: HabitScheduleKind {
        get { HabitScheduleKind(rawValue: scheduleKindRaw) ?? .weekly }
        set { scheduleKindRaw = newValue.rawValue }
    }

    /// 按月集合：1 ... 31。
    var scheduleMonthDays: Set<Int> {
        get { Self.decodeMonthDays(scheduleMonthDaysRaw) }
        set { scheduleMonthDaysRaw = Self.encodeMonthDays(newValue) }
    }

    /// 是否配置了可生成的计划日（`.once` 恒有效）。
    var hasSchedule: Bool {
        switch scheduleKind {
        case .weekly: return !scheduleWeekdays.isEmpty
        case .monthly: return !scheduleMonthDays.isEmpty
        case .once: return true
        }
    }

    var startDate: Date? { WeekyiiDayId.date(from: startDayId) }

    var generatedThroughDate: Date? {
        get { WeekyiiDayId.date(from: generatedThroughDayId) }
        set { generatedThroughDayId = newValue?.dayId ?? "" }
    }

    var habitColor: Color { Color(hex: colorHex) }

    var scheduleSummary: String {
        switch scheduleKind {
        case .once:
            guard let startDate else { return "" }
            let formatted = startDate.formatted(.dateTime.month().day())
            return String(localized: "habit.schedule.once %@", defaultValue: "仅 \(formatted) 一次")
        case .monthly:
            let days = scheduleMonthDays.sorted()
            guard !days.isEmpty else { return "" }
            let list = days.map(String.init).joined(separator: "、")
            return String(localized: "habit.schedule.monthly %@", defaultValue: "每月 \(list) 日")
        case .weekly:
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
    }

    /// 按重复方式判定某天是否应生成（按月缺日 / 不重复非开始日 → false，均不计入统计与时间线）。
    func isScheduled(on date: Date) -> Bool {
        switch scheduleKind {
        case .weekly:
            return scheduleWeekdays.contains(date.isoWeekday)
        case .monthly:
            return scheduleMonthDays.contains(Calendar(identifier: .iso8601).component(.day, from: date))
        case .once:
            return date.dayId == startDayId
        }
    }

    private static func encode(_ weekdays: Set<Int>) -> Int {
        weekdays.filter { (1...7).contains($0) }.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    private static func decode(_ mask: Int) -> Set<Int> {
        Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 })
    }

    private static func encodeMonthDays(_ days: Set<Int>) -> Int {
        days.filter { (1...31).contains($0) }.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    private static func decodeMonthDays(_ mask: Int) -> Set<Int> {
        Set((1...31).filter { mask & (1 << ($0 - 1)) != 0 })
    }
}
```

> CloudKit 约束核对：无 `@Attribute(.unique)`；全部属性有默认值；两个关系均为 `private … ? = []` + `originalName` + `inverse`（与 `ProjectModel`/`DayModel` 同构）。
> `deleteRule` 方向：`dayLogs` 用 `.cascade`（删习惯 → 删记录）；`tasks` 用 `.nullify`（删习惯 → 保留任务、解除关联，与 v2 语义一致）。

### 3.2 `Models/HabitDayRecord.swift`（新建）

```swift
import Foundation
import SwiftData

enum HabitDayRecordStatus: String, Codable, CaseIterable {
    case pending
    case completed
    case missed

    var displayName: String {
        switch self {
        case .pending: return String(localized: "habit.record.status.pending", defaultValue: "待完成")
        case .completed: return String(localized: "habit.record.status.completed", defaultValue: "已完成")
        case .missed: return String(localized: "habit.record.status.missed", defaultValue: "中断")
        }
    }
}

@Model
final class HabitDayRecord {
    var id: UUID = UUID()
    /// YYYY-MM-DD，与 DayModel.dayId / Date.dayId 同格式。
    var dayId: String = ""
    var statusRaw: String = HabitDayRecordStatus.pending.rawValue
    /// 记录创建时刻（= 物化时刻）。
    var createdAt: Date = Date()
    var completedAt: Date?
    var habit: HabitModel?

    init(dayId: String, createdAt: Date = Date()) {
        self.dayId = dayId
        self.createdAt = createdAt
    }

    var status: HabitDayRecordStatus {
        get { HabitDayRecordStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}
```

### 3.3 `Models/TaskItem.swift`（仅 +1 行）

在 `var project: ProjectModel?`（第 26 行）之后追加：

```swift
    var habit: HabitModel?
```

> `taskNumber` 等既有计算属性不动；`TaskMutationService.createTask` 不需要改（`habit` 由物化服务赋值）。

### 3.4 `Shared/Extensions/Date+Weekyii.swift`（追加）

```swift
extension Date {
    /// ISO weekday：1 = 周一 ... 7 = 周日。
    var isoWeekday: Int {
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: self)
        return weekday == 1 ? 7 : weekday - 1
    }
}

/// YYYY-MM-DD ↔ Date 的稳定互转（与 `Date.dayId` 的格式/时区一致）。
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

/// weekday 展示辅助（locale 驱动；`veryShortWeekdaySymbols` 为周日打头）。
enum WeekyiiWeekday {
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

> 实测坑（v2 已记录）：`Calendar(identifier:)` 的 `locale` 是固定 root locale，直接取符号恒为英文；必须显式 `locale = .autoupdatingCurrent`。索引为 `isoWeekday % 7`（周日打头：日一二三四五六）。

---

## §4 Schema 迁移：冻结 V7 + 新增 V8（11 模型）

### 4.1 现状（2026-09-18 复核）
`App/WeekyiiPersistence.swift:1459-1475` 的 `WeekyiiSchemaV7` 直接引用 **live 模型**（9 个）。给 live 模型加 `habit` 关系会**追溯性改写 V7 校验和**，与用户已落盘的 V7 store 不匹配（V2/V3 事故教训）。

### 4.2 修复方案
1. **冻结 V7**：把 v2 计划 §4.4（`docs/plans/2026-09-16-habit-tracker.md` 第 409 行起至代码块结束）的 `WeekyiiSchemaV7` 冻结块**逐字整块替换** 1459-1475 行。该块含 9 个内嵌副本（WeekModel/DayModel/TaskItem/TaskStep/TaskAttachment/ProjectModel/MindStampItem/SuspendedTaskItem/TaskTypeDefinition），已于 2026-09-16/18 两轮与 live 模型核对（存储字段逐一相符；init 签名的轻微差异仅存在于冻结副本内部，不影响校验和）。
2. **新增 V8**：`WeekyiiSchemaV8` 引用 live 模型；Task 0 先写 9 个（与 V7 同形），Task 1 追加 `HabitModel.self`、`HabitDayRecord.self`（最终 11 个）。
3. **迁移阶段**：`.lightweight(fromVersion: WeekyiiSchemaV7.self, toVersion: WeekyiiSchemaV8.self)`（新增实体 + 新增可选关系，均为轻量变更）。
4. **硬性规则（写入代码注释）**：`WeekyiiSchemaV8` 一旦发布即冻结；后续任何模型变更必须新建 V9。

> ⚠️ **Task 0 与 Task 1 之间禁止运行 App**（V8≡V7 形态的窗口期）。若 Task 0 的迁移测试报 "Duplicate version checksums across stages detected"，则把 Task 0 + Task 1 合并为一次落地（V8 首次出现即含 2 个新模型，形态与 V7 不同）。

### 4.3 `WeekyiiSchemaV8` 与迁移数组（Task 0 追加，Task 1 补模型）

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
            // Task 1 追加：
            HabitModel.self,
            HabitDayRecord.self,
        ]
    }
}
```

`WeekyiiMigrationPlan`（`:715-744`）两处：`schemas` 数组追加 `WeekyiiSchemaV8.self`；`stages` 末尾追加 `.lightweight(fromVersion: WeekyiiSchemaV7.self, toVersion: WeekyiiSchemaV8.self)`。

### 4.4 版本锚点表（2026-09-18 逐行复核）

| 文件:行 | 现值 | 改为 |
|---|---|---|
| `App/WeekyiiPersistence.swift:31` | `Schema(versionedSchema: WeekyiiSchemaV7.self)` | `...WeekyiiSchemaV8.self` |
| `App/WeekyiiPersistence.swift:44` | `for: WeekyiiSchemaV7.models` | `for: WeekyiiSchemaV8.models` |
| `App/WeekyiiPersistence.swift:156` | `"preflight-v7"` | `"preflight-v8"` |
| `App/WeekyiiPersistence.swift:192` | `"schema=7.0.0"` | `"schema=8.0.0"` |
| `App/WeekyiiPersistence.swift:239` | `schemaVersion: "7.0.0"` | `"8.0.0"` |
| `App/WeekyiiPersistence.swift:716-726` | schemas 数组 V1…V7 | 追加 `WeekyiiSchemaV8.self` |
| `App/WeekyiiPersistence.swift:742` | 最后 stage = V6→V7 | 追加 V7→V8 lightweight |
| `Tests/ModelTests.swift:23` | `Schema.Version(7, 0, 0)` | `(8, 0, 0)` |
| `Tests/ModelTests.swift:213/226/235` | 字面量 `"preflight-v7"` | `"preflight-v8"` |
| `Tests/ModelTests.swift:2711` | `Schema(versionedSchema: WeekyiiSchemaV4.self)` | **不改动**（冻结历史 schema；live 多属性是既有常态） |
| `Tests/ModelTests.swift:3244-3254` | `makeContainer()` Schema 列表 | 追加 `HabitModel.self`、`HabitDayRecord.self` |
| `Tests/StateMachineTests.swift:140-150` | `makeContainer()` Schema 列表（现 8 个） | 追加 `HabitModel.self`、`HabitDayRecord.self` |
| `Services/DataArchiveService.swift:47` | `currentSchemaVersion = 7` | `8`（Task 6） |

### 4.5 CloudKit 生产 Schema 发布顺序（v2 §4.7 原样沿用）

1. 真机 Debug 启动一次并附加参数 `-initializeCloudKitSchema`（`WeekyiiApp.swift:33-49` 已实现，仅 DEBUG 生效）。
2. CloudKit Dashboard → 容器 → Schema → **Deploy Schema Changes to Production**；确认出现 `CD_HabitModel`、`CD_HabitDayRecord` 实体与 `CD_TaskItem.habit` 关系。
3. 先部署 schema，后发 TestFlight / App Store。
4. 双设备同 iCloud 验证同步（含徽章与统计）。
5. 无需重新提交审核、无需新申请 iCloud 能力。

---

## §5 核心服务（完整代码）

### 5.1 `Services/HabitTaskMaterializer.swift`（新建）

```swift
import Foundation
import SwiftData

struct HabitSyncOutcome: Equatable {
    var createdCount: Int = 0
    var skippedExistingCount: Int = 0
    var blockedCount: Int = 0
    var failedCount: Int = 0
    var missedRecordCount: Int = 0
    var saveFailed: Bool = false
    /// 需要写库（含水位线推进）；不等于需要刷新 UI。
    fileprivate var needsSave: Bool = false

    /// 本次 sync 是否产生了新任务或补记（供测试与调用方判断；视图刷新由 stateTransitionRevision 承担）。
    var didChange: Bool { createdCount > 0 || missedRecordCount > 0 }
}

enum HabitAssignOutcome: Equatable {
    case created
    case alreadyExists
    case dayLocked
    case pastKillTime
    case notScheduledToday
    case failed(String)
}

/// 习惯记录暂存：在调用方事务内修改，不 save；保证与任务完成同一次落盘。
@MainActor
enum HabitRecordService {
    static func stageCompletion(for task: TaskItem, at date: Date) {
        guard let habit = task.habit,
              let dayId = task.day?.dayId,
              !dayId.isEmpty else { return }

        if let existing = habit.records.first(where: { $0.dayId == dayId }) {
            existing.status = .completed
            existing.completedAt = date
        } else {
            let record = HabitDayRecord(dayId: dayId, createdAt: date)
            record.status = .completed
            record.completedAt = date
            record.habit = habit
            habit.records.append(record)
        }
    }
}

/// 仅今日物化 + 过期记录补记。语义见计划 §2.1 / §2.2 / §2.3。
@MainActor
struct HabitTaskMaterializer {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 统一入口：补记过期 pending → 物化今日。单次 save。
    @discardableResult
    func sync(today: Date = Date(), now: Date = Date()) -> HabitSyncOutcome {
        var outcome = HabitSyncOutcome()
        let todayStart = today.startOfDay
        let todayKey = todayStart.dayId

        let descriptor = FetchDescriptor<HabitModel>(sortBy: [SortDescriptor(\.sortOrder)])
        let habits = (try? modelContext.fetch(descriptor)) ?? []

        outcome.missedRecordCount = sweepPendingRecords(habits: habits, todayKey: todayKey)
        if outcome.missedRecordCount > 0 { outcome.needsSave = true }

        for habit in habits where habit.isActive {
            materializeToday(habit: habit, todayStart: todayStart, todayKey: todayKey, now: now, outcome: &outcome)
        }

        if outcome.needsSave {
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                outcome.saveFailed = true
                outcome.createdCount = 0
                outcome.missedRecordCount = 0
            }
        }
        return outcome
    }

    /// 手动加入今日（绕过水位线；成功后水位线推进到今天）。语义见 §2.9。
    @discardableResult
    func assignToday(habit: HabitModel, today: Date = Date(), now: Date = Date()) -> HabitAssignOutcome {
        guard habit.isActive else { return .failed(HabitError.saveFailed.localizedDescription) }
        let todayStart = today.startOfDay
        let todayKey = todayStart.dayId
        guard habit.isScheduled(on: todayStart) else { return .notScheduledToday }

        do {
            let day = try WeekDataStore(modelContext: modelContext)
                .resolveDay(on: todayStart, weekStatus: .present).day

            if day.tasks.contains(where: { $0.habit?.id == habit.id }) {
                return .alreadyExists
            }
            guard day.status == .empty || day.status == .draft else { return .dayLocked }
            guard now < killDate(for: day) else { return .pastKillTime }

            try createHabitTask(habit: habit, in: day, todayKey: todayKey, now: now)
            habit.generatedThroughDayId = max(habit.generatedThroughDayId, todayKey)
            try modelContext.save()
            return .created
        } catch {
            modelContext.rollback()
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - 内部

    private func sweepPendingRecords(habits: [HabitModel], todayKey: String) -> Int {
        var missed = 0
        for habit in habits {
            for record in habit.records
            where record.statusRaw == HabitDayRecordStatus.pending.rawValue && record.dayId < todayKey {
                record.statusRaw = HabitDayRecordStatus.missed.rawValue
                missed += 1
            }
        }
        return missed
    }

    private func materializeToday(
        habit: HabitModel,
        todayStart: Date,
        todayKey: String,
        now: Date,
        outcome: inout HabitSyncOutcome
    ) {
        guard habit.hasSchedule else { return }
        guard habit.startDayId <= todayKey else { return }               // 尚未生效：不写水位线
        guard habit.generatedThroughDayId < todayKey else { return }     // 今日已处理（删除不复活）

        guard habit.isScheduled(on: todayStart) else {
            advanceWatermark(habit, to: todayKey, outcome: &outcome)
            return
        }

        do {
            let day = try WeekDataStore(modelContext: modelContext)
                .resolveDay(on: todayStart, weekStatus: .present).day

            if day.tasks.contains(where: { $0.habit?.id == habit.id }) {
                outcome.skippedExistingCount += 1
                advanceWatermark(habit, to: todayKey, outcome: &outcome)
                return
            }
            guard day.status == .empty || day.status == .draft, now < killDate(for: day) else {
                outcome.blockedCount += 1
                advanceWatermark(habit, to: todayKey, outcome: &outcome)
                return
            }

            try createHabitTask(habit: habit, in: day, todayKey: todayKey, now: now)
            advanceWatermark(habit, to: todayKey, outcome: &outcome)
            outcome.createdCount += 1
        } catch {
            outcome.failedCount += 1      // 水位线不动，下次重试
        }
    }

    private func createHabitTask(habit: HabitModel, in day: DayModel, todayKey: String, now: Date) throws {
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

        let record = HabitDayRecord(dayId: todayKey, createdAt: now)
        record.habit = habit
        habit.records.append(record)
    }

    private func advanceWatermark(_ habit: HabitModel, to todayKey: String, outcome: inout HabitSyncOutcome) {
        guard habit.generatedThroughDayId < todayKey else { return }
        habit.generatedThroughDayId = todayKey
        outcome.needsSave = true
    }

    private func killDate(for day: DayModel) -> Date {
        let calendar = Calendar(identifier: .iso8601)
        var components = calendar.dateComponents([.year, .month, .day], from: day.date)
        components.hour = day.killTimeHour
        components.minute = day.killTimeMinute
        components.second = 0
        return calendar.date(from: components) ?? .distantFuture
    }
}
```

> 说明：
> - `sync` 里 `needsSave` 只在确实有写入（记录补记 / 水位线推进）时为 true，避免每分钟 tick 都 save。
> - `assignToday` 用 `max(水位线, 今天)` 推进——若水位线已 > 今天（异常数据）不回退。
> - 不复用 v2 的 `horizonDays` / `materializeWindow` / `weekStatus(for:)`（仅今日物化后不需要测试注入周状态的 hack，恒 `.present`）。

### 5.2 `Services/HabitStatistics.swift`（新建）

```swift
import Foundation

enum HabitTodayStatus: Equatable {
    case completed
    case pending
    case notGenerated
    case notScheduled
}

/// 时间线节点状态（决策 D4：详情页为每个习惯维护一条完整历史时间线）。
enum HabitTimelineNodeState: Equatable {
    case completed
    case missed        // 显示为「中断」
    case pending       // 仅今天
    case unrecorded    // 计划内无记录（D2 跳过口径），与 missed 视觉可区分
}

struct HabitTimelineNode: Equatable, Identifiable {
    let dayId: String
    let date: Date
    let state: HabitTimelineNodeState
    let completedAt: Date?

    var id: String { dayId }
}

struct HabitStatistics: Equatable {
    let currentStreak: Int
    let longestStreak: Int
    let completedCount: Int
    let missedCount: Int
    let totalRecordedCount: Int
    let todayStatus: HabitTodayStatus

    var completionRate: Double? {
        totalRecordedCount == 0 ? nil : Double(completedCount) / Double(totalRecordedCount)
    }

    var completionRatePercent: Int? {
        completionRate.map { Int(($0 * 100).rounded()) }
    }
}

@MainActor
enum HabitStatisticsCalculator {
    static func statistics(for habit: HabitModel, today: Date = Date()) -> HabitStatistics {
        let map = recordStatusMap(for: habit)
        let todayStart = today.startOfDay
        return HabitStatistics(
            currentStreak: currentStreak(habit: habit, todayStart: todayStart, map: map),
            longestStreak: longestStreak(habit: habit, todayStart: todayStart, map: map),
            completedCount: map.values.filter { $0 == .completed }.count,
            missedCount: map.values.filter { $0 == .missed }.count,
            totalRecordedCount: map.values.filter { $0 != .pending }.count,
            todayStatus: todayStatus(habit: habit, todayStart: todayStart, map: map)
        )
    }

    /// 完整历史时间线（决策 D4）：startDay → today 的全部计划日，倒序。
    /// 纯推导，不新增落盘字段；非计划日不产生节点。
    static func timeline(for habit: HabitModel, today: Date = Date()) -> [HabitTimelineNode] {
        guard habit.hasSchedule, let start = habit.startDate?.startOfDay else { return [] }
        let map = recordStatusMap(for: habit)
        let completedTimes = completedAtMap(for: habit)

        let calendar = Calendar(identifier: .iso8601)
        let startDay = start.startOfDay
        var nodes: [HabitTimelineNode] = []
        var cursor = today.startOfDay
        var scanned = 0
        while cursor >= startDay, scanned < 3660 {
            scanned += 1
            if habit.isScheduled(on: cursor) {
                let state: HabitTimelineNodeState
                switch map[cursor.dayId] {
                case .completed: state = .completed
                case .missed: state = .missed
                case .pending: state = .pending
                case nil: state = .unrecorded
                }
                nodes.append(HabitTimelineNode(
                    dayId: cursor.dayId,
                    date: cursor,
                    state: state,
                    completedAt: completedTimes[cursor.dayId]
                ))
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return nodes
    }

    /// 同日多条 completed 记录（多设备合并）取最早打卡时刻。
    private static func completedAtMap(for habit: HabitModel) -> [String: Date] {
        var map: [String: Date] = [:]
        for record in habit.records where HabitDayRecordStatus(rawValue: record.statusRaw) == .completed {
            guard let completedAt = record.completedAt else { continue }
            if let existing = map[record.dayId] {
                map[record.dayId] = min(existing, completedAt)
            } else {
                map[record.dayId] = completedAt
            }
        }
        return map
    }

    /// 同日多条记录（CloudKit 多设备合并）取"最有利"状态：completed > missed > pending。
    static func recordStatusMap(for habit: HabitModel) -> [String: HabitDayRecordStatus] {
        var map: [String: HabitDayRecordStatus] = [:]
        for record in habit.records {
            let status = HabitDayRecordStatus(rawValue: record.statusRaw) ?? .pending
            guard let existing = map[record.dayId] else {
                map[record.dayId] = status
                continue
            }
            map[record.dayId] = Self.rank(status) > Self.rank(existing) ? status : existing
        }
        return map
    }

    static func currentStreak(
        habit: HabitModel,
        today: Date = Date(),
        map: [String: HabitDayRecordStatus]? = nil
    ) -> Int {
        let todayStart = today.startOfDay
        return currentStreak(habit: habit, todayStart: todayStart, map: map ?? recordStatusMap(for: habit))
    }

    static func longestStreak(
        habit: HabitModel,
        today: Date = Date(),
        map: [String: HabitDayRecordStatus]? = nil
    ) -> Int {
        longestStreak(habit: habit, todayStart: today.startOfDay, map: map ?? recordStatusMap(for: habit))
    }

    // MARK: - 内部

    private static func rank(_ status: HabitDayRecordStatus) -> Int {
        switch status {
        case .completed: return 2
        case .missed: return 1
        case .pending: return 0
        }
    }

    private static func currentStreak(
        habit: HabitModel,
        todayStart: Date,
        map: [String: HabitDayRecordStatus]
    ) -> Int {
        guard habit.hasSchedule, let start = habit.startDate?.startOfDay else { return 0 }

        let calendar = Calendar(identifier: .iso8601)
        let startDay = start.startOfDay
        var streak = 0
        for offset in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { break }
            let dayStart = date.startOfDay
            if dayStart < startDay { break }
            guard habit.isScheduled(on: dayStart) else { continue }

            switch map[dayStart.dayId] {
            case .completed: streak += 1
            case .missed: return streak
            case .pending, nil: continue      // 今天宽限；未记录日跳过（决策 D2）
            }
        }
        return streak
    }

    private static func longestStreak(
        habit: HabitModel,
        todayStart: Date,
        map: [String: HabitDayRecordStatus]
    ) -> Int {
        guard habit.hasSchedule, let start = habit.startDate?.startOfDay else { return 0 }

        var longest = 0
        var run = 0
        var cursor = start.startOfDay
        var guardCounter = 0
        while cursor <= todayStart, guardCounter < 3660 {
            if habit.isScheduled(on: cursor) {
                switch map[cursor.dayId] {
                case .completed:
                    run += 1
                    longest = max(longest, run)
                case .missed:
                    run = 0
                case .pending, nil:
                    break
                }
            }
            cursor = cursor.addingDays(1)
            guardCounter += 1
        }
        return longest
    }

    private static func todayStatus(
        habit: HabitModel,
        todayStart: Date,
        map: [String: HabitDayRecordStatus]
    ) -> HabitTodayStatus {
        guard habit.isActive,
              let start = habit.startDate,
              todayStart >= start.startOfDay,
              habit.isScheduled(on: todayStart) else { return .notScheduled }

        switch map[todayStart.dayId] {
        case .completed: return .completed
        case .pending: return .pending
        case .missed: return .notGenerated
        case nil: return .notGenerated
        }
    }
}
```

### 5.3 `Features/Today/TodayViewModel.swift`（+1 行）

见 §2.4；在 `:243` 之后、`:254` 之前插入 `HabitRecordService.stageCompletion(for: focusTask, at: now)`。

### 5.4 `App/WeekyiiApp.swift`（`AppHealthCoordinator.reconcile` 内 +3 行）

```swift
        let report = stateMachine.reconcile(now: timeProvider.now, force: force || trigger == .manualResync)

        HabitTaskMaterializer(modelContext: modelContainer.mainContext)
            .sync(today: timeProvider.today, now: timeProvider.now)

        rescheduleNotificationsAfterReconcile()
```

- 顺序选择：在 `rescheduleNotificationsAfterReconcile` **之前**（通知重排读取的数据包含新任务）。
- 不处理返回值、不 bump `dataRevision`（P4 复核结论，见 §2.5）：视图刷新由同一次 reconcile 内 StateMachine 已提升的 `stateTransitionRevision` 承担。

---

## §6 本地化（`Resources/Localizable.xcstrings`）

约定：代码用 `String(localized:defaultValue:)`（中文默认值）；Task 12 在**构建自动提取 key 之后**补 en 列。

| Key | 中文（defaultValue） | en |
|---|---|---|
| `task.habit.origin` | 习惯 · %@ | Habit · %@ |
| `extensions.module.habits.title` | 习惯追踪 | Habits |
| `extensions.hub.habits.empty` | 还没有习惯，点击创建 | No habits yet. Tap to create one. |
| `extensions.hub.habits.progress` | 今日 %lld/%lld | Today %lld/%lld |
| `habit.schedule.everyday` / `.weekdays` / `.weekend` | 每天 / 工作日 / 周末 | Every day / Weekdays / Weekends |
| `habit.schedule.kind.weekly` / `.monthly` / `.once` | 按星期 / 按月 / 不重复 | By weekday / By month / Once |
| `habit.schedule.monthly %@` | 每月 %@ 日 | Monthly on %@ |
| `habit.schedule.once %@` | 仅 %@ 一次 | Once on %@ |
| `habit.editor.monthly_footer` | 所选日期在当月不存在时（如 2 月 31 日），该月跳过。 | Months without the selected day are skipped. |
| `habit.category.*`（7 个） | 健康/运动/学习/正念/创造/社交/效率 | Health/Fitness/Learning/Mindfulness/Creativity/Social/Productivity |
| `habit.error.name_empty` / `.schedule_empty` / `.save_failed` / `.day_locked` | 名称空 / 至少一天 / 保存失败 / 日期已锁定 | Name required / Pick a day / Save failed / Date locked |
| `habit.error.not_scheduled_today` | 今天不在该习惯的重复计划内 | Today is not in this habit's schedule |
| `habit.error.past_kill_time` | 已过今日截止时间，明天会自动加入 | Past today's cutoff — it will return tomorrow |
| `habits.title` | 我的习惯 | My Habits |
| `habits.subtitle` | 习惯按重复计划在当天自动加入草稿区 | Habits join the draft zone on scheduled days |
| `habits.archived.section` | 已停用 | Archived |
| `habits.empty.title` | 还没有习惯 | No habits yet |
| `habits.empty.action` | 新建习惯 | New Habit |
| `habits.today.progress` | 今日完成 %lld/%lld | %lld of %lld done today |
| `habit.editor.create_title` / `edit_title` | 新建习惯 / 编辑习惯 | New Habit / Edit Habit |
| `habit.editor.name` / `.name_placeholder` | 名称 / 例如：冥想、跑步 | Name / e.g. Meditation, Running |
| `habit.editor.icon` / `.color` / `.category` / `.schedule` / `.start_date` | 图标 / 颜色 / 分类 / 重复 / 开始日期 | Icon / Color / Category / Repeat / Start Date |
| `habit.editor.footer` | 习惯在当天首次打开 App 时加入草稿区；已开始或已过截止时间的日期不会写入。 | Habits join the draft zone on the first launch of a scheduled day. Started or past-cutoff days are never written. |
| `habit.detail.add_today` | 加入今日 | Add to Today |
| `habit.detail.add_today.result.exists` | 今日已存在该习惯任务 | Already added today |
| `habit.action.archive` / `restore` | 停用 / 恢复 | Archive / Restore |
| `habit.detail.delete` | 删除习惯 | Delete Habit |
| `habit.detail.delete_confirm` | 删除后未开始日期中的该习惯任务会被移除，已开始的日期仅解除关联；全部打卡记录与统计将一并删除。 | Tasks in unstarted days are removed; started days only lose the link. All records and stats are deleted. |
| `habit.stats.title` | 统计 | Statistics |
| `habit.stats.current_streak` / `.longest_streak` / `.completion_rate` / `.total_completed` | 当前连续 / 最长连续 / 完成率 / 累计完成 | Current streak / Longest streak / Completion rate / Total completed |
| `habit.stats.days %lld` | %lld 天 | %lld days |
| `habit.stats.placeholder` | — | — |
| `habit.today.completed` / `.pending` / `.not_generated` / `.not_scheduled` | 今日已完成 / 今日待完成 / 今日未生成 / 今日无需 | Done today / Due today / Not generated / Not scheduled |
| `habit.timeline.title` | 时间线 | Timeline |
| `habit.timeline.footer` | 「中断」= 当日已生成但未完成；「未记录」= 当日未生成（未打开 App 或已过截止时间）。 | "Interrupted" = created that day but not finished; "not recorded" = never created (app not opened or past cutoff). |
| `habit.timeline.starts_on %@` | 将于 %@ 开始 | Starts %@ |
| `habit.record.status.pending` / `.completed` / `.missed` | 待完成 / 已完成 / 中断 | To do / Completed / Interrupted |
| `habit.record.completed_at %@` | 完成于 %@ | Completed at %@ |
| `habit.record.unrecorded` | 未记录 | Not recorded |

---

## §7 Xcode 工程注册（8 个新文件）

pbxproj 手工注册，UUID 沿用既有模式 `<序号>30A0000100BEEF01`（2026-09-18 复核现有最大序号 `C0D3A006`，`C0D3A007` 起无冲突）。

| 新文件 | PBXBuildFile | PBXFileReference | 归属 Group |
|---|---|---|---|
| `Models/HabitModel.swift` | `C0D3A00730A0000100BEEF01` | `C0D3A00830A0000100BEEF01` | Models |
| `Models/HabitDayRecord.swift` | `C0D3A00930A0000100BEEF01` | `C0D3A00A30A0000100BEEF01` | Models |
| `Services/HabitTaskMaterializer.swift` | `C0D3A00B30A0000100BEEF01` | `C0D3A00C30A0000100BEEF01` | Services |
| `Services/HabitStatistics.swift` | `C0D3A00D30A0000100BEEF01` | `C0D3A00E30A0000100BEEF01` | Services |
| `Features/Extensions/HabitViewModel.swift` | `C0D3A00F30A0000100BEEF01` | `C0D3A01030A0000100BEEF01` | Features/Extensions |
| `Features/Extensions/HabitsFullView.swift` | `C0D3A01130A0000100BEEF01` | `C0D3A01230A0000100BEEF01` | Features/Extensions |
| `Features/Extensions/HabitDetailView.swift` | `C0D3A01330A0000100BEEF01` | `C0D3A01430A0000100BEEF01` | Features/Extensions |
| `Features/Extensions/HabitEditorSheet.swift` | `C0D3A01530A0000100BEEF01` | `C0D3A01630A0000100BEEF01` | Features/Extensions |

每个 UUID 需在 **4 个位置**出现（按同组既有文件如 `WeekTopology.swift` / `OrderedTaskRow.swift` 定位，不依赖固定行号）：
1. `PBXBuildFile` 段；2. `PBXFileReference` 段；3. 对应 Group 的 `children`；4. `PBXSourcesBuildPhase` 的 `files`。

---

## §8 任务分解（Task 0 → Task 15）

> 通用约定：
> - 构建：`xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 16' build`（模拟器名按本机 `xcrun simctl list devices available` 调整）。
> - 测试：同上把 `build` 换成 `test`。
> - **长时任务（xcodebuild test）先与用户确认再跑**（前台/后台由用户决定）。
> - 每个 Task 末尾 commit；commit message 用给定文案。

### Task 0：冻结 V7 + 新增 V8 + 迁移阶段
**Files**：`App/WeekyiiPersistence.swift`、`Tests/ModelTests.swift`

1. 整块替换 `WeekyiiPersistence.swift:1459-1475`：取 v2 计划 §4.4 的冻结 `WeekyiiSchemaV7`（9 个内嵌副本），逐字落盘；**落盘后逐字段核对**（对照 §4.3 变化核对表的 9 行 + TaskItem/DayModel 实文件），重点：`originalName`、`inverse`、默认值、`@Attribute(.externalStorage)`。
2. 追加 `WeekyiiSchemaV8`（本步 9 模型，不要写 Habit*）；`WeekyiiMigrationPlan` 两处修改（§4.3）。
3. 更新锚点（§4.4 中除 archive 行外的全部）。
4. 新增测试 `test_publishedV7FixtureMigratesToV8`（v2 Task 0 Step 4 代码原样可用，V7 fixture 覆盖 9 类实体）。
5. 构建 + 全量测试；**Task 0/1 之间不运行 App**。
6. Commit：`refactor: freeze WeekyiiSchemaV7 and introduce WeekyiiSchemaV8 migration stage`

### Task 1：HabitModel + HabitDayRecord + TaskItem.habit
**Files**：新建 2 个模型文件、`Models/TaskItem.swift`、`App/WeekyiiPersistence.swift`、`Tests/ModelTests.swift`、`Tests/StateMachineTests.swift`、`Weekyii.xcodeproj/project.pbxproj`

1. 落盘 §3.1 / §3.2 代码（`HabitError` 也在 §3.1）。
2. `TaskItem.swift` 第 26 行后 +1 行（§3.3）。
3. `WeekyiiSchemaV8.models` 末尾追加 `HabitModel.self`、`HabitDayRecord.self`（V7 冻结块绝不动）。
4. pbxproj 注册 2 个模型文件（§7 前两行 UUID）。
5. 两处测试 `makeContainer()` 追加 2 个模型（ModelTests:3244、StateMachineTests:140）。
6. 测试：`test_habitRelationshipRoundTripsThroughContext`（habit↔task、habit↔record 双向）、`test_habitWeekdayBitmaskEncodesISOWeekdays`（v2 Task 1 Step 6 代码 + record 断言）。
7. Commit：`feat: add HabitModel, HabitDayRecord and TaskItem.habit relationship`

### Task 2：日期工具 + 物化服务
**Files**：`Shared/Extensions/Date+Weekyii.swift`、新建 `Services/HabitTaskMaterializer.swift`、`Tests/ModelTests.swift`、pbxproj

1. 追加 §3.4 日期工具。
2. 落盘 §5.1 代码。
3. pbxproj 注册（`C0D3A00B/C0D3A00C`）。
4. 测试（在 `Tests/ModelTests.swift`）：
   - `test_habitSyncCreatesOnlyTodayAndIsIdempotent`：工作日习惯，sync 两次 → 今日 1 任务 + 1 pending 记录 + 水位线=今天；其它日期 0 任务（关键：仓库里不存在任何 dayId > today 的 DayModel 断言，钉死"未来不写"）。
   - `test_habitSyncSkipsLockedDayAndAdvancesWatermark`：今日 status=.execute → created=0、blocked=1、无任务无记录、水位线=今天；再次 sync 不重试。
   - `test_habitSyncSkipsWhenPastKillTime`：now > killDate → blocked、无任务、无记录。
   - `test_habitSyncSkipsNotScheduledAndFutureStart`：今日非计划 / startDayId 为明天 → 无任务。
   - `test_habitSyncSweepsPendingRecordsToMissed`：昨日 pending → sync → missed；今日 pending 不动。
   - `test_habitStageCompletionUpsertsCompletedRecord`：stageCompletion 到已有 pending 与无记录两种情形 → completed + completedAt。
   - `test_habitAssignTodayBypassesWatermarkAndRejectsLocked`：水位线=今天时 assignToday 仍可补建（先删除任务）；今日 execute → .dayLocked；非计划日 → .notScheduledToday。
5. Commit：`feat: add today-only habit materializer with record sweep and completion staging`

### Task 3：统计计算器
**Files**：新建 `Services/HabitStatistics.swift`、`Tests/ModelTests.swift`、pbxproj

1. 落盘 §5.2 代码。
2. 测试 `test_habitStatisticsStreakRateAndDedupe`：固定 2026-09-16（周三）；构造 5 个工作日记录（4 完成 + 1 missed + 1 天无记录）→ 断言 currentStreak / longestStreak / 完成率 / 累计；同一 dayId 两条记录（completed + missed）→ 去重取 completed。
3. Commit：`feat: add habit statistics calculator with weekday-aware streaks`

### Task 4：完成钩子
**Files**：`Features/Today/TodayViewModel.swift`、`Tests/StateMachineTests.swift` 或 `Tests/ModelTests.swift`

1. `doneFocus` 插入 §2.4 的 1 行。
2. 测试（复用 StateMachineTests 的 TodayViewModel 测试设施，`:321` 等处有现成 setUp）：启动日 → 给今日任务挂 habit → doneFocus → 断言记录 completed；习惯任务在队列中非首位时，完成到它才记录（前面任务完成不产生记录）。
3. Commit：`feat: record habit completion when focus task is finished`

### Task 5：HabitViewModel
**Files**：新建 `Features/Extensions/HabitViewModel.swift`、`Tests/ModelTests.swift`、pbxproj

接口（`@MainActor @Observable`，与 `ExtensionsViewModel` 同构；持有 `modelContext` + `appState: AppState`）：

```swift
    var activeHabits: [HabitModel]
    var archivedHabits: [HabitModel]
    var errorMessage: String?

    func refresh()
    func createHabit(name:iconName:colorHex:category:scheduleKind:scheduleWeekdays:scheduleMonthDays:startDate:) throws -> HabitModel
    func updateHabit(_ habit: HabitModel, name:iconName:colorHex:category:scheduleKind:scheduleWeekdays:scheduleMonthDays:startDate:) throws
    func assignToday(_ habit: HabitModel) throws -> HabitAssignOutcome
    func setActive(_ habit: HabitModel, _ isActive: Bool) throws
    func deleteHabit(_ habit: HabitModel) throws
    func statistics(for habit: HabitModel) -> HabitStatistics
```

语义要点：
- `createHabit`：校验（name 非空 → `HabitError.nameEmpty`；schedule 非空 → `.scheduleEmpty`）→ 落盘 → `sync()` → `appState.bumpStateTransitionRevision()`。
- `updateHabit`：若 `scheduleKindRaw` / `scheduleWeekdaysRaw` / `scheduleMonthDaysRaw` / `startDayId` 任一变化 → `habit.generatedThroughDayId = 今天 − 1 天`（回拨，仅当原水位线 ≥ 昨天）→ `sync()` → bump。
- `deleteHabit`（§2.8）：先记 `let linkedTasks = habit.tasks`；`modelContext.delete(habit)`（记录级联删除、任务关系 nullify）→ 对 `linkedTasks` 中 `.empty`/`.draft` 日的任务：从 day 移除 + `modelContext.delete(task)` + `normalizeOrder(in:zone:.draft)`；保存；bump。
- `setActive(false)`：置位保存；`setActive(true)`：置位 → `sync()` → bump。

测试：`test_habitDeleteRemovesDraftTasksAndKeepsStartedDayTasks`、`test_habitArchiveStopsGenerationAndRestoreResumesToday`、`test_habitUpdateRewindsWatermarkWhenPlanChanges`、`test_habitCreateMaterializesTodayWhenScheduled`。
Commit：`feat: add habit view model with today-only lifecycle actions`

### Task 6：归档兼容 V8
**Files**：`Services/DataArchiveService.swift`、`Tests/ModelTests.swift`（顶部 `import CryptoKit`）

1. `currentSchemaVersion = 8`（:47）。
2. `Inspection` 加 `habitCount`；`conciseSummary` 追加 `· \(habitCount) 个习惯`。
3. `Payload` 在 `taskTypes` 后插入 `let habits: [HabitRecord]?`；新增：

```swift
    struct HabitRecord: Codable {
        let id: UUID; let name: String; let iconName: String; let colorHex: String
        let categoryRaw: String
        let scheduleKindRaw: String; let scheduleWeekdaysRaw: Int; let scheduleMonthDaysRaw: Int
        let startDayId: String; let generatedThroughDayId: String
        let isActive: Bool; let createdAt: Date; let sortOrder: Int
        let dayLogs: [HabitDayLog]?
    }
    struct HabitDayLog: Codable {
        let id: UUID; let dayId: String; let statusRaw: String
        let createdAt: Date; let completedAt: Date?
    }
```

   `TaskRecord` 追加 `let habitId: UUID?`。
4. `makePayload`：抓 habits（含 dayLogs）；`taskRecord(_:)` 追加 `habitId: task.habit?.id`；两处 `Inspection` 构造点追加 `habitCount: (payload.habits ?? []).count`。
5. `validate`：habit ID 唯一 + `task.habitId ⊆ habitIds`。
6. `deleteAllData`：追加 `HabitModel`、`HabitDayRecord`。
7. `insert`：先插 habits（含 dayLogs，`record.habit = habit`），任务循环里 `if let habitId = record.habitId { item.habit = habits[habitId] }`。
8. 测试：`test_dataArchiveRoundTripsHabitsRecordsAndTaskLinks`（断言 dayLogs 往返 + 任务关联）、`test_dataArchiveImportsLegacySchema7PayloadWithoutHabits`（沿用 v2 的 `downgradeArchiveToSchema7` 辅助：去掉 `habits` 键与 `task.habitId`、重算 SHA256、schemaVersion=7）。
9. Commit：`feat: extend data archive with habits and day records for schema 8`

### Task 7：来源徽章
**Files**：`Shared/Components/TaskRowView.swift`、`Shared/Components/TaskCard.swift`、`Features/Today/DraftEditorView.swift`、`Features/Today/TodayView.swift`、`Features/Today/FrozenZoneView.swift`

1. `TaskRowView.swift` 紧跟 `TaskProjectOriginBadge` 新增 `TaskHabitOriginBadge`（v2 Task 5 Step 1 代码原样；`accessibilityIdentifier("taskHabitOriginBadge")`）。
2. `TaskRowView` / `TaskCard` 各加 `showsHabitOrigin: Bool = false` 参数与渲染（紧随项目徽章，同一视觉槽位）。
3. 调用点接线（规则：凡 `showsProjectOrigin: true` 处同传 `showsHabitOrigin: true`）：DraftEditorView（:195-200）、TodayView Focus 大卡（:499-505 内联暗底徽章）、FrozenZoneView + TodayView 调用点（:625-634）；Complete 区不显示。
4. 构建 + 模拟器人工核对（Draft 行 / Focus 暗卡 / Frozen 卡可见；无 habit 任务时 UI 与现状逐像素一致）。
5. Commit：`feat: show habit origin badge on draft rows, focus card and frozen cards`

### Task 8：Hub tile + 习惯管理页
**Files**：`Features/Extensions/ExtensionsHubView.swift`、新建 `Features/Extensions/HabitsFullView.swift`、pbxproj

1. `ExtensionsHubView`：仿 `SuspendedTasksModulePreview`（:94-121）新增文件内私有 `HabitsModulePreview`：`NavigationLink { HabitsFullView(viewModel: viewModel) }`（viewModel 用既有 `ExtensionsViewModel` 旁的 `HabitViewModel`，在 `ExtensionsHubView` 的 `.task`/`onAppear` 初始化）；tile 显示 `今日进度（completed/scheduled）` + 习惯数；空态 `HubEmptyTile`（`extensions.hub.habits.empty`），accessibilityIdentifier `extensionsHabitsLiveTile` / `extensionsHabitsEmptyTile`；插入位置：`LazyVGrid` 第 3 格（MindStamps、Suspended 之后；Projects 全宽行之前）。
2. `HabitsFullView`：`ScrollView` + 顶部单张 `WeekCard`（今日完成进度）；`进行中` 分组：行为原生 List 风格行（图标圆 + 名称 + `scheduleSummary` + 连续天数 chip + 今日状态 chip），`NavigationLink` → `HabitDetailView`；`已停用` 分组（`habits.archived.section`）；空态（`habits.empty.*`）；`.onAppear` / `sheet(onDismiss:)` / `.refreshOnStateTransitions(using: appState) { viewModel.refresh() }`；toolbar `+` → `HabitEditorSheet`。
3. 视觉约束：少卡片、单焦点、无渐变遮丑（与近期视觉基调一致）。
4. 构建 + 截图核对。
5. Commit：`feat: add habits module tile and management screen`

### Task 9：习惯详情页（统计 / 时间线）
**Files**：新建 `Features/Extensions/HabitDetailView.swift`、pbxproj

结构（参照 `ProjectDetailView` 分段；决策 D4）：
1. identity：图标 + 名称 + 分类 + `scheduleSummary` + 开始日期 + 今日状态 chip。
2. 统计卡：当前连续 / 最长连续 / 完成率 / 累计完成（`contentTransition(.numericText())`）。
3. **时间线（历史主视图，取代月历网格）**：`LazyVStack` 驱动 `HabitStatisticsCalculator.timeline(for:today:)`；按月分组（组头 "2026 年 9 月"）；节点行 = 状态圆点 + 日期（"9月18日 周四"）+ 状态文案：`已完成 08:12` / `中断`（警示色空心，用户要求显式标注）/ `待完成`（描边，仅今天）/ `未记录`（淡显）；非计划日不出现；脚注 `habit.timeline.footer`；无节点时（开始日在未来）显示 `habit.timeline.starts_on %@`。
4. 操作：`habit.detail.add_today`（结果提示映射 `HabitAssignOutcome`）、编辑（`HabitEditorSheet`）、停用/恢复、删除（`confirmationDialog` + `habit.detail.delete_confirm`）。
5. `.onAppear { viewModel.refresh() }`、`sheet(onDismiss: refresh)`、`.refreshOnStateTransitions(using: appState) { viewModel.refresh() }`。
6. 视觉约束：少卡片、单焦点；时间线不加边框容器（直接列表流）；「中断」与「未记录」仅靠颜色 + 文案区分，不堆图标、不用 emoji。
7. 空/异常兜底：习惯已删除 → 返回上一页。
8. 构建 + 截图核对（含"中断日与未记录日肉眼可区分"确认）；Commit：`feat: add habit detail screen with statistics and full history timeline`

### Task 10：习惯编辑表单
**Files**：新建 `Features/Extensions/HabitEditorSheet.swift`、pbxproj

1. 字段：名称（TextField）、图标（16 个预置 SF Symbols 网格）、颜色（8 色 swatch）、分类（Menu Picker）、**重复方式（Segmented Picker：按星期 / 按月 / 不重复，`HabitScheduleKind`）**：
   - 按星期：7 个 ISO weekday 圆形多选 + 快捷预设（每天 / 工作日 / 周末）；
   - 按月：1–31 数字网格（7 列、多选）；
   - 不重复：无附加选择，仅开始日一次。
   开始日期（DatePicker，`in: Date()...`，默认今天）。
2. 支持 create/edit 两态（`habit.editor.create_title` / `edit_title`）；校验与错误：`HabitError.nameEmpty` / `.scheduleEmpty`（按星期/按月至少选一天；不重复无需选）→ 行内红字；保存调 `HabitViewModel` 对应方法（编辑态提示计划变更会重估今日）。
3. footer：`habit.editor.footer`（讲清"当天首次打开时加入草稿区；已开始或已过截止时间不写入"）+ 按月态追加 `habit.editor.monthly_footer`（所选日在当月不存在则该月跳过）。
4. 构建 + 截图核对（三种重复方式各一张）；Commit：`feat: add habit editor sheet with weekly, monthly and one-off schedules`

### Task 11：推迟守卫 + 协调器触发
**Files**：`Models/WeekyiiError.swift`、`Services/TaskPostponeService.swift`、`App/WeekyiiApp.swift`、`Tests/ModelTests.swift`、`Tests/StateMachineTests.swift`

1. `WeekyiiError` 追加 `case cannotPostponeHabitTask`（文案"习惯任务属于当天，不能后移。"，与既有 postpone 错误同风格硬编码中文，`:42-49`）。
2. `TaskPostponeService.validateSourceTask`（:335-349）在 zone 校验前追加：`guard task.habit == nil else { throw WeekyiiError.cannotPostponeHabitTask }`——该方法被 `preview`（:254，**确认后移之前**）与 `execute`（:292）共同调用，一处守卫两处生效。
3. `AppHealthCoordinator.reconcile` 插入 §5.4 的 3 行（**无需协议改动**：`StateMachine.swift:4-14` 保持原样，`TestAppState` 不动）。
4. 测试：`test_habitTaskCannotBePostponed`（preview 与 execute 均抛 `cannotPostponeHabitTask`；同日普通任务不受影响）；`test_reconcileMaterializesHabitForToday`（建习惯 → 触发 reconcile → 今日任务出现 + 记录 pending；再 reconcile → 不重复）。既有 StateMachineTests 零回归。
5. Commit ①：`fix: block postponing habit tasks`；Commit ②：`feat: materialize habits during app health reconcile`

### Task 12：本地化落地
**Files**：`Resources/Localizable.xcstrings`

1. 构建一次让 Xcode 提取全部 `String(localized:)` 新 key（空条目自动出现，属正常产物）。
2. 按 §6 表补 en 值（zh 即 defaultValue，不重复填写；注意 `%lld`/`%@` 占位符原样保留）。
3. 抽查 en/zh 截图（编辑器 + 详情 + Hub）。
Commit：`i18n: add habit tracker localization entries`

### Task 13：全量验证
1. `xcodebuild ... test` 全量（先与用户确认）：
   - 新增测试（§9）全部通过；
   - 既有 `test_publishedV6FixtureMigratesToV7`、preflight、archive、StateMachine、UI 基线（20 例）零回归。
2. 归档专项：导出 → 导入（新→新）、schema 7 旧档 → 导入（旧→新）。
3. 徽章范围核对（Draft/Focus/Frozen 有、Complete 无）。
4. 未来不变量专项：全新安装 → 建习惯 → 不打开其它日期 → 断言 store 中不存在 `dayId > 今天` 的 DayModel / 任务（可写一个临时诊断或走单元测试）。

### Task 14：人工验收（必须逐条勾选）
- [ ] 新建"每天"习惯 → 今日草稿区立即出现任务（徽章「习惯 · 名称」）。
- [ ] 今日已 start 后再建习惯 → 今日不注入；次日启动 App 自动出现在草稿区。
- [ ] 完成习惯任务（经 doneFocus）→ 详情页时间线该日变「已完成」+ 连续 +1。
- [ ] 不完成任务等到次日 → 时间线该日变为「中断」，连续中断。
- [ ] 当天删除习惯任务 → 不复活；「加入今日」可补回。
- [ ] 编辑重复计划（加/减今天）→ 今日按新计划重估；已存在任务不重复。
- [ ] 停用 → 不再生成；恢复 → 今日立即生成（若匹配）。
- [ ] 删除习惯 → 未开始日任务移除、已开始日仅解除关联；记录/统计消失。
- [ ] 时间线自开始日起逐日覆盖计划日（倒序、按月分组、不截断）；「中断」日显式标注，「未记录」日淡显，二者肉眼可区分。
- [ ] 连续/完成率与时间线逐日状态手工核对一致。
- [ ] 推迟一个习惯任务 → **确认后移之前**即被拒（"习惯任务属于当天，不能后移。"）；同日普通任务照常可后移。
- [ ] 按月习惯（如选 1、15 日）→ 仅这两天生成；2 月缺 29/30/31 日时该月自动跳过。
- [ ] 不重复习惯 → 仅在开始日生成一次；次日起不再生成，今日状态显示"今日无需"。
- [ ] 旧版本数据升级（真机/模拟器已装 V7 数据）启动正常（preflight-v8 快照生成）。

### Task 15：CloudKit 发布
按 §4.5 顺序执行；双设备验证习惯 + 记录 + 徽章同步。
Commit/发布说明：`release: habit tracker (schema 8)`

---

## §9 测试矩阵

| 测试 | 位置 | 覆盖 |
|---|---|---|
| `test_publishedV7FixtureMigratesToV8` | ModelTests | 迁移链（V7→V8 全量实体） |
| `test_habitRelationshipRoundTripsThroughContext` | ModelTests | habit↔task / habit↔record 双向关系 |
| `test_habitWeekdayBitmaskEncodesISOWeekdays` | ModelTests | 位掩码 |
| `test_habitSyncCreatesOnlyTodayAndIsIdempotent` | ModelTests | 仅今日 / 幂等 / 无未来写入 |
| `test_habitSyncSkipsLockedDayAndAdvancesWatermark` | ModelTests | 锁定日 / 水位线 / 删除不复活前提 |
| `test_habitSyncSkipsWhenPastKillTime` | ModelTests | kill time 守卫 |
| `test_habitSyncSkipsNotScheduledAndFutureStart` | ModelTests | 计划/生效日守卫 |
| `test_habitMonthlyScheduleOccurrenceAndSkipsMissingDates` | ModelTests | 按月计划：命中日生成 / 缺日月份跳过 / 时间线无该月节点 |
| `test_habitOneOffScheduleMaterializesOnce` | ModelTests | 不重复：仅开始日生成一次 |
| `test_habitTaskCannotBePostponed` | ModelTests | 推迟守卫：preview（确认前）与 execute 均拒；普通任务不受影响 |
| `test_habitSyncSweepsPendingRecordsToMissed` | ModelTests | 补记 sweep（D1/D2 口径） |
| `test_habitStageCompletionUpsertsCompletedRecord` | ModelTests | 完成钩子暂存（upsert） |
| `test_habitAssignTodayBypassesWatermarkAndRejectsLocked` | ModelTests | 手动加入语义 |
| `test_habitStatisticsStreakRateAndDedupe` | ModelTests | 统计口径 / 去重 |
| `test_habitTimelineAssemblesScheduledDaysWithStates` | ModelTests | 时间线：计划日过滤 / 四态映射（含中断与未记录区分）/ 倒序 / completedAt 携带 |
| `test_habitDeleteRemovesDraftTasksAndKeepsStartedDayTasks` | ModelTests | 删除语义 |
| `test_habitArchiveStopsGenerationAndRestoreResumesToday` | ModelTests | 停用/恢复 |
| `test_habitUpdateRewindsWatermarkWhenPlanChanges` | ModelTests | 计划回拨 |
| `test_habitCreateMaterializesTodayWhenScheduled` | ModelTests | VM 创建即同步 |
| `test_dataArchiveRoundTripsHabitsRecordsAndTaskLinks` | ModelTests | 归档新→新 |
| `test_dataArchiveImportsLegacySchema7PayloadWithoutHabits` | ModelTests | 归档旧→新 |
| `test_reconcileMaterializesHabitForToday` | StateMachineTests | 协调器触发 |
| doneFocus 钩子测试 | StateMachineTests | 完成路径（含队列非首位） |
| 既有全量 | 全部 | 零回归 |

---

## §10 验收清单（Definition of Done）

- [ ] `WeekyiiSchemaV7` 已冻结（9 内嵌副本）；`WeekyiiSchemaV8` 含 11 模型；lightweight 阶段；§4.4 锚点全部更新；真机旧数据升级通过。
- [ ] 习惯任务**仅在当天**生成；仓库中不存在自动写入的未来日/周（Task 13 专项）。
- [ ] 记录三态 + sweep 补记工作正常；详情页时间线 / 统计与手工核对一致（「中断」与「未记录」可区分）。
- [ ] 三种重复方式（按星期 / 按月 / 不重复）均按计划生成；按月缺日跳过；习惯任务在确认后移前被拒。
- [ ] 徽章与 Project 徽章逐点对齐（Draft/Focus/Frozen；Complete 不显示）。
- [ ] 归档（含旧档）双向通过；CloudKit 生产 schema 部署 + 双设备同步通过。
- [ ] 新增测试全部通过，既有测试（含 UI 20 例基线）零回归。
- [ ] 中英文文案完整；不影响无习惯用户的任何既有行为（徽章默认 false）。

---

## §11 风险与回滚

| 风险 | 触发信号 | 缓解 / 回滚 |
|---|---|---|
| 冻结副本与线上 V7 字段级偏差 | 旧数据设备启动失败 / "Duplicate version checksums" | 对照 §4.3 逐字段修正；必要时合并 Task 0+1 一次落地；不推进 Task 1 |
| V8≡V7 窗口期运行 App | 异常崩溃 | Task 0/1 连续完成之间禁止运行 |
| CloudKit 未部署生产 schema | 线上同步报错 | Task 15 顺序（先部署后发版）；补部署即可 |
| 60 秒 tick 高频 sync 造成写入 | 电量/性能隐患 | `needsSave` 仅在真实变更时为 true；水位线保证同日只处理一次 |
| 计划回拨致今天已删任务复活 | 用户反馈重复 | §2.1 声明为设计取舍（用户重新确认计划）；必要时只对"新增 weekday"回拨 |
| 多设备重复记录 | 统计偏差 | 读取按 dayId 去重（completed 优先） |
| 整体回滚 | 上线后严重问题 | 回滚代码到 Task 0 之前；store 已迁移到 V8 → 不可逆，用 preflight-v8 快照恢复（`BackupRecoveryService`） |

---

## §12 文件变更总表

| Action | 文件 | Task |
|---|---|---|
| Modify | `App/WeekyiiPersistence.swift` | 0（冻结 V7 + V8 + 锚点）、1（V8 加 2 模型） |
| Create | `Models/HabitModel.swift` | 1 |
| Create | `Models/HabitDayRecord.swift` | 1 |
| Modify | `Models/TaskItem.swift` | 1 |
| Modify | `Models/WeekyiiError.swift` | 11 |
| Modify | `Services/TaskPostponeService.swift` | 11 |
| Modify | `Tests/StateMachineTests.swift` | 1（容器）、11（测试） |
| Modify | `Shared/Extensions/Date+Weekyii.swift` | 2 |
| Create | `Services/HabitTaskMaterializer.swift` | 2 |
| Create | `Services/HabitStatistics.swift` | 3 |
| Modify | `Features/Today/TodayViewModel.swift` | 4 |
| Create | `Features/Extensions/HabitViewModel.swift` | 5 |
| Modify | `Services/DataArchiveService.swift` | 6 |
| Modify | `Shared/Components/TaskRowView.swift` | 7 |
| Modify | `Shared/Components/TaskCard.swift` | 7 |
| Modify | `Features/Today/DraftEditorView.swift` | 7 |
| Modify | `Features/Today/TodayView.swift` | 7 |
| Modify | `Features/Today/FrozenZoneView.swift` | 7 |
| Modify | `Features/Extensions/ExtensionsHubView.swift` | 8 |
| Create | `Features/Extensions/HabitsFullView.swift` | 8 |
| Create | `Features/Extensions/HabitDetailView.swift` | 9 |
| Create | `Features/Extensions/HabitEditorSheet.swift` | 10 |
| Modify | `App/WeekyiiApp.swift` | 11 |
| Modify | `Resources/Localizable.xcstrings` | 12 |
| Modify | `Tests/ModelTests.swift` | 0/1/2/3/5/6/11 |
| Modify | `Weekyii.xcodeproj/project.pbxproj` | 1/2/3/5/8/9/10 |

**总计**：8 个新文件、16 个修改文件、17 个提交（Task 0–15；Task 11 含 2 个提交）。
