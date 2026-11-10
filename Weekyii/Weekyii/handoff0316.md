# Weekyii 工作交接细则（handoff0316）

## 1. 当前任务目标

当前最近一项明确任务是继续开发 Weekyii 的「扩展」首页，重点处理“习惯追踪”模块的视觉呈现：

- 将扩展首页中的习惯模块从两列网格里的方形/近方形卡片改为全宽横向长方体卡片。
- 内部信息层级和视觉语言要与扩展首页已有的“呆胶布 / 悬置箱 / 项目”模块一致：模块标题栏、图标圆底、卡片圆角、描边、阴影、主题色和间距应属于同一套设计系统。
- 解决当前习惯卡片“留白过大、信息密度不均、标题和内容关系弱、进度信息悬浮、空状态像临时占位”的粗糙感。
- 只允许修改 UI/SwiftUI 布局和样式，不改变习惯生成、统计、轮换、导航、创建、编辑、归档、删除或任务状态逻辑。

完成标准：

1. `HabitsModulePreview` 仍进入原来的 `HabitsFullView`，仍使用原来的 `LiveModuleTile` 轮换数据。
2. 习惯模块在扩展首页是独立的全宽横向卡；空状态也保持相同宽卡形态。
3. 习惯名称、重复规则、今日进度、习惯数量等现有信息仍可见，但通过稳定的标题/主体/辅助信息层级呈现。
4. 不引入新 SwiftData 字段、迁移、后台任务、网络接口或业务规则。
5. 不误删当前工作区中其他 Agent/用户已经留下的改动。

## 2. 当前进展

### Git 与分支

- 当前目录：`/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii`
- 当前分支：`online-chatgpt-develop`
- 当前 HEAD：`6b4c4da test: cover monthly and one-off habit schedules plus timeline states`
- 最近相关提交顺序：
  - `c17b565`：习惯详情页、统计和完整历史时间线
  - `e66a110`：习惯编辑表单，支持按星期、按月、不重复
  - `c965d64`：阻止习惯任务后移
  - `c1ea099`：App 健康协调时物化习惯任务
  - `13753a8`：习惯本地化条目
  - `6b4c4da`：月度/一次性计划与时间线状态测试

### 最近一次视觉修改

本轮已经改动 `Features/Extensions/ExtensionsHubView.swift`：

- `ExtensionsHubView.body` 中，呆胶布和悬置箱继续放在两列 `LazyVGrid`；习惯模块移到网格外，单独占满宽度；项目模块仍位于其后。
- 新增 `HubWideSurface`，作为 `HubSquareSurface` 的横向卡片版本，沿用 `backgroundSecondary`、`WeekRadius.medium`、浅色描边和阴影。
- `HabitLiveTile` 改为使用 `HubWideSurface`，将图标、习惯名、重复规则和今日进度放在同一水平内容区。
- 新增 `HabitEmptyLiveTile`，让“还没有习惯”的空状态也使用全宽横向卡，而不是继续使用方形空卡。
- 仍保留 `NavigationLink`、`LiveModuleTile`、`animationsActive` 和原来的 `HabitViewModel` 数据来源。

当前工作区里，`ExtensionsHubView.swift` 不只有本轮改动，还存在其他未提交视觉改动：

- 外层加入了 `GeometryReader`，并用 `.frame(minWidth: geo.size.width, minHeight: geo.size.height)` 约束滚动内容。
- `ProjectsModulePreview` 被加了 `.frame(maxHeight: .infinity)`。
- `ProjectFocusLiveTile` 被重做为大进度环 + 剩余数量 + 下一步任务卡。
- 当前习惯卡的实现已经被工作区后续改动调整过：标题栏右侧显示 `completedToday/scheduledToday`，内容右侧在多个习惯时显示“还有 N 个习惯”和“点击查看全部”。不要假设它仍与上一轮最终回复中的代码完全一致，接手时应以工作区实际文件为准。

### 当前工作区状态

工作区不是干净状态。当前 `git status --short` 主要包括：

- 已修改：
  - `App/WeekyiiApp.swift`
  - `Features/Extensions/ExtensionsHubView.swift`
  - `Features/Extensions/HabitDetailView.swift`
  - `Features/Extensions/HabitsFullView.swift`
  - `Resources/LaunchScreen.storyboard`
  - `Resources/Localizable.xcstrings`
  - `Services/HabitStatistics.swift`
  - `Tests/ModelTests.swift`
  - `WeekyiiUITests/DraftReorderUITests.swift`
  - Xcode 用户界面状态文件及多个 `.DS_Store`
- 未跟踪：
  - `.workbuddy-ai/`
  - `ICLOUD_SYNC_REVIEW_2026-09-13.md`
  - `ICLOUD_SYNC_REVIEW_ROUND2_2026-09-13.md`
  - `docs/plans/2026-09-16-habit-tracker.md`
  - `docs/plans/2026-09-18-focus-countdown-plan.md`
  - `docs/plans/2026-09-18-habit-tracker-v3.md`
  - `Resources/Assets.xcassets/LaunchBackground.imageset/`
  - `weekyii-icon_副本.png`

这些改动属于用户或此前工作流留下的内容，禁止直接 `git reset --hard`、`git checkout --`、清空 stash 或批量删除。

上一轮习惯宽卡补丁完成后曾执行过轻量 `git diff --check`，当时通过；当前工作区后来叠加了其他未提交改动，重新检查时在 `Features/Extensions/ExtensionsHubView.swift:245` 发现一行已有的尾随空格，因此当前整份工作区不能宣称 diff check 全部通过。没有执行完整 Xcode 构建或 UI 测试，因为用户明确表示自己会在真机/Xcode 查看效果、不希望为了这类视觉改动消耗大量 token 做测试。因此不能向用户声称“构建通过”。

## 3. 关键上下文

### 用户明确要求与偏好

- 用户要求直接改代码，通常自己在 Xcode/真机观察效果；不要擅自做大量测试、操作设备或发布动作。
- “只改视觉，不动功能/逻辑”是本次习惯卡任务的硬约束。
- 用户非常在意全局视觉语言：不能生搬旧卡片；标题、间距、色彩、图标、卡片比例和各主题必须协调。
- 用户之前明确要求 Weekyii 顶部品牌名保留原来的手写字体，不要改成普通系统字体。
- 「过去」和「未来」是不同功能板块，不能因为想统一视觉就把功能/排版语义强行合并；只做视觉语言层的对齐。
- 多主题是实际功能，不能只在琥珀/橙色主题下看起来正常。现有主题系统位于 `Shared/Extensions/Color+Weekyii.swift`，并有 `ThemeVisualStyle`（classic、brutalist、neon、paper、terminal 等）。

### 习惯功能的业务语义（不可被 UI 改动破坏）

- `HabitModel` 位于 `Models/HabitModel.swift`，支持三种计划：
  - `.weekly`：ISO 周一到周日多选；
  - `.monthly`：1–31 日多选，不存在的日期跳过；
  - `.once`：只在开始日生成一次。
- `HabitModel` 关键字段：`startDayId`、`generatedThroughDayId`、`isActive`、`sortOrder`、习惯颜色/图标，以及 `records` 关系。
- `HabitDayRecord` 位于 `Models/HabitDayRecord.swift`，状态为 `pending / completed / missed`。
- 习惯任务生成服务是 `Services/HabitTaskMaterializer.swift`：
  - `sync(today:now:)` 先把过期 pending 记录标记为 missed，再只处理“今天”；
  - `materializeToday` 只解析今天的 `DayModel`，绝不循环创建未来周/未来日；
  - `generatedThroughDayId` 防止同一天重复生成，也保证用户手动删除今日习惯任务后当天不会自动复活；
  - `assignToday` 是用户主动补加今日任务的例外入口。
- `App/WeekyiiApp.swift` 的 `AppHealthCoordinator.reconcile` 在启动、回前台、状态协调等时机调用 `HabitTaskMaterializer.sync`。这条链路必须保持“只今日物化”的未来点亮不变量。
- `Features/Extensions/HabitViewModel.swift` 负责刷新、创建、编辑、恢复/停用、删除和 `assignToday`；创建/编辑/恢复后会立即同步今日。
- `Services/HabitStatistics.swift` 负责今日状态、当前连续、最长连续、完成率和完整时间线。详情页的“中断”来自实际生成后未完成的记录；未生成日与中断日必须区分。

### 旧计划与关键决策

- `docs/plans/2026-09-16-habit-tracker.md` 是 v2，已被 `docs/plans/2026-09-18-habit-tracker-v3.md` 取代。
- v2 的“滚动 14 天窗口 + 自动生成未来周/日”会破坏 Weekyii 的“未来只能由用户显式点亮”设计，曾被明确判定为致命问题；不要按 v2 的窗口语义恢复代码。
- v3 改成“只在当天首次协调时物化今日任务”，增加 `HabitDayRecord` 来保存历史和中断状态。
- v3 仍引用 v2 的迁移/CloudKit/Schema 冻结部分，但 v3 的生成语义和 UI 范围优先。
- `docs/plans/2026-09-18-focus-countdown-plan.md` 目前只是评估文档，明确写着“仅评估，未改任何代码”，不要把其中的专注倒计时当成已实现功能。

### App Store Connect / TestFlight 历史背景

这部分不是当前视觉任务，但可能在下一会话被继续询问：

- App bundle ID：`com.fluentdesign.Weekyii`；Widget bundle ID：`com.fluentdesign.Weekyii.widget`。
- Apple Developer 团队在 Xcode 中显示为 `jingyi luo`。
- 曾出现 Xcode “Communication with Apple failed: Your team has no devices from which to generate a provisioning profile” 和两个 bundle 找不到 iOS Development provisioning profile 的错误。这是把目标设为 `Any iOS Device (arm64)` 时的开发签名/设备注册问题；TestFlight 分发本身不要求注册 iPhone，但真机开发运行需要开发签名/已注册设备或正确的开发配置。
- App Store Connect 的 TestFlight 页面曾看到版本 1.0 / 构建 1，并处于“准备提交”或需要补充出口合规信息的状态；加密问卷必须完成后才能继续外部测试流程。不要仅凭 Xcode Archive 成功就声称已经上传或已经可供测试。

### iCloud 历史背景

- 用户在“数据与安全”页看到 `CKErrorDomain 错误 2`，来自模拟器同步失败提示。
- 这不能直接推断为 iCloud 空间不足；错误 2 可能是 CloudKit partial failure 或容器/生产 schema/权限/具体 record 失败。
- 当前诊断仍缺少对 `CKPartialErrorsByItemIDKey` 的逐项展开；如果以后继续处理 iCloud，应先查具体子错误，不要直接让用户购买空间或重装。
- 相关审查记录：`ICLOUD_SYNC_REVIEW_2026-09-13.md`、`ICLOUD_SYNC_REVIEW_ROUND2_2026-09-13.md`。

## 4. 关键发现

1. **习惯自动生成未来任务曾经是最危险的设计点。** 旧 v2 计划的 14 天滚动窗口会不断解析未来日期并创建未来周，破坏“未来点亮”设计；当前 `HabitTaskMaterializer` 已改成只处理今天，后续任何修改都必须保持这一点。
2. **当前生成是幂等的。** 先检查同一 habit 的今日任务，再检查今日状态和 kill time，最后创建任务与 pending record；同一天由多个 reconcile 触发不会重复创建。
3. **今日删除不会当日复活，但跨日会由新日期重新评估。** 这是 `generatedThroughDayId` 的水位线语义，UI 不能通过自动刷新绕过它。
4. **“中断”和“未记录”是不同状态。** `missed` 表示曾物化的 pending 到了次日仍未完成；`unrecorded` 表示当天没有可追踪记录。统计和时间线不能把两者合并。
5. **扩展首页现在存在两个层面的未提交 UI 改动。** 习惯宽卡是当前任务；项目大进度卡、`GeometryReader` 外壳和 `maxHeight: .infinity` 是工作区已有的其他改动。接手时要先审阅整体布局，避免只修习惯卡后让项目卡出现垂直撑满或 ScrollView 空白。
6. **主题适配仍是风险。** `HubSquareSurface`/`HubWideSurface` 当前使用固定 `backgroundSecondary`、固定 0.14 描边和黑色浅阴影，没有完全读取 `ThemeVisualStyle` 的 corner/border/shadow/symbol 变体；如果用户反馈霓虹、粗野、纸感或终端主题“不协调”，应优先检查这里，而不是改习惯业务逻辑。
7. **当前未提交的 `Resources/Localizable.xcstrings` diff 很大。** 它可能包含 Xcode 本地化文件重排而不只是新增 key，不能用格式化或全量重生成覆盖用户内容。
8. **当前扩展卡片的动画由 `LiveModuleTile` 控制。** 它使用 `.task(id:)`、随机队列、错峰初始延迟和减少动态效果降级；习惯 UI 调整不应复制一套轮换逻辑或改变 `items`/`isActive`。
9. **项目卡当前有一份未提交的“进度环 + 下一步卡”重设计。** 该改动未在本轮由用户确认，不要把它误认为已稳定设计；如果要继续视觉统一，应先确认其在多主题/窄屏下是否可用。

## 5. 未完成事项

按优先级：

### P0：先确认工作区实际状态，避免误改

- 阅读 `git diff -- Features/Extensions/ExtensionsHubView.swift`，分清习惯宽卡改动与其他项目/外壳改动。
- 检查 `GeometryReader` + `.frame(minWidth: geo.size.width, minHeight: geo.size.height)` + 项目 `.frame(maxHeight: .infinity)` 是否造成 ScrollView 内不必要的撑高、空白或项目卡高度异常。
- 不要清理/回滚工作区中用户已有的其他文件。

### P1：完成习惯扩展卡的视觉收口

- 在 `Features/Extensions/ExtensionsHubView.swift` 检查宽卡在以下状态的一致性：一个习惯、多个习惯轮换、没有习惯、长名称、长重复规则、今日未排期、今日 0/0、今日完成 1/1。
- 确认标题栏右侧到底显示“习惯总数”还是“今日进度”，两者不能在不同版本中语义漂移；这属于 UI 信息架构，不要修改统计计算。
- 确认 `HabitEmptyLiveTile` 的空状态文本不会挤压或被截断。
- 复核扩展页所有主题，尤其是 `WeekTheme.visualStyle` 非 classic 主题下的圆角、描边、阴影和图标变体。

### P1：对习惯“只今日物化”做定向回归审阅

- 检查 `Services/HabitTaskMaterializer.swift` 是否仍只调用 `resolveDay(on: todayStart, ...)`。
- 检查 `AppHealthCoordinator.reconcile`、`HabitViewModel.createHabit/updateHabit/setActive` 的调用链，不得出现未来日期循环。
- 检查 `ExtensionsViewModel` 中的显式未来周/日创建逻辑，确保它只由用户在 Pending 页面操作触发，不被习惯同步调用。
- 如用户后续要求功能确认，再针对“重复调用 sync 不重复、手动删除今日不复活、跨日生成下一次、未来为空”添加/运行定向测试；不要恢复 v2 的未来窗口测试。

### P2：审阅当前其他未提交改动

- `Features/Extensions/HabitDetailView.swift`：确认 toolbar 菜单仍覆盖编辑、停用/恢复、删除；确认“加入今日”只在今日已排期且没有今日任务时出现，且没有误改业务。
- `Features/Extensions/HabitsFullView.swift`：确认进度条 + 环形进度在窄屏和长本地化文本下不溢出。
- `App/WeekyiiApp.swift`：审阅新增模型注册/协调器改动是否已与当前 Schema/CloudKit 版本匹配。
- `Resources/Localizable.xcstrings`：检查新增习惯 key 是否存在，不要对整个文件做无关重排。
- `Tests/ModelTests.swift`：确认新增测试覆盖 monthly/once/timeline，而非依赖 UI 快照。

### P3：外部发布和 iCloud（仅用户重新提出时）

- TestFlight：先确认 Archive、上传记录、出口合规和 TestFlight 状态，不要根据本地 Xcode 状态猜测。
- iCloud：先读取具体 CloudKit 子错误和容器环境，再判断是否 schema/权限/数据问题，不能先归因到容量。

## 6. 建议接手路径

1. 先执行只读检查：
   - `git status --short`
   - `git diff --stat`
   - `git diff -- Features/Extensions/ExtensionsHubView.swift`
   - `rg -n "materializ|generatedThrough|resolveDay\(|HabitDayRecord" App Services Features/Extensions Models`
2. 阅读以下文件的实际当前版本：
   - `Features/Extensions/ExtensionsHubView.swift`
   - `Features/Extensions/HabitsFullView.swift`
   - `Features/Extensions/HabitDetailView.swift`
   - `Features/Extensions/HabitViewModel.swift`
   - `Services/HabitTaskMaterializer.swift`
   - `Services/HabitStatistics.swift`
   - `Models/HabitModel.swift`
   - `Models/HabitDayRecord.swift`
   - `Shared/Extensions/Color+Weekyii.swift`
   - `Shared/DesignSystem/Spacing+Weekyii.swift`
3. 先验证 UI 数据边界，而不是马上重写：
   - `HubWideSurface` 是否真的拿到父容器全宽；
   - `LiveModuleTile` 轮换时 `.id(selectedItem.id)` 是否仍然稳定；
   - 习惯名称和 scheduleSummary 的长度是否会挤掉右侧进度；
   - empty / one item / many items 的高度是否一致；
   - 主题色变化是否仅来自已有 `habit.habitColor`，没有新增持久化颜色字段。
4. 若要继续视觉修改，只改 `ExtensionsHubView.swift` 及必要的共享视觉组件；不要动 `HabitTaskMaterializer`、`HabitViewModel`、`HabitStatistics`，除非用户明确要求功能修复。
5. 每次修改后至少执行 `git diff --check`，然后报告“检查了什么”；如果不运行完整构建，必须明确说“未构建”。
6. 未经用户明确要求，不要 commit、push、修改分支、操作 Xcode、上传 TestFlight 或改 CloudKit schema。

## 7. 风险与注意事项

- **禁止破坏未来点亮不变量。** 任何 `for date in today...future`、滚动窗口、水位线前推到未来、由习惯同步调用 `Pending` 周创建，都应视为高风险，先停下来复核。
- **不要把 v2 计划当现行计划。** v2 的 14 天窗口已明确废弃；v3 才是当前语义基线。
- **不要因工作区脏而 reset/checkout。** 当前改动涉及模型注册、详情页、首页视觉、本地化、启动页和测试，可能来自用户的多次迭代。
- **不要把 UI 视觉卡片与业务模块混为一谈。** `LiveModuleTile` 只是展示轮换；点击目标、VM、统计和任务物化逻辑都不能从视觉重构中顺便改掉。
- **不要为了“统一”抹掉过去/未来的功能差异。** 用户只要求视觉语言协调，不要求两个板块变成同一布局或同一数据模型。
- **多主题不能只看琥珀主题。** 固定黑色阴影、固定描边、不读取 `ThemeVisualStyle` 可能在 neon/terminal/brutalist/paper 下产生明显不协调；如需修，应以共享视觉层为边界并先说明影响范围。
- **不要把 iCloud `CKErrorDomain 2` 直接解释成空间不足。** 必须读取 CloudKit partial failure 的具体子错误。
- **不要把 TestFlight“准备提交”当作“已上传且外部可测”。** 应分别确认构建上传、加密合规、测试组和审核状态。
- 当前分支中 Xcode 的 `xcuserstate`、`.DS_Store` 和资源副本存在脏改动，通常不应纳入功能 commit；但也不要未经用户确认删除。

### 下一位 Agent 的第一步建议

先不要写代码。先在当前目录执行 `git status --short` 与 `git diff -- Features/Extensions/ExtensionsHubView.swift`，把扩展首页中“习惯宽卡”“项目进度卡”“GeometryReader 外壳”三组未提交改动分开，再核对 `Services/HabitTaskMaterializer.swift` 是否只处理今天。确认工作区边界和未来点亮不变量后，再决定下一步是继续收口视觉，还是先修当前布局撑高/多主题适配问题。
