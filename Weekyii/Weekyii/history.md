# Weekyii 历史开发经验沉淀（会话迁移版）

> 更新时间：2026-03-31  
> 作用：给新会话/新 Agent 快速接管 Weekyii 的历史决策、实现经验和高频风险点。  
> 适用分支：`codex/theme-orange`（近期主工作线）

---

## 1. 产品与交互层面的关键历史决策

### 1.1 项目页（扩展 > 项目）已转向 Windows Phone 磁贴范式
- 核心目标不是普通卡片列表，而是可编辑的磁贴工作台。
- 已明确交互共识：
  - 长按进入编辑态；
  - 删除必须确认（且支持级联影响）；
  - 尺寸切换在编辑态完成；
  - 支持拖拽重排；
  - 磁贴间任何状态下都不能重叠。
- 用户对“WP 风格”要求非常具体：密度、节奏、信息前置（进入项目前先感知项目状态）。

### 1.2 “视觉效果”优先级高，但不能牺牲稳定性
- 用户接受持续微调，尤其关注：
  - 信息层级是否清晰；
  - 颜色是否刺眼/杂乱；
  - 动效是否造成布局抖动或重叠。
- 明确禁忌：任何“呼吸感”如果改变 tile 实际高度，会直接导致布局冲突，必须避免。

### 1.3 过去/未来要统一视觉规律，但保留权限差异
- Pending（未来）可编辑；Past（过去）偏只读与分析。
- 已形成方向：信息架构统一、视觉节奏统一，但不强行统一业务能力。

### 1.4 草稿任务/后移任务交互已有高敏感反馈
- 用户对底部弹层（后移确认）的体验要求很明确：
  - 默认高度合理；
  - 主按钮固定底部；
  - 内容可拉升但默认态要完整可读。
- 任何“全屏草稿扩展”若影响主流程可读性，会被要求快速回退。

---

## 2. 架构与代码层的关键经验

### 2.1 周预报（Week Outlook）是当前周卡核心信息源
- 数据计算入口：`Features/Pending/PendingViewModel.swift`
  - `WeekOutlookTone`
  - `WeekOutlookSnapshot`
  - `buildWeekOutlook(for:)`
- 展示入口：`Features/Pending/PendingWeekCard.swift`
- 挂载入口：`Features/Pending/PendingView.swift`
- 测试入口：`Tests/ModelTests.swift`（已有 tone 分类相关测试）

### 2.2 周卡 UI 改造经验（当前状态）
- 已做过多轮重排，最终经验：
  - 文本要分层（标题/一句话预期/建议）；
  - 类型计数要紧凑；
  - sparkline 仅承担趋势提示，不应抢主视线；
  - 高风险 tone（红色）必须克制，避免整卡“噪音红”。
- 常见反模式：
  - 同一区块同时放太多高饱和颜色；
  - 文案多行且无优先级；
  - 图表和文本争抢视觉焦点。

### 2.3 主题系统已是“双态（浅/深）+ 主题色板”结构
- 核心文件：`Shared/Extensions/Color+Weekyii.swift`
- 设置持久化：`Resources/UserSettings.swift`
- 设置 UI：`Resources/SettingsView.swift`
- App 注入：`App/WeekyiiApp.swift`、`App/ContentView.swift`
- Widget 同步链路：`Shared/WidgetSupport/WeekyiiWidgetSupport.swift` + `WeekyiiWidget/*`

### 2.4 Live Activity（灵动岛/锁屏）已落地，但设计迭代频繁
- 经验结论：
  - 动态岛黑底是平台特性，不应试图改壳；
  - 应优化“岛内内容对比度与信息密度”；
  - 锁屏活动与动态岛需要不同语义色策略；
  - 明暗模式链路必须可验证，不能仅凭主 App 观感判断。

---

## 3. 曾经踩过的高价值坑（必须记住）

### 3.1 磁贴重叠根因：高度非模块化 + 间距不足 + 动画影响布局
- 典型症状：
  - 编辑态/拖拽态出现上下重叠；
  - 小砖右下角按钮被邻近磁贴遮挡；
  - 与“新建项目”区域垂直间距冲突。
- 经验法则：
  - 先锁定尺寸体系（离散尺寸）；
  - 再锁定 rowSpacing/底部安全间距；
  - 最后才做动效细化。

### 3.2 数据库“退回内存模式”错误是高优先级事故
- 曾出现“本地数据暂时不可用，已进入只保启动模式”。
- 根因方向：模型变更/迁移链路与底层持久化不匹配。
- 经验法则：
  - 结构变更先审迁移；
  - 不允许静默丢数；
  - 先保证 fail-closed 与恢复路径，再做 UI。

### 3.3 不同分支与工作区混用会引入“文件找不到”
- 出现过：`Build input file cannot be found ... TodayViewState.swift`
- 常见原因：
  - 分支切换后 `project.pbxproj` 与文件系统不一致；
  - 某些文件未纳入 git 管理，切分支后丢失引用。
- 经验法则：
  - 在复杂切换前先 commit 快照；
  - 用 `git status --short` 检查未跟踪关键文件；
  - 避免把 `.worktrees` 内容纳入常规提交。

### 3.4 `git add .` 在此仓库风险高
- 仓库根下有 `.worktrees`、`.DS_Store`、xcode user state 等噪音源。
- 已形成操作习惯：
  - `git add -u` + 按路径补 add；
  - 提交前人工审 `git status --short`。

---

## 4. 用户偏好与协作模式（非常关键）

### 4.1 用户风格偏好
- 喜欢直接落地，不喜欢长时间停留在“纯分析”。
- 视觉反馈非常敏感，且会频繁要求“再改一版”。
- 对“抖动、重叠、拥挤、信息密度失衡”容忍度低。

### 4.2 交付方式偏好
- 允许先做骨架，再持续精修；
- 但每次迭代都要有明确可见变化；
- 经常要求“先给完整方案，再落地”；
- 对测试态度：有时要求全量测，有时明确“不用测”，要按当次指令执行。

### 4.3 语言与文案偏好
- 中文为主；
- 文案要直接、可操作；
- 不要废话与模板化表达。

---

## 5. 当前高价值文件地图（新会话优先看）

### 5.1 Pending（未来）周卡与周预报
- `Features/Pending/PendingWeekCard.swift`
- `Features/Pending/PendingView.swift`
- `Features/Pending/PendingViewModel.swift`
- `Tests/ModelTests.swift`（WeekOutlook 相关）

### 5.2 主题与外观
- `Shared/Extensions/Color+Weekyii.swift`
- `Resources/UserSettings.swift`
- `Resources/SettingsView.swift`
- `App/WeekyiiApp.swift`
- `App/ContentView.swift`

### 5.3 项目磁贴系统
- `Features/Extensions/ExtensionsHubView.swift`
- `Features/Extensions/ExtensionsView.swift`
- `Features/Extensions/ExtensionsViewModel.swift`
- `Models/ProjectModel.swift`

### 5.4 Widget / Live Activity
- `Shared/WidgetSupport/WeekyiiWidgetSupport.swift`
- `WeekyiiWidget/WeekyiiWidget.swift`
- `WeekyiiWidget/WeekyiiWidgetBundle.swift`

---

## 6. 测试与构建基线（iPhone 17 Pro / iOS 26.2）

### 6.1 常用命令
- 构建 App：
  - `xcodebuild build -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'`
- 核心测试：
  - `xcodebuild test -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:WeekyiiTests/ModelTests`
  - `xcodebuild test -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:WeekyiiTests/StateMachineTests`

### 6.2 测试经验
- UI 测试不要和单测并行混跑同模拟器会话，曾导致假失败。
- Widget scheme 的 test action 不是总可用，先以 build 验证为主。

---

## 7. 对下一会话最有用的“执行套路”

1. **先读现状**：`git status --short` + 目标模块入口文件。  
2. **先做小步可见改动**：一次只改一个核心区块（如周卡下半区）。  
3. **立刻 build 验证**：不把多轮视觉修改堆到最后。  
4. **保持改动边界**：避免把无关模块一起带入提交。  
5. **记录可回滚点**：用户经常要求“撤销某方案”，要保证可快速回退。

---

## 8. 当前会话迁移建议（开新窗后第一步）

1. 打开并快速浏览：
   - `history.md`（本文）
   - `handoff0320.md`
   - 当前目标模块文件（若是周卡就看 Pending 三件套）
2. 运行一次最小 build，确认新会话环境可编译。
3. 根据用户最新诉求先产出“1页计划 + 1轮落地改动”，不要在方案阶段停滞过久。

---

## 9. 2026-04-01 增量经验（本会话新增）

### 9.1 灵动岛 compact 态长度控制（避免遮挡状态栏）
- 问题现象：未点击前（compact）占用过长，导致看不清左上时间与右上信号电量。
- 实践结论：
  - `compactLeading` 与 `compactTrailing` 都应优先使用“图标级”信息密度；
  - 倒计时文本不适合 compact 区，保留到 expanded/lock screen 展示更稳；
  - trailing 可用紧急态变色（如 <=1h 切 warning 色）提供风险信号。
- 已落地调整：
  - `IslandCompactLeading` 保持小尺寸任务类型图标；
  - `IslandCompactTrailing` 从倒计时文本改为 `timer` 图标，并按剩余时间切换强调色。

### 9.2 Live Activity 信息密度分层原则
- compact：只保留“身份/状态信号”。
- expanded：展示完整任务文案与可读倒计时。
- lock screen：展示统计指标与操作按钮。
- 该分层可显著减少前摄区域占用，同时不丢核心可操作性。

---

## 9. 2026-03-31 增量经验（未来月视图与可编辑详情）

### 9.1 未来页月视图交互落地要点（已实现）
- 月视图已支持：
  - 过去日期统一灰色；
  - 过去日期不可点击、不可选中、不可添加；
  - 过去日期不显示任务标记与数量角标（避免误导“可操作”预期）。
- 相关文件：`Features/Pending/PendingView.swift`

### 9.2 月视图下方“已选日期任务列表”支持点击详情并编辑（已实现）
- 当前行为：
  - 点击任务时，若该日期可编辑且任务在 `draft` 区，进入可编辑 `TaskEditorSheet`；
  - 若不可编辑（如非 draft / 非可编辑日期），降级为只读详情查看；
  - 保存后会刷新当月摘要标记，保证任务数/DDL 标记同步更新。
- 关键实现点：
  - `PendingMonthEditTarget`（编辑上下文容器）
  - `monthEditTarget` sheet（编辑）
  - `selectedTaskForDetail` sheet（只读兜底）

### 9.3 构建验证经验（本地与受限环境差异）
- 在受限 CLI 环境中，可能出现与业务改动无关的构建失败：
  - `CoreSimulatorService connection became invalid`
  - `No available simulator runtimes for platform iphonesimulator`
  - `CompileAssetCatalogVariant ... fail`
- 经验法则：
  - 先区分“代码错误”与“环境错误”；
  - 功能验证优先在本机 Xcode/simulator 实机环境完成。

### 9.4 Widget 预览宏稳定性处理（已加护栏）
- 为避免某些环境中 `#Preview` 宏导致构建中断，已将 Widget 预览代码改为显式开关：
  - `#if DEBUG && canImport(ActivityKit) && WEEKYII_ENABLE_WIDGET_PREVIEWS`
- 文件：`WeekyiiWidget/WeekyiiWidget.swift`
- 启用预览时在对应 target Debug `Other Swift Flags` 增加：`-D WEEKYII_ENABLE_WIDGET_PREVIEWS`

---

## 10. 2026-03-31 锁屏后移动作回写延迟经验

### 10.1 现象
- 从锁屏 Live Activity 执行“后移 +1 天”后，任务数据已迁移，但锁屏组件状态偶发未即时刷新。

### 10.2 可能根因
- 动作链路里对 Widget 与 Live Activity 的刷新触发过于“间接”（依赖上层 onChange / 单次 reconcile 异步执行），在锁屏短生命周期下可能发生回写延迟。

### 10.3 已采用修复策略
- 在 `LiveActivityActionRouter.handle` 成功分支中，直接做两类刷新：
  - 显式调用 `WidgetSnapshotComposer.syncFromModelContext(...)`；
  - 调用 `liveActivityService.reconcile(...)` 后，再延迟约 350ms 追加一次 reconcile，降低短时异步丢更新概率。
- 文件：`App/WeekyiiApp.swift`

### 10.4 回归测试补强（已补）
- 新增 `StateMachineTests.test_liveActivityActionRouter_postponePerformsCriticalImmediateReconcile`，
  通过 `RecordingLiveActivityService` 验证锁屏后移动作会触发两次 `reconcileImmediately`。
- 目的：防止后续重构把“关键路径即时回写”退化为单次异步调用。
- 文件：`Tests/StateMachineTests.swift`

---

## 11. 2026-03-31 任务项目来源展示经验（草稿区 + 今日专注/冻结）

### 11.1 关系模型结论
- `TaskItem.project` 是可空关系，`ProjectModel.tasks` 为 `.nullify`，适合做“仅展示来源，不改变生命周期”。
- 删除项目但保留任务时，任务会走 `task.project = nil`，UI 应该自动隐藏来源标签。

### 11.2 实现策略
- 不改数据模型，不改删除逻辑，只在 UI 侧做条件渲染。
- 在共享组件中新增任务来源徽标（`TaskProjectOriginBadge`）并以参数开关控制：
  - `TaskRowView(showsProjectOrigin: Bool = false)`
  - `TaskCard(showsProjectOrigin: Bool = false)`
- 只在目标区域开启：
  - 各“按天草稿任务区”；
  - Today 执行态的 Focus 与 Frozen。

### 11.3 工程注意点
- 新增共享 View 时，若单独新建文件未加入 target，编译会报 `cannot find ... in scope`；
  最稳妥做法是先放入已编译的共享组件文件，避免 target membership 漏配。

---

## 12. 2026-04-01 Widget 全栈重构经验（锁屏配件 + 主屏 + Live Activity）

### 12.1 重构边界与原则
- 本次仅重构 Widget/Live Activity 的信息架构与视觉表达，不改任务生命周期与 action URL 语义。
- 保留动作：`done-focus`、`postpone-focus`、`open-today`。
- 采用“同语义跨家族映射”：各 family 都展示同一核心语义（进度、焦点、完成/总数），仅做信息密度降级。

### 12.2 关键实现文件
- `WeekyiiWidget/WeekyiiWidget.swift`

### 12.3 结构调整要点
- 将原先单体堆叠视图按层重组为：
  - 语义层：`WidgetSemanticData` / `WidgetWeekDaySemantic`
  - 主题 token 层：`WidgetVisualTokens`
  - 共享绘图原子：`WidgetProgressRing`、`WidgetLinearProgress`、`WidgetWeekStripCell`、`WidgetTaskPreviewLine`
  - 家族视图层：`systemSmall/Medium/Large` + `accessoryInline/Rectangular/Circular`
- Live Activity / Dynamic Island 改为控制优先布局：
  - 锁屏大卡保留焦点任务 + 倒计时 + 两个动作按钮
  - Dynamic Island expanded bottom 保留两动作按钮，compact/minimal 维持高可读压缩信息

### 12.4 锁屏添加页占位修复经验（`Please adopt co...`）
- 对所有 family 统一采用 `.containerBackground(for: .widget)` 的背景修饰入口，避免配件家族遗漏/分散配置。
- accessory family 不再用“无背景策略”，改为明确背景色语义（`accessoryBackground`），提高系统采纳稳定性。

### 12.5 验证命令与结果
- `xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build` 通过。
- `xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:WeekyiiTests/ModelTests test` 通过（46/46）。
- 测试日志中出现的 `device is passcode protected` 为本机已连接物理设备噪声，不影响模拟器测试结果。

---

## 13. 2026-04-01 今日体验修复经验（Start Flow + 拖拽边缘 + Dynamic Island）

### 13.1 Start Flow（准备开始）排版重构
- 将 `TodayView.startFlowSheet` 拆成独立子视图：
  - `StartFlowWarningStepView`
  - `StartFlowRitualStepView`
- Ritual 页从“Spacer 主导”改为固定三段：顶部说明、思想钢印主卡、底部确认按钮区。
- 思想钢印主卡对长文本使用限高滚动容器，避免半屏 detent 出现空洞与溢出。

### 13.2 今日草稿拖拽边缘修复（保留 List + onMove）
- 不改变拖拽机制，仅处理渲染链路：
  - `DraftEditorView` 的 `listRowBackground` 改为不透明语义背景；
  - 任务行改为稳定圆角容器与描边路径，减少拖拽 lift 时白边锯齿；
  - 在列表重排上下文使用 `TaskRowView.RenderContext.reorderList`。
- 结论：在保持现有交互的前提下，拖拽快照边缘稳定性更高。

### 13.3 Dynamic Island / Live Activity 数值重绘
- 倒计时统一改为基于 `remainingSeconds` 的固定格式字符串：
  - 标准态 `HH:MM:SS`
  - 紧凑态 `H:MM` / `MM:SS`
- 避免系统 `.timer` 文本在窄宽度下换行断裂；Trailing 区加了窄宽度保护。
- Expanded 信息层级重排：center 保留主任务与进度，trailing 展示剩余时间 + 截止提示，bottom 维持动作按钮。

### 13.4 本地验证与环境限制
- `xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -sdk iphonesimulator -configuration Debug build` 通过。
- `xcodebuild ... test` 在当前环境失败（CoreSimulatorService 连接不可用 + 无具体可用模拟器目的地），属于环境限制而非本次代码语义错误。

### 13.5 Dynamic Island 紧凑态长度控制（2026-04-01）
- 触发原因：compact 态占用过宽，遮挡状态栏时间/信号信息。
- 处理方式：
  - `compactLeading` 改为仅显示任务类型图标（去掉文本标签）。
  - `compactTrailing` 改为超短倒计时文案（`xh/xm/now`），替代更长格式。
- 结果：点击前灵动岛胶囊整体宽度明显收缩，状态栏信息可见性提升。

---

## 14. 2026-04-01 Live Activity 二次修复（expanded 下沉 + 通知中心裁切）

### 14.1 现象与根因
- 现象 A：黑底 expanded 卡里“剩余时间”跑到右下角，信息重心断裂。  
  根因：`IslandExpandedTrailing` 使用 `.dynamicIsland(verticalPlacement: .belowIfTooWide)`，在窄宽下被系统下沉。
- 现象 B：白底通知中心态顶部文案发灰、底部动作被裁切。  
  根因：锁屏卡信息密度过高（总高度超预算），在通知中心压缩态发生上下裁切；浅底主题对比度不足时观感更差。

### 14.2 已落地修复
- `IslandExpandedTrailing`：
  - 去掉 `belowIfTooWide` 下沉策略；
  - 倒计时改为短格式 `H:MM / MM:SS`；
  - 固定紧凑尺寸，避免右侧断裂布局。
- `LockScreenLiveActivityView`：
  - 顶部重排为“图标 + 标题/截止 + 剩余”单行主结构；
  - 移除重复层级，压缩卡片 spacing/padding、进度条高度、指标卡与按钮高度；
  - `LiveActionCapsule` 增加 `verticalPadding` 参数，锁屏态使用更紧凑的按钮高度；
  - 增加浅背景判定（hex 亮度），浅底时强制使用更深文字色，提升可读性。

### 14.3 回归验证
- `xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -sdk iphonesimulator -configuration Debug build` 通过。

---

## 15. 2026-04-01 Dynamic Island 三次微调（左侧图标过大）

### 15.1 现象
- expanded 态左侧图标视觉权重过高，且任务类型文本在窄宽度下出现竖排挤压，干扰标题阅读。

### 15.2 调整
- `IslandExpandedLeading` 改为仅保留小图标：
  - 外圈从 `30x30` 缩到 `22x22`；
  - 图标从 `12` 缩到 `10`；
  - 移除 leading 区文本，仅保留无障碍标签。
- `IslandExpandedCenter` 的标题增加 `maxWidth + leading 对齐`，避免首行视觉偏移。

### 15.3 验证
- `xcodebuild -project Weekyii.xcodeproj -scheme Weekyii -sdk iphonesimulator -configuration Debug build` 通过。
