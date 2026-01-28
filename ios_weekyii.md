# Weekyii iOS 开发规范

> 本文档定义 Weekyii iOS App 的完整开发规范，采用 **SwiftUI + SwiftData + iOS 17+** 技术栈。
> 
> 核心理念保持不变：以周为粒度、单任务专注、承诺不可回滚、过期即遗忘。

---

## 1. 技术栈概览

| 层次 | 技术选型 | 说明 |
|------|---------|------|
| UI 框架 | SwiftUI | 声明式 UI |
| 数据持久化 | SwiftData | iOS 17+ 原生 ORM |
| 状态管理 | @Observable | iOS 17+ Observation 框架 |
| 最低版本 | iOS 17.0 | 充分利用最新 API |
| 架构模式 | MVVM + Services | Feature-based 组织 |

> ⚠️ **数据源唯一性**：SwiftData 是唯一运行时数据源；不使用文件系统（如 `.md` 文件）作为持久化存储。

### 未来扩展预留
- **iCloud 同步**：SwiftData 原生支持，v1 不启用
- **Widget**：Today Extension，v1 不实现
- **Apple Watch**：独立 Target，v1 不实现

---

## 2. 项目结构

```
Weekyii/
├── App/
│   ├── WeekyiiApp.swift              # @main 入口，配置 ModelContainer
│   ├── AppState.swift                # 全局状态（@Observable）
│   └── ContentView.swift             # Tab 导航根视图
│
├── Models/
│   ├── WeekModel.swift               # @Model 周数据
│   ├── DayModel.swift                # @Model 日数据
│   ├── TaskItem.swift                # @Model 任务项
│   └── Enums/
│       ├── DayStatus.swift           # draft/execute/completed/expired/empty
│       ├── WeekStatus.swift          # pending/present/past
│       └── TaskType.swift            # regular/ddl/leisure
│
├── Services/
│   ├── TimeProvider.swift            # 时间服务（可 mock）
│   ├── StateMachine.swift            # 状态转换引擎
│   ├── NotificationService.swift     # 本地通知
│   └── WeekCalculator.swift          # 周计算工具
│
├── Features/
│   ├── Today/
│   │   ├── TodayView.swift           # 首页主视图
│   │   ├── TodayViewModel.swift      # 业务逻辑
│   │   ├── FocusZoneView.swift       # 专注区组件
│   │   ├── FrozenZoneView.swift      # 冻结区组件
│   │   ├── CompleteZoneView.swift    # 完成区组件
│   │   └── DraftEditorView.swift     # 草稿编辑器
│   │
│   ├── Week/
│   │   ├── WeekOverviewView.swift    # 本周 7 天概览
│   │   ├── WeekViewModel.swift
│   │   └── DayCardView.swift         # 单日卡片
│   │
│   ├── Pending/
│   │   ├── PendingView.swift         # 未来周列表
│   │   ├── PendingViewModel.swift
│   │   ├── MonthPickerView.swift     # 月份选择器
│   │   └── CreateWeekSheet.swift     # 创建周 Sheet
│   │
│   └── Past/
│       ├── PastView.swift            # 历史记录
│       ├── PastViewModel.swift
│       └── PastDayDetailView.swift   # 历史日详情
│
├── Shared/
│   ├── Components/
│   │   ├── StatusBadge.swift         # 状态标签
│   │   ├── TaskRowView.swift         # 任务行组件
│   │   ├── KillTimeEditor.swift      # kill_time 编辑器
│   │   └── EmptyStateView.swift      # 空状态占位
│   │
│   └── Extensions/
│       ├── Date+Weekyii.swift        # 日期扩展
│       ├── Calendar+Week.swift       # 周计算扩展
│       └── View+Modifiers.swift      # 视图修饰符
│
├── Resources/
│   ├── Assets.xcassets               # 图片资源
│   ├── Localizable.xcstrings         # 多语言
│   └── Info.plist
│
└── Tests/
    ├── StateMachineTests.swift
    ├── WeekCalculatorTests.swift
    └── ModelTests.swift
```

---

## 3. 数据模型（SwiftData）

### 3.1 WeekModel

```swift
import SwiftData

@Model
final class WeekModel {
    // 主键：2026-W05 格式
    @Attribute(.unique) var weekId: String
    
    // 周范围
    var startDate: Date  // 周一
    var endDate: Date    // 周日
    
    // 状态
    var status: WeekStatus  // pending/present/past
    
    // 关联的天（一对多）
    @Relationship(deleteRule: .cascade, inverse: \DayModel.week)
    var days: [DayModel] = []
    
    // 统计（Past 状态时填充）
    var completedTasksCount: Int = 0
    var expiredTasksCount: Int = 0
    var totalStartedDays: Int = 0
    
    // 初始化器
    init(weekId: String, startDate: Date, endDate: Date, status: WeekStatus = .pending) {
        self.weekId = weekId
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
    }
    
    // 计算属性（统一使用 ISO 8601 日历）
    var weekNumber: Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: startDate)
    }
}
```

### 3.2 DayModel

```swift
@Model
final class DayModel {
    // 主键：2026-01-29 格式
    @Attribute(.unique) var dayId: String
    
    var date: Date
    var dayOfWeek: String  // Mon/Tue/...
    var status: DayStatus  // empty/draft/execute/completed/expired
    
    // kill_time（默认 20:00）
    var killTimeHour: Int = 20
    var killTimeMinute: Int = 0
    
    // 时间戳
    var initiatedAt: Date?
    var closedAt: Date?
    
    // 关联
    var week: WeekModel?
    
    @Relationship(deleteRule: .cascade, inverse: \TaskItem.day)
    var tasks: [TaskItem] = []
    
    // 过期统计（expired 状态时使用）
    var expiredCount: Int = 0
    
    // 初始化器
    init(dayId: String, date: Date, status: DayStatus = .empty) {
        self.dayId = dayId
        self.date = date
        self.dayOfWeek = date.dayOfWeekShort
        self.status = status
    }
    
    // 计算属性
    var killTime: DateComponents {
        DateComponents(hour: killTimeHour, minute: killTimeMinute)
    }
    
    /// 按 order 排序的草稿任务（用于 start 时确定顺序）
    var sortedDraftTasks: [TaskItem] {
        tasks.filter { $0.zone == .draft }.sorted { $0.order < $1.order }
    }
    
    /// 专注区任务（强约束：最多只能有一个）
    /// 如果发现多个，取 order 最小的（防御性编程）
    var focusTask: TaskItem? {
        tasks.filter { $0.zone == .focus }.min { $0.order < $1.order }
    }
    
    var frozenTasks: [TaskItem] {
        tasks.filter { $0.zone == .frozen }.sorted { $0.order < $1.order }
    }
    
    var completedTasks: [TaskItem] {
        tasks.filter { $0.zone == .complete }.sorted { $0.completedOrder < $1.completedOrder }
    }
    
    /// 验证 Focus Zone 唯一性（调试/测试用）
    var hasSingleFocus: Bool {
        tasks.filter { $0.zone == .focus }.count <= 1
    }
}
```

### 3.3 TaskItem

```swift
@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID = UUID()
    
    // 任务内容
    var title: String
    var taskType: TaskType  // regular/ddl/leisure
    
    // 序号（T01, T02...）
    var order: Int
    var taskNumber: String { String(format: "T%02d", order) }
    
    // 区域
    var zone: TaskZone  // draft/focus/frozen/complete
    
    // 时间戳
    var startedAt: Date?
    var endedAt: Date?
    
    // 完成顺序（用于 Complete Zone 排序）
    var completedOrder: Int = 0
    
    // 关联
    var day: DayModel?
    
    // 子任务（可选扩展）
    var subtasks: [String] = []
    
    // 初始化器
    init(title: String, taskType: TaskType = .regular, order: Int, zone: TaskZone = .draft) {
        self.title = title
        self.taskType = taskType
        self.order = order
        self.zone = zone
    }
}
```

### 3.4 枚举定义

```swift
// DayStatus.swift
enum DayStatus: String, Codable {
    case empty      // 未创建任务
    case draft      // 草稿，可编辑
    case execute    // 执行中，已锁定
    case completed  // 全部完成
    case expired    // 已过期
}

// WeekStatus.swift
enum WeekStatus: String, Codable {
    case pending    // 未来周
    case present    // 当前周
    case past       // 过去周
}

// TaskType.swift
enum TaskType: String, Codable, CaseIterable {
    case regular    // 常规任务
    case ddl        // 截止日期任务
    case leisure    // 休闲任务
    
    var displayName: String {
        switch self {
        case .regular: return "常规"
        case .ddl: return "DDL"
        case .leisure: return "休闲"
        }
    }
    
    var iconName: String {
        switch self {
        case .regular: return "checkmark.circle"
        case .ddl: return "exclamationmark.triangle"
        case .leisure: return "leaf"
        }
    }
}

// TaskZone.swift
enum TaskZone: String, Codable {
    case draft      // 草稿区
    case focus      // 专注区
    case frozen     // 冻结区
    case complete   // 完成区
}
```

---

## 4. 服务层设计

### 4.1 TimeProvider（可测试的时间服务）

```swift
protocol TimeProviding {
    var now: Date { get }
    var today: Date { get }
    var currentWeekId: String { get }
}

@Observable
final class TimeProvider: TimeProviding {
    /// 统一使用 ISO 8601 日历（周一为周首）
    private let iso8601Calendar = Calendar(identifier: .iso8601)
    
    var now: Date { Date() }
    
    var today: Date {
        iso8601Calendar.startOfDay(for: now)
    }
    
    var currentWeekId: String {
        let week = iso8601Calendar.component(.weekOfYear, from: now)
        let year = iso8601Calendar.component(.yearForWeekOfYear, from: now)
        return String(format: "%04d-W%02d", year, week)
    }
}

// 测试用 Mock
final class MockTimeProvider: TimeProviding {
    private let iso8601Calendar = Calendar(identifier: .iso8601)
    var mockDate: Date
    
    init(mockDate: Date) {
        self.mockDate = mockDate
    }
    
    var now: Date { mockDate }
    var today: Date { iso8601Calendar.startOfDay(for: mockDate) }
    var currentWeekId: String {
        let week = iso8601Calendar.component(.weekOfYear, from: mockDate)
        let year = iso8601Calendar.component(.yearForWeekOfYear, from: mockDate)
        return String(format: "%04d-W%02d", year, week)
    }
}
```

### 4.2 StateMachine（状态转换引擎）

```swift
@Observable
final class StateMachine {
    private let modelContext: ModelContext
    private let timeProvider: TimeProviding
    private let notificationService: NotificationService
    
    init(modelContext: ModelContext, 
         timeProvider: TimeProviding = TimeProvider(),
         notificationService: NotificationService) {
        self.modelContext = modelContext
        self.timeProvider = timeProvider
        self.notificationService = notificationService
    }
    
    /// 每次 App 进入前台或执行操作前调用
    func processStateTransitions() {
        processCrossDay()
        processCrossWeek()
        processKillTime()
    }
    
    // MARK: - 跨日处理
    private func processCrossDay() {
        // 1. 获取昨日
        // 2. 如果昨日 status == .execute 且未完成 → 标记 expired
        // 3. 如果昨日 status == .draft 且未启动 → 标记 expired (expiredCount = 0)
    }
    
    // MARK: - 跨周处理
    private func processCrossWeek() {
        // 1. 检查 Present 周是否仍是当前周
        // 2. 如果不是 → 移入 Past
        // 3. 检查 Pending 中是否有新的当前周 → 移入 Present
        // 4. 如果没有 → 创建空的当前周
    }
    
    // MARK: - Kill Time 处理
    private func processKillTime() {
        // 如果当前时间 > 今日 kill_time 且 status == .execute
        // → 立即过期，清空 Focus/Frozen 详情，记录 expiredCount
    }
}
```

### 4.3 AppState（全局状态）

```swift
@Observable
final class AppState {
    var daysStartedCount: Int = 0
    var systemStartDate: Date?
    
    /// 上次状态机处理的日期（仅日期部分，不含时间）
    /// 用于判断是否需要跨日处理
    var lastProcessedDate: Date?
    
    /// 上次状态机运行的完整时间戳（用于日志/调试）
    var lastRolloverAt: Date?
    
    // 从 UserDefaults 加载/保存
    private let defaults = UserDefaults.standard
    
    init() {
        load()
    }
    
    func load() {
        daysStartedCount = defaults.integer(forKey: "daysStartedCount")
        systemStartDate = defaults.object(forKey: "systemStartDate") as? Date
        lastProcessedDate = defaults.object(forKey: "lastProcessedDate") as? Date
        lastRolloverAt = defaults.object(forKey: "lastRolloverAt") as? Date
    }
    
    func save() {
        defaults.set(daysStartedCount, forKey: "daysStartedCount")
        defaults.set(systemStartDate, forKey: "systemStartDate")
        defaults.set(lastProcessedDate, forKey: "lastProcessedDate")
        defaults.set(lastRolloverAt, forKey: "lastRolloverAt")
    }
    
    func incrementDaysStarted() {
        daysStartedCount += 1
        save()
    }
    
    /// 由 StateMachine 在每次处理完成后调用
    func markProcessed(at date: Date) {
        let calendar = Calendar(identifier: .iso8601)
        lastProcessedDate = calendar.startOfDay(for: date)
        lastRolloverAt = date
        save()
    }
}
```

#### 4.3.1 为何使用 UserDefaults 而非 SwiftData

| 字段 | 存储位置 | 原因 |
|------|---------|------|
| `daysStartedCount` | UserDefaults | 统计类全局标量，非关系模型，不影响核心流程 |
| `lastProcessedDate` | UserDefaults | 状态机运行时状态，非关系模型 |
| `systemStartDate` | UserDefaults | 一次性记录，不需要关系模型 |

**备份/迁移处理**：
- SwiftData 负责业务数据（Week/Day/Task）
- UserDefaults 的 `daysStartedCount` 仅用于统计显示，丢失不影响核心功能
- 如需完整备份，导出时应包含 UserDefaults 中的 `daysStartedCount`

---

## 5. 状态机规则（核心业务逻辑）

> 以下规则必须严格实现，保持与 Weekyii 理念一致。

### 5.1 执行时机

状态机在以下时机自动执行：
1. **App 启动时**（`WeekyiiApp.init`）
2. **App 进入前台时**（`scenePhase == .active`）
3. **前台定时器触发**（每分钟检查 kill_time，**仅限 App 在前台时**）

> ⚠️ **iOS 限制**：后台无法持续运行定时器。kill_time 过期检查仅在 App 前台或下次唤醒时触发。
> 如需精确到期，依赖本地通知提醒用户打开 App。

### 5.2 跨日规则

```
IF 系统日期（仅日期部分）> appState.lastProcessedDate:
    FOR 每个日期在 (lastProcessedDate, 今日) 区间内的 day:
        IF day.status == .execute AND day 未完成:
            → day.status = .expired
            → day.expiredCount = Focus + Frozen 中的任务数
            → 清空 Focus/Frozen 任务详情
            → 保留 Complete 任务详情
        
        IF day.status == .draft:
            → day.status = .expired
            → day.expiredCount = 0
            → 清空 Draft 任务详情
    
    // 处理完成后更新状态
    appState.markProcessed(at: now)
```

### 5.3 跨周规则

```
IF 当前周 ID != Present 周的 weekId:
    // 旧周移入 Past，并统计汇总
    presentWeek.status = .past
    presentWeek.completedTasksCount = 汇总本周所有天的 completedTasks.count
    presentWeek.expiredTasksCount = 汇总本周所有天的 expiredCount
    presentWeek.totalStartedDays = 本周 status 曾为 execute/completed/expired 的天数
    
    // 新周处理
    IF Pending 中存在当前周:
        pendingWeek.status = .present
        移动到 Present
    ELSE:
        创建空的当前周（7 天 empty 状态）
```

### 5.4 Kill Time 规则

```
// 仅对 execute 状态生效；completed/expired 不处理
IF 当前时间 > 今日 kill_time AND today.status == .execute:
    → today.status = .expired
    → 记录 expiredCount = focusTask + frozenTasks.count
    → 清空 Focus/Frozen 详情
    → 保留 Complete 详情
    → 取消当日通知

// kill_time 修改约束
IF 当前时间 >= kill_time:
    → 禁止延长 kill_time（已过时不可延期）
```

#### 5.4.1 iOS 后台限制与边界情况

由于 iOS 后台运行限制，通知与状态转换存在时间差：

| 时间 | 发生什么 |
|------|---------|
| 20:00 (kill_time) | **系统**弹出本地通知 "今日任务流到期提醒" |
| 20:00 ~ 用户打开 App | 状态仍是 `execute`（App 未运行，无法处理） |
| 用户打开 App | StateMachine 检测到超时 → 标记 `expired` |

**设计决策**：
- 通知的作用是**提醒用户打开 App**
- 状态转换**只在 App 运行时发生**
- 这是 iOS 平台限制下的合理行为，不是 bug

**跨日场景**：
| 时间 | 发生什么 |
|------|---------|
| 20:00 (kill_time) | 系统弹出通知，用户未打开 |
| 次日 09:00 | 用户打开 App |
| - | StateMachine 先执行跨日检查 → 昨日 expired |
| - | 再检查今日状态（如有） |

### 5.5 Today Start 规则

```
PRECONDITION:
    - today.status == .draft
    - today.sortedDraftTasks.count > 0

ACTION:
    // 按 order 排序后取任务
    let sortedTasks = today.sortedDraftTasks
    
    - today.status = .execute
    - today.initiatedAt = now
    - sortedTasks[0].zone = .focus, sortedTasks[0].startedAt = now
    - sortedTasks[1...].forEach { $0.zone = .frozen }
    - IF kill_time 未设置: 设置为 20:00
    - IF 今日首次 start: appState.daysStartedCount += 1
    
    // Kill Time 边界检查
    IF 当前时间 >= 今日 kill_time:
        → 立即执行过期流程（status = .expired）
        → 不调度通知
    ELSE:
        → 调度 kill_time 本地通知
```

### 5.6 Today Done 规则

```
PRECONDITION:
    - today.status == .execute
    - today.focusTask != nil

ACTION:
    - focusTask.zone = .complete
    - focusTask.endedAt = now
    - focusTask.completedOrder = completedTasks.count + 1
    
    IF frozenTasks.isNotEmpty:
        - nextTask = frozenTasks.first
        - nextTask.zone = .focus
        - nextTask.startedAt = now
    ELSE:
        - today.status = .completed
        - today.closedAt = now
        - 取消 kill_time 通知
```

---

## 6. 功能模块详细设计

### 6.1 Today 模块

#### TodayView 状态机

```
┌─────────┐   create    ┌─────────┐   start    ┌─────────┐
│  empty  │ ──────────> │  draft  │ ─────────> │ execute │
└─────────┘             └─────────┘            └────┬────┘
                              │                     │
                              │ (跨日未启动)         │ done (全部完成)  |超时
                              v                     v              v
                        ┌─────────┐           ┌───────────┐
                        │ expired │           │ completed │
                        └─────────┘           └───────────┘

注：execute 可以通过“超时”进入 expired，也可以通过“全部完成”进入 completed。
completed 是终态，不会转换为 expired。
```

#### UI 交互约束

| 状态 | 允许操作 | 禁止操作 |
|------|---------|---------|
| empty | 创建任务 | start, done, 修改 kill_time |
| draft | 编辑任务、排序、删除、start、修改 kill_time | done |
| execute | done focus、修改 kill_time | 编辑任务、添加任务 |
| completed | 查看 | 所有编辑操作 |
| expired | 查看 | 所有编辑操作 |

> **kill_time 修改限制**：execute 状态允许修改 kill_time，但当前时间已过 kill_time 时禁止延长。

#### 草稿编辑器功能

- **添加任务**：输入框 + TaskType 选择器
- **删除任务**：滑动删除
- **排序**：拖拽重排（自动重新编号 T01, T02...）
- **编辑**：点击任务进入编辑 Sheet

### 6.2 Week 模块

#### WeekOverviewView

- 显示当前周 7 天的卡片列表
- 每张卡片显示：日期、星期、状态 Badge
- 点击可进入 DayDetailView

#### 日详情编辑规则（统一规则）

| 日期位置 | 状态 | 可否编辑 |
|---------|------|----------|
| 今日 | draft | ✅ 可编辑 |
| 今日 | execute/completed/expired | ❌ 只读 |
| 本周未来日 | empty/draft | ✅ 可编辑（可提前规划） |
| 本周过去日 | 任意 | ❌ 只读 |
| Pending 周 | empty/draft | ✅ 可编辑 |
| Past 周 | 任意 | ❌ 只读 |

> **规则总结**：只有 `empty` 或 `draft` 状态的日期可以编辑，且不能是过去的日期。
>
> **「过去日期」定义**：`date < TimeProvider.today` 即视为过去日期。

#### 视觉规范

```
┌────────────────────────────────┐
│  Week 2026-W05                 │
├────────────────────────────────┤
│  ┌──────┐ ┌──────┐ ┌──────┐   │
│  │ Mon  │ │ Tue  │ │ Wed  │   │
│  │ 01/27│ │ 01/28│ │ 01/29│   │
│  │[完成]│ │[执行]│ │[草稿]│   │
│  └──────┘ └──────┘ └──────┘   │
│  ┌──────┐ ┌──────┐ ...        │
│  │ Thu  │ │ Fri  │            │
│  │ 01/30│ │ 01/31│            │
│  │[空]  │ │[空]  │            │
│  └──────┘ └──────┘            │
└────────────────────────────────┘
```

### 6.3 Pending 模块

#### 功能列表

- 按月份分组显示未来周
- 创建指定周/日的入口
- 点击周进入周详情
- 点击日进入日编辑（仅 empty/draft 可编辑，符合上表规则）

#### 创建周逻辑

```swift
func createWeek(containing date: Date) {
    let weekId = calculateWeekId(for: date)
    
    guard !weekExists(weekId) else { return }
    
    let week = WeekModel(weekId: weekId, ...)
    
    // 创建 7 个空日
    for dayOffset in 0..<7 {
        let dayDate = week.startDate.addingDays(dayOffset)
        let day = DayModel(date: dayDate, status: .empty)
        week.days.append(day)
    }
    
    modelContext.insert(week)
}
```

### 6.4 Past 模块

#### 显示规则

- 按月份分组，展示过去的周
- 周摘要：完成任务数 / 过期任务数
- 日详情：**只显示完成的任务详情**
- 过期任务：**只显示数量，不显示详情**

#### 日详情视图

```
┌────────────────────────────────┐
│  2026-01-27 (Mon)              │
├────────────────────────────────┤
│  ✅ 完成任务: 5                 │
│  ┌────────────────────────────┐│
│  │ T01 [常规] 完成项目报告     ││
│  │ T02 [DDL] 提交申请材料      ││
│  │ ...                         ││
│  └────────────────────────────┘│
│                                │
│  ❌ 过期任务: 2                 │
│  （详情不可查看）               │
└────────────────────────────────┘
```

---

## 7. UI 规范

### 7.1 颜色系统

```swift
extension Color {
    static let weekyiiPrimary = Color("Primary")       // 主色调
    static let weekyiiBackground = Color("Background") // 背景色
    
    // 状态色
    static let statusDraft = Color.gray
    static let statusExecute = Color.blue
    static let statusCompleted = Color.green
    static let statusExpired = Color.red
    static let statusEmpty = Color.secondary
    
    // 任务类型色
    static let taskRegular = Color.primary
    static let taskDDL = Color.orange
    static let taskLeisure = Color.mint
}
```

### 7.2 状态 Badge 组件

```swift
struct StatusBadge: View {
    let status: DayStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .clipShape(Capsule())
    }
}

extension DayStatus {
    var displayName: String {
        switch self {
        case .empty: return "空"
        case .draft: return "草稿"
        case .execute: return "执行中"
        case .completed: return "已完成"
        case .expired: return "已过期"
        }
    }
    
    var color: Color {
        switch self {
        case .empty: return .statusEmpty
        case .draft: return .statusDraft
        case .execute: return .statusExecute
        case .completed: return .statusCompleted
        case .expired: return .statusExpired
        }
    }
}
```

### 7.3 导航结构

```swift
struct ContentView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("今日", systemImage: "sun.max")
                }
            
            WeekOverviewView()
                .tabItem {
                    Label("本周", systemImage: "calendar")
                }
            
            PendingView()
                .tabItem {
                    Label("未来", systemImage: "calendar.badge.plus")
                }
            
            PastView()
                .tabItem {
                    Label("过去", systemImage: "clock.arrow.circlepath")
                }
        }
    }
}
```

### 7.4 动态字体

```swift
// 使用系统动态类型，不硬编码字体大小
Text("任务标题")
    .font(.headline)

Text("副标题")
    .font(.subheadline)

Text("说明文字")
    .font(.caption)
```

---

## 8. 本地通知

### 8.1 通知类型

| 类型 | 触发时机 | 内容 |
|------|---------|------|
| Kill Time 提醒 | kill_time 到达 | "今日任务流即将到期" |
| 每日提醒（可选）| 用户设定时间 | "开始规划今日任务" |

### 8.2 NotificationService

```swift
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }
    
    func scheduleKillTimeNotification(for day: DayModel) {
        let content = UNMutableNotificationContent()
        content.title = "Weekyii"
        content.body = "今日任务流到期提醒"
        content.sound = .default
        
        // 统一使用 ISO 8601 日历
        let calendar = Calendar(identifier: .iso8601)
        var dateComponents = calendar.dateComponents(
            [.year, .month, .day], from: day.date)
        dateComponents.hour = day.killTimeHour
        dateComponents.minute = day.killTimeMinute
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents, repeats: false)
        
        let identifier = "killtime-\(day.dayId)"
        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func cancelKillTimeNotification(for day: DayModel) {
        let identifier = "killtime-\(day.dayId)"
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
```

---

## 9. App 入口配置

### 9.1 WeekyiiApp.swift

```swift
import SwiftUI
import SwiftData

@main
struct WeekyiiApp: App {
    let modelContainer: ModelContainer
    @State private var appState = AppState()
    @State private var stateMachine: StateMachine?
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        do {
            let schema = Schema([WeekModel.self, DayModel.self, TaskItem.self])
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none  // v2 启用: .private("iCloud.com.yourapp.weekyii")
            )
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .modelContainer(modelContainer)
                .onAppear {
                    initializeStateMachine()
                    stateMachine?.processStateTransitions()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        stateMachine?.processStateTransitions()
                    }
                }
        }
    }
    
    private func initializeStateMachine() {
        let context = modelContainer.mainContext
        stateMachine = StateMachine(
            modelContext: context,
            notificationService: .shared
        )
    }
}
```

---

## 10. 测试策略

### 10.1 必须覆盖的测试用例

#### 状态机测试

```swift
final class StateMachineTests: XCTestCase {
    
    func test_crossDay_executeToExpired() {
        // Given: 昨日 status == .execute，有未完成任务
        // When: 跨日处理
        // Then: status == .expired, expiredCount 正确
    }
    
    func test_crossDay_draftToExpired() {
        // Given: 昨日 status == .draft
        // When: 跨日处理
        // Then: status == .expired, expiredCount == 0
    }
    
    func test_crossWeek_presentToPast() {
        // Given: Present 周不再是当前周
        // When: 跨周处理
        // Then: 该周 status == .past
    }
    
    func test_killTime_executeToExpired() {
        // Given: 当前时间 > kill_time, status == .execute
        // When: kill_time 处理
        // Then: status == .expired
    }
}
```

#### 任务操作测试

```swift
final class TodayViewModelTests: XCTestCase {
    
    func test_start_setsStatusToExecute() { }
    func test_start_movesFirstTaskToFocus() { }
    func test_start_incrementsDaysStartedCount() { }
    
    func test_done_movesTaskToComplete() { }
    func test_done_nextTaskBecomeFocus() { }
    func test_done_allCompleted_setsStatusToCompleted() { }
    
    func test_draft_canReorderTasks() { }
    func test_execute_cannotEditTasks() { }
}
```

### 10.2 使用 MockTimeProvider 测试

```swift
func test_with_mockedTime() {
    let mockTime = MockTimeProvider(
        mockDate: Date(timeIntervalSince1970: 1735000000)
    )
    let stateMachine = StateMachine(
        modelContext: context,
        timeProvider: mockTime,
        notificationService: .shared
    )
    // 测试特定时间点的行为
}
```

---

## 11. 编码规范

### 11.1 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| 类型 | UpperCamelCase | `DayModel`, `TaskItem` |
| 变量/方法 | lowerCamelCase | `focusTask`, `processKillTime()` |
| 枚举值 | lowerCamelCase | `.draft`, `.execute` |
| 常量 | lowerCamelCase | `let defaultKillTime = 20` |
| 文件名 | 与主类型同名 | `TodayViewModel.swift` |

### 11.2 SwiftData 规范

- `@Model` 类使用 `final class`
- 主键字段添加 `@Attribute(.unique)`
- 关系使用 `@Relationship` 明确定义
- 删除规则优先使用 `.cascade`

### 11.3 SwiftUI 规范

- View 保持轻量，逻辑放入 ViewModel
- 使用 `@Observable` 而非 `ObservableObject`
- 使用 `@Environment` 注入依赖
- 避免在 View 中直接操作 ModelContext

### 11.4 错误处理

```swift
enum WeekyiiError: LocalizedError {
    case dayNotFound(String)
    case cannotStartEmptyDay
    case cannotEditStartedDay
    case killTimePassed
    
    var errorDescription: String? {
        switch self {
        case .dayNotFound(let id):
            return "找不到日期: \(id)"
        case .cannotStartEmptyDay:
            return "任务列表为空，无法启动"
        case .cannotEditStartedDay:
            return "已启动的任务流无法编辑"
        case .killTimePassed:
            return "当前时间已超过 Kill Time"
        }
    }
}
```

---

## 12. 日期处理工具

### 12.1 Date+Weekyii 扩展

```swift
extension Date {
    /// 格式化为 "2026-01-29"
    var dayId: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: self)
    }
    
    /// 格式化为 "2026-W05"
    var weekId: String {
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: self)
        let year = calendar.component(.yearForWeekOfYear, from: self)
        return String(format: "%04d-W%02d", year, week)
    }
    
    /// 星期几 "Mon"/"Tue"/...
    var dayOfWeekShort: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: self)
    }
    
    /// 当天开始（00:00:00）统一使用 ISO 8601
    var startOfDay: Date {
        Calendar(identifier: .iso8601).startOfDay(for: self)
    }
    
    /// 所在周的周一
    var startOfWeek: Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2 // Monday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components)!
    }
    
    /// 添加天数（统一使用 ISO 8601）
    func addingDays(_ days: Int) -> Date {
        Calendar(identifier: .iso8601).date(byAdding: .day, value: days, to: self)!
    }
}
```

### 12.2 Calendar+Week 扩展

```swift
extension Calendar {
    /// 获取某周包含的所有日期
    func datesInWeek(of date: Date) -> [Date] {
        let startOfWeek = date.startOfWeek
        return (0..<7).map { startOfWeek.addingDays($0) }
    }
    
    /// 判断两个日期是否在同一周
    func isDate(_ date1: Date, inSameWeekAs date2: Date) -> Bool {
        date1.weekId == date2.weekId
    }
}
```

---

## 13. 开发检查清单

### 13.1 核心功能

- [ ] 状态机：跨日处理
- [ ] 状态机：跨周处理
- [ ] 状态机：Kill Time 处理
- [ ] Today：创建任务
- [ ] Today：编辑/排序任务（Draft）
- [ ] Today：Start 启动
- [ ] Today：Done Focus 完成
- [ ] Today：修改 Kill Time
- [ ] Week：本周 7 天概览
- [ ] Pending：创建未来周/日
- [ ] Pending：月份导航
- [ ] Past：历史周/日查看
- [ ] Past：过期任务只显示数量

### 13.2 边界条件

- [ ] 启动时 Draft 为空 → 禁止 Start
- [ ] Execute 状态 → 禁止编辑任务
- [ ] Completed/Expired → 只读
- [ ] Kill Time 已过 → 禁止延长
- [ ] 非今日 → 禁止 Start

### 13.3 通知

- [ ] 请求通知权限
- [ ] Start 时调度通知
- [ ] Kill Time 修改时重新调度
- [ ] Completed/Expired 时取消通知

### 13.4 测试

- [ ] StateMachine 单元测试
- [ ] ViewModel 单元测试
- [ ] 使用 MockTimeProvider 测试时间相关逻辑

---

## 14. 版本规划

### v1.0 (MVP)
- [ ] 核心 Today 功能
- [ ] Week 概览
- [ ] Pending 创建
- [ ] Past 查看
- [ ] 本地通知

### v1.1
- [ ] 数据导出（JSON）
- [ ] 深色模式优化

### v2.0
- [ ] iCloud 同步
- [ ] Widget 支持
- [ ] Apple Watch App
