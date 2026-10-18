# Suspended Tasks Design

> 预案阶段，不含实现。

## Goal
在扩展页新增一个“悬置任务”模块，用来收纳尚未承诺到某一天、但需要在限定倒计时内再次决策的任务。用户可创建、续期、删除，或在到期前将其分派到某个具体日期；若多次提醒后仍未处理，系统最终删除。

## Recommendation
推荐命名为“悬置箱”。这是最贴近你现有语义的名称：不是普通收件箱，也不是 someday list，而是带明确倒计时和强制决策窗口的中转区。

## Feasibility
可行，且代码可复用度较高。主要可复用点包括：
- 扩展页模块入口与详情页结构：`Features/Extensions/ExtensionsHubView.swift`
- 任务编辑表单：`Shared/Components/TaskEditorSheet.swift`
- 未来周/日创建与定位：`Features/Pending/PendingViewModel.swift`
- 将任务落到某个具体未来日期的核心逻辑：`Services/TaskPostponeService.swift`
- 本地通知调度：`Services/NotificationService.swift`
- 周期性状态推进入口：`App/WeekyiiApp.swift` + `Services/StateMachine.swift`

## Recommended Architecture
不要复用 `TaskItem` 直接承载悬置任务。推荐新增独立模型 `SuspendedTaskItem`。

原因：
- `TaskItem` 当前天然属于某个 `DayModel` 或 `ProjectModel`，语义是“已落盘到某日/项目的执行任务”。
- 现有状态机按天处理 `draft/execute/expired`，如果让无日期任务混入 `TaskItem`，会污染现有过期与排序逻辑。
- 悬置任务的核心字段是 `decisionDeadline / reminderCount / snoozeCount / finalExpiryAt`，这些都不属于普通 `TaskItem`。

推荐新增字段：
- `id`
- `title`
- `taskDescription`
- `taskType`
- `steps`
- `attachments`
- `createdAt`
- `decisionDeadline`
- `lastReminderAt`
- `reminderCount`
- `maxReminderCount`
- `status`：`active | assigned | deleted`
- `preferredCountdownPreset`：`10d | 30d | custom`

## Primary Flows
### 1. 创建
- 用户在扩展页“悬置箱”新增任务。
- 创建时必须选择倒计时：`10 天`、`30 天`、`自定义天数`。
- 保存后写入 `decisionDeadline`，并立即调度提醒通知。

### 2. 续期
- 用户可在到期前进入详情或卡片操作，续期 `+10 天`、`+30 天` 或自定义。
- 续期会更新 `decisionDeadline`，清理旧通知并重排新通知。

### 3. 分派到具体某天
- 用户选择目标日期。
- 复用 `TaskPostponeService` 中“定位目标周/目标天、必要时创建周/天”的思路。
- 但不是移动已有 `TaskItem`，而是：
  1. 校验目标日期是否可用；
  2. 必要时创建目标周和目标天；
  3. 由 `SuspendedTaskItem` 生成新的 `TaskItem(zone: .draft)` 写入目标日；
  4. 删除原悬置任务；
  5. 取消悬置通知。

### 4. 到期提醒
- 推荐 3 个提醒层级：
  - `T-3 天`
  - `T-1 天`
  - `T-0 天`
- 通知文案围绕“续期 / 分派 / 删除”决策。
- 第一版不建议直接做通知 action button，而是先做普通本地通知 + 应用内入口。这样风险最低。

### 5. 最终清理
- 当超过最终宽限期且提醒次数耗尽，系统删除该悬置任务。
- 这里有一个硬限制：在当前架构下，应用无法保证“用户完全不打开 App 也能按时删库”。
- 因此推荐定义为：
  - 通知尽可能按时发出；
  - 真正的数据删除在 `StateMachine.processStateTransitions()` 或扩展页进入时执行 sweep；
  - 也就是“下次应用活跃时强制删除”。

## Reuse Map
### High Reuse
1. `TaskEditorSheet`
- 可直接复用输入 title/description/type/steps/attachments 的 UI。
- 只需增加“倒计时 preset”区域或在外层包装一个专用 sheet。

2. `TaskPostponeService`
- 其 `preview/resolveTargetDay/resolveTargetWeek` 思路高度可复用。
- 建议抽出更通用的 `FutureDayResolutionService`，让 Today postpone 和 Suspended assign 共用。

3. `PendingViewModel.createWeek(containing:)` 与 `day(in:for:)`
- 可作为目标日期落盘的参考实现。

4. `NotificationService`
- 已有 schedule/cancel 模式，可扩成 `scheduleSuspendedTaskNotifications(for:)` 和 `cancelSuspendedTaskNotifications(for:)`。

5. `ExtensionsHubView`
- 现有扩展页已经有 module preview 容器，适合新增第三块模块。

### Medium Reuse
1. `MindStamp` 模块的“轻量独立实体 + 扩展页入口”模式
- 结构上很适合照着做，但业务语义不同。

2. `PendingWeekDetailView`
- 草稿 CRUD 结构可借鉴，用于“悬置箱详情页”的编辑列表。

## New Components Required
必须新增：
- `Models/SuspendedTaskItem.swift`
- `Models/Enums/SuspendedTaskStatus.swift`
- `Features/Extensions/SuspendedTasksFullView.swift`
- `Features/Extensions/SuspendedTaskEditorSheet.swift` 或包装 `TaskEditorSheet`
- `Features/Extensions/SuspendedTaskViewModel.swift`
- `Services/SuspendedTaskLifecycleService.swift` 或扩充 `StateMachine`
- Schema V3 + migration plan 更新

建议新增但可后置：
- `Services/FutureDayResolutionService.swift`
  - 把 `TaskPostponeService` 的周/天创建解析逻辑抽出来，减少重复。

## UI Plan
### Extensions 页
新增第三个模块，推荐顺序：
1. Projects
2. Suspended Tasks
3. Mind Stamps

模块预览展示：
- 活跃悬置任务数
- 最近到期的 2-3 个任务
- 每个任务展示：标题、剩余天数、类型标签
- CTA：新增悬置任务

### 悬置箱详情页
需要有：
- 顶部统计：总数、7 天内到期数、今日到期数
- 列表分组：`即将到期` / `其他悬置`
- 每行操作：
  - 编辑
  - 续期
  - 分派到日期
  - 删除（必须确认）

### 创建/编辑 Sheet
必填：
- 标题
- 倒计时 preset

可选：
- 描述
- 类型
- 子步骤
- 附件

## Hard Problems / Pitfalls
### 1. 自动删除的时机不可能 100% 精准
这是当前方案最大的现实限制。
- 本地通知能准时弹出。
- 但本地通知本身不能直接替你修改 SwiftData。
- 现有工程也没有 BGTask 调度基础设施。
- 所以“多次通知无效后自动删除”只能保证为：应用下一次进入 active 或分钟级 state machine tick 时删除。

### 2. 不要复用 `TaskItem` 做悬置实体
否则会遇到：
- zone 语义不成立
- day 为空时很多逻辑不安全
- 排序、统计、项目关联、过期流转全被污染

### 3. 分派到具体某天时要保证原子性
正确顺序应是：
- resolve target day/week
- create new `TaskItem`
- append to target day
- save
- delete suspended item
- cancel notifications
如果中途失败，不能出现“悬置任务已删，但目标天没写进去”。

### 4. 通知去重与续期重排
续期后必须：
- 取消旧通知
- 只保留新的 deadline 通知
否则用户会收到失效提醒。

### 5. 强删除策略需要产品口径稳定
“不给用户留后路”很强硬，需要提前固定规则：
- 最大提醒次数是多少
- 最终宽限期是 0 天还是 1 天
- 删除后是否要写审计日志
第一版建议：不保留恢复站，但保留一次性的确认说明文案。

## Recommended Rollout
### Phase 1
- 新模型
- 扩展页模块入口
- CRUD
- 倒计时创建/续期
- 分派到具体日期
- 通知调度
- 应用 active 时的清理 sweep

### Phase 2
- 更丰富的通知节奏
- 统计面板
- 更细的筛选和排序
- 可选的通知 action buttons

## Testing Strategy
必须覆盖：
1. 创建悬置任务时必须有 countdown preset
2. 续期会重排 `decisionDeadline`
3. 分派到已存在 day 时直接写入 draft
4. 分派到缺失 day/缺失 week 时能自动创建
5. 分派成功后原悬置任务删除
6. 到期 sweep 会删除超过最终宽限期的悬置任务
7. 通知续期后旧 request 被取消
8. 删除操作必须确认

## Final Assessment
这个需求和 Weekyii 的产品哲学是相容的，但它本质上不是“普通待办”，而是“强制二次决策箱”。

最稳妥的方案是：
- 作为扩展页的新模块存在；
- 独立数据模型；
- 复用现有未来周/某天创建与任务编辑能力；
- 自动删除交给 state machine 在应用活跃时收口，而不是承诺系统级后台硬删除。
