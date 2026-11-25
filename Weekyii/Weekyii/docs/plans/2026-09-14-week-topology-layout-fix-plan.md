# Week 任务结构树（拓扑图）绘制修复计划

**日期**：2026-09-14
**范围**：`Features/Week/WeekTopology.swift`、`Features/Week/WeekTopologyView.swift`、`Features/Week/WeekOverviewView.swift`、`Tests/ModelTests.swift`、`WeekyiiUITests/DraftReorderUITests.swift`

**Goal:** 修掉拓扑图在「节点互相压叠」和「缩放层级不可达」两类缺陷，并把这些几何约束变成可回归测试的不变量，而不是留在视图注释里的承诺。

**Architecture:** 保持现有四段式管线不变（Snapshot → Layout → Canvas 连线 / SwiftUI 按钮 → Transform）。把布局常量从 `WeekTopologyView` 里提到 `WeekTopology.swift` 的度量类型中，让「节点尺寸」和「坐标间距」用同一组常量推导，从根上消除「写死的间距配不上写死的卡片宽度」这类问题。

**Tech Stack:** SwiftUI、Canvas、XCTest、Xcode/iOS Simulator。

---

## 0. 问题清单（含实测证据）

以下数值均由复刻 `WeekTopologyLayout` 的脚本算出（7 天整周，`contentBounds.width = 1112`，根节点 `x = 556`，日期 `x = 100/252/404/556/708/860/1012`）。

| 编号 | 现象 | 实测证据 | 根因 |
|---|---|---|---|
| **P0** | 主干横杆只覆盖右半侧，左侧日期节点的竖线顶端悬空 | 横杆区间 `[556, 1012]`，只覆盖 day 3–6；day 0/1/2（x=100/252/404）无横杆 | `drawConnections` 里横杆从 `rootPoint.x` 画到 `lastDayPoint.x`，而 `rootPoint.x = contentBounds.midX`，天然落在日期串中间 |
| **P1** | 任务第 2 行压到下一组节点 | 组带固定 88pt 间距（292→380→468），任务行距 42、首行偏移 54 → 第 2 行 `y = 组Y+96`，**重叠 26pt**。触发条件：某天某类任务数 ≥ 4 | `groupY` 是写死字典，任务行数却是变量 |
| **P2** | 相邻日期的任务卡水平压叠 | 相邻两日任务列中心最小距 **40pt**，任务卡宽 **84pt** → **重叠 44pt**。同日 3 列（距 96）不重叠 | 列偏移固定 ±96、日间距 152，`152 − 96 − 96 = −40` 为负 |
| **P3** | 紧凑卡片里「缩放看细节」不可用 | 画布宽 321 → `fitScale 0.267`；`viewport.scale` 顶到上限 3.2 时**有效缩放仅 0.855**，任务列仍重叠 2pt。全屏 `fitScale 0.716`，scale 1.5 时有效 1.074 已可读 | 语义层级阈值比较的是 `viewport.scale`（相对值），而决定「看得清吗」的是 `fitScale × scale`（有效值） |
| **P4** | overview 层日期节点首尾相贴 | 屏宽 393 时间距 40.6pt vs compact 节点宽 42pt（重叠 1.4pt）；屏宽 375 时间距 38.1pt（重叠 3.9pt） | 同上：节点尺寸不随 `fitScale` 缩放 |
| **P5** | 轻点日期后水平居中只是近似 | `focus()` 用 `approximateWidth`（写死 800/330）反算 `fitScale`，且未减 `leadingInset` | 与 `WeekTopologyTransform.point()` 的公式不一致 |
| **P6** | 拖拽/缩放时重复重建快照与布局 | `snapshot` / `layout` 是 computed property，`topologyCanvas` 内 `layout` 被访问 2 次、`inspector` 多次访问 `snapshot` | 每次 `body` 求值重建字典 |

**P2 / P3 / P4 是同一个根因**：`WeekTopologyTransform` 只映射坐标、不缩放节点，于是「有效缩放 < 1」时节点必然互相压叠。因此 P2 无法靠调几何单独修好——必须让有效缩放能进入可读区间。

---

## 1. 批次一：纯几何 bug（低风险，先落地）

### Task 1.1 修复主干横杆覆盖范围（P0）

**Files:** `Features/Week/WeekTopologyView.swift`

**Step 1:** 把 `drawConnections` 里的「一根折线」拆成「竖直主干 + 横跨全周的横杆」。当前写法是一条折线 `root → (root.x, branchY) → (lastDay.x, branchY)`，无法表达「从最左到最右」。

**Step 2:** 横杆起点改为 `min(rootPoint.x, firstDayPoint.x)`，终点改为 `max(rootPoint.x, lastDayPoint.x)`：

```swift
let branchY = (rootPoint.y + firstDayPoint.y) / 2

var trunk = Path()
trunk.move(to: transform.point(rootPoint))
trunk.addLine(to: transform.point(CGPoint(x: rootPoint.x, y: branchY)))

var rail = Path()
rail.move(to: transform.point(CGPoint(x: min(rootPoint.x, firstDayPoint.x), y: branchY)))
rail.addLine(to: transform.point(CGPoint(x: max(rootPoint.x, lastDayPoint.x), y: branchY)))

for path in [trunk, rail] {
    context.stroke(
        path,
        with: .color(Color.textPrimary.opacity(0.28)),
        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
    )
}
```

**Step 3:** 检查退化情形：`n = 1` 时 `root.x == day.x == 100`，横杆退化为零长线段，主干仍从 y=24 落到 y=118，视觉正常；`n = 2/3` 时根节点落在日期串内部，`min/max` 保证横杆完整覆盖。

### Task 1.2 把横杆几何提到可测类型（让 Task 1.1 能被回归测试守住）

**Files:** `Features/Week/WeekTopology.swift`

**Step 1:** 给 `WeekTopologyLayout` 补两个字段，让它能自证几何：

```swift
struct WeekTopologyLayout: Equatable {
    let positions: [String: CGPoint]
    let contentBounds: CGRect
    let rootNodeID: String
    let dayIDs: [String]        // 按日期升序
}

struct WeekTopologyRootRail: Equatable {
    let trunkX: CGFloat
    let trunkTopY: CGFloat
    let trunkBottomY: CGFloat
    let railY: CGFloat
    let railStartX: CGFloat
    let railEndX: CGFloat
}

extension WeekTopologyLayout {
    var rootRail: WeekTopologyRootRail? {
        guard let root = positions[rootNodeID],
              let first = dayIDs.first.flatMap({ positions[$0] }),
              let last = dayIDs.last.flatMap({ positions[$0] }) else { return nil }
        let branchY = (root.y + first.y) / 2
        return WeekTopologyRootRail(
            trunkX: root.x,
            trunkTopY: root.y,
            trunkBottomY: branchY,
            railY: branchY,
            railStartX: min(root.x, first.x),
            railEndX: max(root.x, last.x)
        )
    }
}
```

**Step 2:** `drawConnections` 改为消费 `layout.rootRail`，不再自己算 `branchY`。这样「横杆覆盖全周」成为 `WeekTopologyLayout` 的属性，而不是视图里的临时算术。

**Step 3:** 同步更新 `WeekTopologyLayout.init(snapshot:)`，写入新增的 `rootNodeID = snapshot.rootNodeID` 与 `dayIDs = snapshot.days.map(\.id)`。注意 `Equatable` 会自动带上新字段，既有测试里用到的相等比较不受影响。

**理由**（沿用主题系统那轮的教训）：把派生几何从 View 提到可测类型，否则「横杆覆盖所有日期」只是注释里的承诺，没有回归测试能守住。

### Task 1.3 修复组带间距随任务行数自适应（P1）

**Files:** `Features/Week/WeekTopology.swift`

**Step 1:** 新增度量类型，让「卡片高度」和「坐标间距」来自同一组常量（当前卡片高度只写在 View 里，布局侧完全不知道）：

```swift
enum WeekTopologyMetrics {
    static let horizontalInset: CGFloat = 100
    static let daySpacing: CGFloat = 152
    static let rootY: CGFloat = 24
    static let dayY: CGFloat = 212
    static let groupCardHeight: CGFloat = 38
    static let taskCardWidth: CGFloat = 84
    static let taskCardHeight: CGFloat = 30
    static let taskColumnSpacing: CGFloat = 96
    static let taskVerticalSpacing: CGFloat = 42
    static let taskFirstRowOffset: CGFloat = 54
    static let bandGap: CGFloat = 24          // 任务末行与下一组之间的净空
    static let bottomInset: CGFloat = 72
}
```

**Step 2:** 组带 Y 由「跨所有日期的最大行数」递推得出，不再写死 292/380/468：

```swift
let rowsByKind: [WeekTopologyResultKind: Int] = Dictionary(
    uniqueKeysWithValues: WeekTopologyResultKind.allCases.map { kind in
        let maxCount = snapshot.days.map { $0.count(for: kind) }.max() ?? 0
        return (kind, (maxCount + 2) / 3)      // 3 列网格，向上取整
    }
)

var groupY: [WeekTopologyResultKind: CGFloat] = [:]
var cursor = WeekTopologyMetrics.dayY + 80
for kind in WeekTopologyResultKind.allCases {
    guard let rows = rowsByKind[kind], rows > 0 else { continue }
    groupY[kind] = cursor
    let lastTaskY = cursor + WeekTopologyMetrics.taskFirstRowOffset
        + CGFloat(rows - 1) * WeekTopologyMetrics.taskVerticalSpacing
    cursor = lastTaskY
        + WeekTopologyMetrics.taskCardHeight / 2
        + WeekTopologyMetrics.bandGap
        + WeekTopologyMetrics.groupCardHeight / 2
}
```

**Step 3:** 任务 Y 改用 `groupY[kind]` 推导，替换现有 `baseY + 54 + row * 42` 的裸数字。原来的 `let baseY = groupY[kind]` 已经带了 `guard let`，把字典取值收进同一个 `guard` 即可，不要引入强制解包：

```swift
for kind in WeekTopologyResultKind.allCases {
    guard day.count(for: kind) > 0,
          let baseY = groupY[kind] else { continue }
    positions[day.groupID(for: kind)] = CGPoint(x: x, y: baseY)
    maximumY = max(maximumY, baseY)

    for (taskIndex, nodeID) in nodeIDs.enumerated() {
        let column = taskIndex % 3
        let row = taskIndex / 3
        let spread = CGFloat(column - 1) * WeekTopologyMetrics.taskColumnSpacing
        let y = baseY + WeekTopologyMetrics.taskFirstRowOffset
            + CGFloat(row) * WeekTopologyMetrics.taskVerticalSpacing
        positions[nodeID] = CGPoint(x: x + spread, y: y)
        maximumY = max(maximumY, y)
    }
}
```

**Step 4:** `contentBounds.height` 继续用 `maximumY + bottomInset`，无需改动（它已经会跟随任务行增长）。

**验证要点：** 单行任务时组带间距从 88 变为 112（略松，可接受）；某类完全为空时该带不占位，后续带整体上移。

### Task 1.4 收窄 compact 日期节点（P4）

**Files:** `Features/Week/WeekTopologyView.swift`

**Step 1:** `dayButton` 的 compact 外框 `42 → 34`，`WeekTopologyDayNode` 的 compact 节点框 `44 → 36`、`cardWidth 34 → 28`、`cardHeight 28 → 24`。

**Step 2:** 核对文案：compact 分支渲染 `"15"` + `"·3"`，9px 约 22pt，28pt 卡片可容纳。若实机偏挤，改为只显示日号、把总数移到无障碍标签（`dayAccessibilityLabel` 已包含完整统计，不会丢信息）。

**Step 3:** 小屏边界：屏宽 375 时屏幕间距 38.1pt，节点 34pt → 净空 4.1pt；屏宽 393 时净空 6.6pt。均可接受。

---

## 2. 批次二：让「有效缩放」真正可用（P3，核心）

> 这是本计划里唯一需要你先拍板的部分，见 §4 决策点。

### Task 2.1 语义层级改为基于有效缩放

**Files:** `Features/Week/WeekTopology.swift`

**Step 1:** 把 `WeekTopologySemanticLevel` 的入口从 `init(scale:)` 改为 `init(effectiveScale:)`，阈值 1.5 / 2.2 保持不变，但比较对象变成 `fitScale × scale`。

**Step 2:** `WeekTopologyViewportState` 不再把 `fitScale` 存成状态（画布尺寸由几何决定，状态里存会引入时序问题），改为按需传入：

```swift
struct WeekTopologyViewportState: Equatable {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 3.2
    /// 有效缩放至少要能到达 tasks 档，留 0.4 余量
    static let tasksReachEffectiveScale: CGFloat = 2.6

    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var selectedNodeID: String?

    func effectiveScale(fitScale: CGFloat) -> CGFloat { fitScale * scale }

    func semanticLevel(fitScale: CGFloat) -> WeekTopologySemanticLevel {
        WeekTopologySemanticLevel(effectiveScale: effectiveScale(fitScale: fitScale))
    }

    /// 上限按 fitScale 反算，保证紧凑卡片也能缩放到可读区间
    func clampedScale(_ proposed: CGFloat, fitScale: CGFloat) -> CGFloat {
        let ceiling = max(
            Self.maximumScale,
            Self.tasksReachEffectiveScale / max(fitScale, 0.1)
        )
        return min(max(proposed, Self.minimumScale), ceiling)
    }
}
```

**关键约束：** 不能在 `body` 求值过程中写 `@Binding`。因此 `fitScale` 必须由视图在 `GeometryReader` 内算出后**沿参数传递**给 `dayButton` / 手势 / `drawConnections`，而不是回写到 `viewport`。手势闭包拿不到 `proxy.size`，用一个 `@State private var lastFitScale: CGFloat = 1` 配合 `.onChange(of: proxy.size)` 同步。

**Step 3:** 更新所有读取点：
- `topologyCanvas` 里 `viewport.semanticLevel != .overview` → `viewport.semanticLevel(fitScale: fitScale) != .overview`
- `drawConnections` 两处 `viewport.semanticLevel` 同样改造
- `zoomGesture` 里 `viewport.applyScale(...)` → `viewport.scale = viewport.clampedScale(..., fitScale: lastFitScale)`
- `rootButton` / `dayButton` 的 `isCompact` 判定同样改用带 `fitScale` 的版本

### Task 2.2 让 `focus(day:)` 按有效缩放定目标并精确居中（P3 + P5）

**Files:** `Features/Week/WeekTopologyView.swift`

**Step 1:** 目标缩放改为按有效缩放反算，替换写死的 2.25：

```swift
let targetScale = WeekTopologyViewportState.tasksReachEffectiveScale / max(fitScale, 0.1)
viewport.scale = viewport.clampedScale(max(viewport.scale, targetScale), fitScale: fitScale)
```

**Step 2:** 居中改为「先缩放、再用新变换算偏移增量」，彻底去掉 `approximateWidth` 的 800/330 猜测：

```swift
let updated = WeekTopologyTransform(
    viewportSize: size,
    contentBounds: layout.contentBounds,
    viewport: viewport
)
let point = updated.point(position)          // offset 尚未修正
viewport.offset = CGSize(
    width: viewport.offset.width + (size.width / 2 - point.x),
    height: viewport.offset.height + (size.height * 0.42 - point.y)
)
```

**Step 3:** `dayButton` 与 `focus` 需要新增 `fitScale` / `size` / `transform` 参数，签名相应调整。

**Step 4:** `WeekOverviewContentView.reconcileTopologyState` 里的 `topologyViewport.reset()` 保持语义不变（scale 回 1，即回到 overview 档）。

### Task 2.3 可选加固：任务卡宽度

**Files:** `Features/Week/WeekTopologyView.swift`

有效缩放达到 2.2 时，相邻日期任务列中心距为 `40 × 2.2 = 88pt`，任务卡 84pt → 净空仅 **4pt**。若实机觉得贴太紧，把 `WeekTopologyMetrics.taskCardWidth` 从 84 收到 **76**（净空升到 12pt），`taskColumnSpacing` 同步从 96 收到 88。**这一步是可选的**，不做也能通过「不重叠」的断言。

---

## 3. 批次三：回归防护

### Task 3.1 补充模型/布局单测

**Files:** `Tests/ModelTests.swift`

**Step 1:** 横杆覆盖（守住 P0）：

```swift
func test_weekTopologyLayout_rootRailSpansEveryDayColumn() throws {
    let week = WeekCalculator().makeWeek(for: makeDate(2026, 6, 15), status: .present)
    let snapshot = WeekTopologySnapshot(week: week)
    let layout = WeekTopologyLayout(snapshot: snapshot)
    let rail = try XCTUnwrap(layout.rootRail)

    let dayPoints = try snapshot.days.map { try XCTUnwrap(layout.positions[$0.id]) }
    let minDayX = try XCTUnwrap(dayPoints.map(\.x).min())
    let maxDayX = try XCTUnwrap(dayPoints.map(\.x).max())
    let minDayY = try XCTUnwrap(dayPoints.map(\.y).min())

    XCTAssertLessThanOrEqual(rail.railStartX, minDayX, "横杆没有覆盖到最左一天")
    XCTAssertGreaterThanOrEqual(rail.railEndX, maxDayX, "横杆没有覆盖到最右一天")
    XCTAssertGreaterThan(rail.railY, rail.trunkTopY)
    XCTAssertLessThan(rail.railY, minDayY)
}
```

**Step 2:** 组带不重叠（守住 P1）——构造某天 7 个剩余任务 + 4 个完成任务，断言：

```swift
func test_weekTopologyLayout_taskRowsNeverCollideWithNextGroupBand() throws {
    // 构造 1 天：7 个 remaining（3 行）、4 个 completed（2 行）、expiredCount = 3
    let day = DayModel(dayId: start.dayId, date: start, status: .execute)
    for order in 1...7 { day.tasks.append(TaskItem(title: "R\(order)", order: order, zone: .focus)) }
    for order in 8...11 {
        let done = TaskItem(title: "C\(order)", order: order, zone: .complete)
        done.completedOrder = order - 7
        day.tasks.append(done)
    }
    day.expiredCount = 3
    week.days.append(day)

    let snapshot = WeekTopologySnapshot(week: week)
    let layout = WeekTopologyLayout(snapshot: snapshot)
    let metrics = WeekTopologyMetrics.self
    let topologyDay = try XCTUnwrap(snapshot.days.first)

    func assertNoCollision(_ taskIDs: [String], above groupID: String) throws {
        let group = try XCTUnwrap(layout.positions[groupID])
        let groupTop = group.y - metrics.groupCardHeight / 2
        for id in taskIDs {
            let point = try XCTUnwrap(layout.positions[id])
            XCTAssertLessThan(
                point.y + metrics.taskCardHeight / 2, groupTop,
                "任务 \(id) 的底边压到了 \(groupID) 的顶边"
            )
        }
    }

    try assertNoCollision(
        topologyDay.remainingTasks.map(\.id),
        above: topologyDay.groupID(for: .completed)
    )
    try assertNoCollision(
        topologyDay.completedTasks.map(\.id),
        above: topologyDay.groupID(for: .forgotten)
    )
}
```

**注意：** 这条用例在修复前必然失败（重叠 26pt），是先写失败测试再改布局的顺序。

**Step 3:** 相邻日期任务列不重叠（守住 P2）——断言任意两个任务节点的水平中心距 ≥ `taskCardWidth`：

```swift
func test_weekTopologyLayout_taskNodesFromAdjacentDaysDoNotOverlapHorizontally() throws {
    // ... 构造 7 天，每天 3 个 remaining 任务
    // 对同一行内的任务节点两两断言 |Δx| >= WeekTopologyMetrics.taskCardWidth
}
```

**Step 4:** 语义层级改为按有效缩放后，更新既有用例 `test_weekTopologySemanticLevel_usesStableScaleThresholds` 的调用签名，并补一条紧凑卡片场景：

```swift
func test_weekTopologySemanticLevel_reachableAtCompactCardFitScale() {
    let compactFit: CGFloat = 0.267
    var viewport = WeekTopologyViewportState()
    viewport.scale = viewport.clampedScale(100, fitScale: compactFit)
    XCTAssertEqual(viewport.semanticLevel(fitScale: compactFit), .tasks)
    XCTAssertGreaterThanOrEqual(viewport.effectiveScale(fitScale: compactFit), 2.2)
}
```

**Step 5:** 运行：

```bash
xcodebuild -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WeekyiiTests/ModelTests test
```

### Task 3.2 UI 测试与截图验证

**Files:** `WeekyiiUITests/DraftReorderUITests.swift`

**Step 1:** 现有 `testWeekOverviewSupportsCardsStripsAndCollapsedModes`（549–576）依赖 `weekTopologyDay_0` / `weekTopologyDay_6` / `weekTopologyInspector` / `weekTopologyFullscreen*`，这些标识符本计划**不改**，用例应保持通过。

**Step 2:** 补一条「紧凑卡片可缩放到任务层」的用例：进入本周页 → 对拓扑画布做 pinch 放大 → 断言出现任务节点（需要给 `taskButton` 补 `accessibilityIdentifier`，如 `weekTopologyTask_\(index)`）。

**Step 3:** 截图验证（沿用主题系统那轮的做法）：分别抓取
- overview 层（scale=1）——确认 7 个日期节点之间有空隙、横杆横跨全周
- 某天 7 个剩余任务的周——确认任务第 2 行不再压到「完成」组
- 全屏 tasks 档——确认任务卡不重叠

**注意：** 模拟器改 `UserDefaults` 必须走 `uninstall → install → defaults write → launch`；跳通知弹窗用 XCUITest 的 `addUIInterruptionMonitor`。

---

## 4. 需要你决策的点

| # | 决策 | 选项 | 我的建议 |
|---|---|---|---|
| D1 | 紧凑卡片要不要保留「就地缩放到任务层」？ | **A**：保留，把语义阈值/缩放上限改为基于有效缩放（Task 2.1/2.2）<br>**B**：紧凑卡片锁 overview 档，细节交给全屏<br>**C**：紧凑卡片不追求「一眼看全 7 天」，`fitScale` 设下限（约 4 天可读），靠横向拖动看其余日期 | **A**。理由见下方说明 |
| D2 | 任务卡是否收窄 84 → 76？ | 收窄 / 不动 | **不动**。4pt 净空虽紧但不重叠，先看实机截图再决定 |
| D3 | compact 日期节点 42 → 34 是否接受？ | 接受 / 保留 42 并容忍首尾相贴 | **接受**，若文案偏挤则去掉 `·N` 后缀（统计信息在无障碍标签和 inspector 里都有） |
| D4 | 组带为空时是否占位？ | 不占位（Task 1.3 的写法）/ 保留空位让三条带永远对齐 | **不占位**。空带占位会浪费高度并进一步压缩 `fitScale` |

**关于 D1 的取舍说明：**

三个方案都必须面对同一个物理事实——紧凑画布只有约 **321 × 220pt**，而 7 天 × 3 层的树在「不缩放节点尺寸」的前提下装不进去。三者代价各不相同：

| 方案 | overview 观感 | 进入 tasks 档需要的 pinch | 代价 |
|---|---|---|---|
| A | 7 天全可见，节点净空 6.6pt（靠 Task 1.4） | 约 **9.7×**（`2.6 / 0.267`） | 手动 pinch 到任务层很费力 |
| B | 同上 | 不可达（只能进全屏） | 砍掉「轻点展开当天任务」这个已承诺的交互 |
| C | 约 4.3 天可见，节点净空约 40pt | 约 **5.3×** | 「全局视图」按钮不再是字面意义的全局 |

选 **A** 的关键理由是：`focus(day:)` 才是进入任务层的主路径，**轻点日期即可直接跳到有效缩放 2.6**（Task 2.2），不需要用户手动 pinch 9.7 倍。手动 pinch 只是次要的微调手段，够不到 tasks 档并不影响主流程。C 虽然观感最好，但会让「全局视图」按钮名不副实，属于需要重命名文案的连锁改动。

---

## 5. 执行顺序

1. Task 1.1 + 1.2（横杆 + 可测几何）→ 跑 ModelTests
2. Task 1.3（组带自适应）→ 补 3.1 Step 2 的用例
3. Task 1.4（compact 节点收窄）
4. Task 2.1 + 2.2（有效缩放，需 D1 拍板）→ 补 3.1 Step 3/4 的用例
5. Task 3.2（UI 测试 + 截图）
6. Task 2.3（可选加固，视截图决定）

批次一（1.1–1.4）互相独立，可单独交付；批次二（2.x）依赖 D1 的决定。

---

## 6. 不在本次范围

- **任务层 3 列 → 2 列**：在有效缩放修好之后已无必要，属于体验偏好而非缺陷。
- **`WeekTopologyLayout` 缓存 / 增量重建（P6）**：原计划建议单独一次提交，实际已在同轮落地，见 §7.4。
- **连线视觉（`drawTreeEdge` 的圆角肘形、层级配色）**：非缺陷。
- **`WeekTopologyDayNode` 的 `pulse` 动画在 `focusTask` 消失后未复位**：影响极小，暂不处理。

---

## 7. 执行记录（2026-09-14 落地）

批次一、二、三全部落地，P6 也已补上。单测 **169 条全绿**（`ModelTests` 107 + `StateMachineTests` 40 + `NotificationServiceTests` 12 + `SuspendedTaskLifecycleServiceTests` 6 + `WeekCalculatorTests` 4），UI 测试 `testWeekOverviewSupportsCardsStripsAndCollapsedModes`、`testWeekTopologyTaskNodeShowsTaskInspectorNotForgotten` 均通过。截图验证抓出计划本身的两处缺陷，已在同轮修掉。

### 7.1 计划缺陷一：Task 2.2 的目标缩放对紧凑卡片不成立

Task 2.2 让 `focus(day:)` 把有效缩放顶到 2.6，理由是「轻点日期即可看到任务层」。实测（复刻几何脚本）：

| 画布 | fitScale | scale | 有效缩放 | 日期节点 y | 组节点 y | 任务行 y |
|---|---|---|---|---|---|---|
| 紧凑卡片 338×220 | 0.282 | 9.21 | 2.60 | 517–585 | **740–778（画布外）** | **885–915（画布外）** |
| 全屏 460×800 | 0.392 | 6.63 | 2.60 | 517–585 | 740–778 | 885–915 |

日期节点到组节点的内容距离是 80，有效缩放 2.6 时渲染成 **208pt**——比紧凑画布整高（220pt）还接近。所以轻点日期后画布上只剩一个孤零零的日期节点，任务层全在画布下方。Task 2.2 把「进入任务层」当成了终点，但它其实只是起点：还得把任务层**框进画布**。

**修法**：`focus(day:)` 改为对「这天的子树包围盒」取景（新增 `WeekTopologyLayout.subtreeBounds(for:)`，由每个节点自身的卡片尺寸求并集；用最大节点统一外扩会让盒子虚高 19pt，反而把子树顶出画布）。缩放取「刚好装下」与「任务层下限」中的较大者，装不下时把子树顶部对齐上边距、其余靠拖动。

### 7.2 计划缺陷二：三列任务网格让 P2 无法修复，也让任务层不可达

§6 把「任务层 3 列 → 2 列」列为体验偏好。实测证明它是缺陷：

- 一天的任务行宽 = `2 × 96 + 84 = 276`，而日间距只有 `152`。相邻日期的外侧列中心距 = `|152 − 2×96| = 40`，卡片 84 宽 → **必然重叠 44pt**。
- 要让 3 列互不压叠，`taskColumnSpacing` 需 ≤ 34，但列距小于卡宽 84，同一天的 3 列又会互相压叠。**无解**：3 列与 152 的日间距在几何上不相容。
- 顺带把任务层门槛推到 `90 / 40 = 2.25`，这也是原实现里「任务层够不到」的一半原因。

**修法**：`taskColumnCount` 3 → 1。任务在日期节点下方纵向排列，行宽 84 远小于日间距 152，相邻日期在任何缩放下都不会压叠。这是**一行常量改动**，也是唯一能结构性消除 P2 的改法。代价是全屏任务层从三列扇形变成纵向列表——更贴近「结构树」的语义，但与改动前的观感不同，**如需回退只需把该常量改回 3**。

### 7.3 顺带修正：层级阈值改为几何推导

原实现（含本计划 §2）把阈值写成手写倍数（1.5 / 2.2 / 2.6）。改成由节点尺寸与间距推导：

```
groupClearEffectiveScale = (groupCardWidth + minimumNodeGap) / daySpacing          // 0.50
taskClearEffectiveScale  = max((taskCardHeight + minimumNodeGap) / taskVerticalSpacing,   // 0.857
                               (taskCardWidth  + minimumNodeGap) / taskPitch)             // 0.592
```

`taskPitch` 是「同一层里两张任务卡的最小水平中心距」，单列时等于 `daySpacing`。这组推导对 3 列布局会还原出 `90 / 40 = 2.25`，正好印证原阈值 2.2 的来源；换成单列后降到 0.857，于是紧凑卡片里轻点日期、全屏里一次 2.2 倍 pinch 都能进入任务层。同时把缩放上限从 `max(3.2, 2.6/fitScale)` 改为「渲染尺度上限 1.8」——卡片尺寸不随缩放变化，超过 1.8 只是拉开空白。

### 7.4 P6 落地：快照与布局只解析一次

`snapshot` / `layout` 原是 computed property，一次 `body` 求值里被反复重建。实测统计：

| 位置 | 原访问次数 | 说明 |
|---|---|---|
| `topologyCanvas` | 2 | 自带一次 `layout` 重建 |
| `rootButton` | 4 | 画布里明明已有局部快照，方法里却重新读属性 |
| `inspector` | 6 | 4 处 `days.first(where:)` 线性扫描 + `weekInspector` 的 3 个计数 |
| `WeekOverviewView` body | 1 | 仅为了 `hasContent` 就建了整个快照 |

**改法：**

- `WeekTopologyView.body` 顶部解析一次 `snapshot` / `layout`，沿参数传给 `topologyCanvas(size:snapshot:layout:)`、`rootButton(semanticLevel:snapshot:)`、`inspector(snapshot:)`。`layout` 这个 computed property 随之删除。
- `inspector` 拆出 `daySubtreeInspector(nodeID:day:snapshot:)`，把「找到这个节点所属的那一天」从 4 次扫描收敛成 1 次。
- 新增 `WeekTopologySnapshot.hasContent(in:)`：只看模型的轻量探针，替代 `WeekOverviewView` body 里为了 `hasContent` 而建的完整快照。
- `reconcileTopologyState` 把 `guard let selectedNodeID` 提到建快照之前——没有选中节点时无事可做。

**过程中差点踩的坑（已被 UI 测试守住）：** 收敛 `inspector` 分支时，若把 `taskInspector` 放到 `forgottenInspector` 之后，点任务卡会显示「任务已遗忘」。任务节点确实属于某一天（日查找成功），但它既不等于日期节点 id 也不匹配任何分组 id —— 正是这一点让它能落到 `taskInspector`。**分支顺序不能动。**

新增 `testWeekTopologyTaskNodeShowsTaskInspectorNotForgotten`（UI）守住它：把分支顺序换回错误版本后，该用例的两条断言都会失败（已实测），改回即通过。

> 注：`.accessibilityIdentifier("weekTopologyInspector")` 会传播到 inspector 的每个子元素，所以该 id 不唯一，`inspector.staticTexts[...]` 这类作用域查询不可靠。用例改用只在单一分支出现的文案断言：`查看任务详情` 只属于任务 inspector，`任务已遗忘` 只属于遗忘 inspector。

### 7.5 未落地 / 待观察

- **`groupTopOffset` 68 → 80**：为让「日期→组」这一层在组层门槛下真的分开（见 §7.8）。overview 层不渲染组节点，观感无变化。
- **Task 2.3（任务卡 84 → 76）**：仍未做。单列布局下净空已足够（`152 × 0.857 − 84 = 46pt`），无需收窄。
- **一天任务很多（≥4）时**：子树装不下紧凑画布，取景退到任务层下限并顶部对齐，最后几行需要拖动查看。这是画布高度决定的物理限制，不是缺陷。
- **组节点 / 任务卡 / 遗忘节点没有 accessibility identifier**：目前只有 root / day / fullscreen / inspector 有。若后续要为这些节点写用例，建议按同一命名约定补齐（`weekTopologyGroup_*` / `weekTopologyTask_*`），避免用文案匹配。

### 7.6 验证截图

归档在 `docs/assets/week-topology-2026-09-14/`：

| 文件 | 状态 | 确认内容 |
|---|---|---|
| `01-overview.png` | 紧凑卡片 scale=1 | 横杆从 14日 横跨到 20日；7 个日期节点之间有空隙 |
| `02-focused-day0.png` | 轻点 day 0 后 | 日期节点 →「剩余 2 项」→ 两张任务卡，全部落在画布内且不重叠 |
| `03-fullscreen-overview.png` | 全屏 scale=1 | 回到 overview 档，观感与紧凑卡片一致 |
| `04-fullscreen-tasks.png` | 全屏 pinch 2.4× | tasks 档三层清晰，任务卡纵向排列、不重叠 |
| `05-task-inspector.png` | 轻点任务卡后 | 任务卡高亮，inspector 显示「Draft Task A / 常规 · 草稿」+ 详情入口（§7.4 分支顺序） |

### 7.7 环境注意（复现构建用）

本机 Xcode 的宏插件服务在受限沙箱里会失败：`sandbox-exec: sandbox_apply: Operation not permitted`，表现为 `swift-plugin-server produced malformed response` / `'SwiftDataMacros.PersistentModelMacro' could not be found`。这不是代码问题。命令行构建时补上：

```bash
xcodebuild ... OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' test
```

`-disable-sandbox` 是编译器「不再用沙箱执行子进程」的开关。只在命令行传，不要写进工程文件。

### 7.8 连线穿框（用户截图复核后追加）

用户拿截图质问「这个线条和框的关系对吗？？？？」——一根竖线笔直穿过日期节点、组节点和两张任务卡，把整棵子树串成糖葫芦。§7.6 的截图只核对了「节点之间不压叠」，**没有核对「线终点与卡片边界的关系」**，所以漏掉了。

用探针脚本在 5 个缩放档位（0.282 / 0.60 / 0.857 / 0.871 / 1.8）量化后，五类连线**每一类**都画进了卡片里；另外组层档位上日期节点还和组节点重叠 12pt，overview 档位根节点被上边缘裁掉 7pt。

**根因（两个独立缺陷）：**

1. **连线按中心点画**：`drawConnections` 把线从一张卡的中心画到另一张卡的中心，中间自然横穿两张卡。单列任务布局下同一棵子树的所有节点共用一个 x，于是这条线退化成一竖到底的直线，直接穿透整列。
2. **门槛只保证卡片不压叠，不保证有地方画线**：门槛用的是 `upper/2 + lower/2 + minimumNodeGap`，而连线需要 `upper/2 + lower/2 + 2 × edgeGap`。当 `minimumNodeGap = 6 < 2 × edgeGap = 8` 时，**恰好在线条刚能读出来的那个尺度上，每条边都被裁成零长度**——树在最该成形的时候散成一张张孤立的卡片。

**修法：**

- 新增 `WeekTopologyEdgeSpan`（`WeekTopology.swift`）：把「一条边从哪儿画到哪儿」抽成可断言的值类型。`startY = 上卡中心 + 上卡半高 + edgeGap`，`endY = 下卡中心 − 下卡半高 − edgeGap`，`jogY` 取中点；空间不足时返回 `nil`，**宁可不画也不穿框**。
- `drawConnections` / `drawTreeEdge` 改为按 `WeekTopologyEdgeSpan` 绘制：主干从根卡下边界出发，日期支线止于日期卡上边界，每条肘形折线两端各让出 `edgeGap`。卡片尺寸随语义层变化（overview 用紧凑尺寸，其余用展开尺寸），所以让位量按当前档位取。
- **`minimumNodeGap` 改为推导值**，这是关键一步：

  ```swift
  static let edgeGap: CGFloat = 3
  static let minimumConnectorLength: CGFloat = 4
  static var minimumNodeGap: CGFloat { 2 * edgeGap + minimumConnectorLength }   // = 10
  ```

  门槛和连线问的是**同一个间隙**。把连线的让位量折进门槛，两个条件就在构造上恒等——「这一层画得出来」和「这一层的边画得出来」不再可能打架。写死一个 6 正是它们打架的原因。
- `taskVerticalSpacing` 46 → 48、`groupTopOffset` 68 → 80、`verticalInset` 改为 `rootNodeExpandedHeight/2 + canvasVerticalPadding`（= 35，修 overview 裁顶）。

**预算的两面性**（`taskVerticalSpacing` 的注释里记了推导）：卡片尺寸是屏幕空间的常量，所以同一组间距同时给出**下界**（门槛，低了卡片压叠）和**上界**（取景，高了子树装不进紧凑画布）。加宽行距会抬高子树高度、但让门槛掉得更快，净效果是**余量变大**——所以「给连线腾地方」要加宽而不是收紧行距。

当前取值（紧凑画布 321×220）：

| 量 | 值 |
|---|---|
| `groupClearEffectiveScale` | 0.7875（日期→组 绑定） |
| `taskClearEffectiveScale` | 0.8462（组→任务 绑定） |
| 取景上限 `fitted` | 0.8559 |
| 余量 | +0.0097 |
| 门槛处的净空 | 日期→组 14.7pt、组→任务 10.0pt、任务→任务 10.6pt（要求 ≥ 10） |
| 门槛处的可见线长 | 8.7 / 4.0 / 4.6pt（要求 ≥ 4） |

余量只有 1%，属于偏紧。数值扫描显示 `T=96 / F=64 / S=58` 能把余量拉到 4.4%，但那会明显改变用户已过目的纵向节奏，所以本轮**只做最小改动**。取景尺度下的渲染间距几乎与这些常量无关（`fitted` 与子树高度成反比，两者抵消），所以真要放宽时观感代价很小。

**顺带修掉的一处「常量说谎」：** 日期节点视图里外框写死 `isCompact ? 36 : 30`，而 `WeekTopologyMetrics` 记的是 `34 / 32`——布局按 34×32 预留、视图实际画 36×30。视图改为从 metrics 读取，同时把 **metrics 的值改成 36 / 30**（是 metrics 记错了，不是视图画错了：按 34 宽，带计数的日期卡「14日 · 2」会折成两行并和自己的角标撞在一起，本轮实测踩到过）。根节点高度同样改为读 `rootNodeCompactHeight` / `rootNodeExpandedHeight`。核对过其余三类卡片——组卡 70×38、任务卡 84×30、遗忘卡 68×30——都与 metrics 一致，所以连线让位量对这些卡片是准确的。

**连线长度是几何预算的直接结果，不是调参能改善的。** 门槛处两张卡片的净空恒等于 `minimumNodeGap`，所以门槛处的可见线长恒等于 `minimumConnectorLength`（当前 4pt）。想让线更长只有两条路，代价都不小：

| 手段 | 代价 |
|---|---|
| 加大 `minimumConnectorLength` | 门槛随之抬高，必须同时加大 `T/F/S` 才装得进画布。数值扫描显示要做到 8.5pt 需 `T=104 / F=76 / S=68`（子树高度 +30%），余量反而掉到 0.5%，且任务层门槛从 0.85 降到 0.65 |
| 缩小卡片 | 任务卡 30 → 26、组卡 38 → 34 可让 `G` 放宽到 ~13（线长 ~7pt）并显著改善余量，但这是比调间距更大的观感改动 |

当前选择「最小改动」：只修正确性，不动用户已过目的纵向节奏。取景尺度（0.856）略高于门槛，所以实际看到的是 4.5–9.5pt 的线段，截图确认可读。

**新增测试（均已实测会在缺陷复现时失败）：**

| 用例 | 守住什么 |
|---|---|
| `test_weekTopologyEdgeSpan_stopsAtCardBorders` | 三类上下相邻卡片在门槛尺度下：连线端点必须落在卡片外侧，且**剩余可见线长 ≥ `minimumConnectorLength`**（只断言「非 nil」不够——中间一点不剩等于裁没了） |
| `test_weekTopologyEdgeSpan_returnsNilWhenCardsAreTooClose` | 空间不足时返回 nil，不画穿框线 |
| `test_weekTopologyFocus_everyEdgeStaysDrawableAtTheFramedScale` | 端到端：拿**真实布局**在取景尺度上走一遍日期→组→任务1→任务2，每条边都要画得出且不被裁没；同时断言子树仍装得进画布 |

「守卫会失败」实测：把 `minimumNodeGap` 改回写死的 6 后，`test_weekTopologyEdgeSpan_stopsAtCardBorders` 报出两条错误——`日期→组 在门槛尺度下连线被裁得看不见了`（2.54 < 4.0）与 `组→任务：两张卡片之间没有给连线留下任何空间`（nil）；改回推导式后 113 条全通过。

**仍未做的：** Task 2.3（任务卡 84 → 76）依然不需要——单列布局下横向净空 `152 × 0.8462 − 84 = 44.6pt` 富余。

**验证截图**（归档在 `docs/assets/week-topology-connectors-2026-09-14/`）：

| 文件 | 确认内容 |
|---|---|
| `00-compare-before-after.png` | 左：修复前，一根竖线从画布顶部一路穿过日期卡、组卡、两张任务卡；右：修复后，线断成四段，每段都止于卡片边界 |
| `01-overview.png` / `01-overview-zoom.png` | 根卡「W38 2」不再被上边缘裁掉（`verticalInset` = 35）；横杆横跨 7 天，每条日支线止于日期卡上方 |
| `02-focused-day.png` / `02-focused-day-zoom.png` | 用户截图里的那个场景：轻点 day 0 后整棵子树同屏，四段连线全在卡片之外 |
| `03-fullscreen.png` | 全屏（不同 `fitScale`）下同样干净 |

> **紧凑日期卡折行（同一轮内已修）：** 紧凑日期卡内容区固定 28pt 宽，带计数的日期会折成两行并和自己的角标挤在一起（「14 / 日 · 2」）。这是**既有**问题，已用上一轮归档截图比对确认修复前就存在。
>
> 根因查清楚了：`dayNumberFormatter` 用 `setLocalizedDateFormatFromTemplate("d")`，而在 `zh_CN` 下模板 `"d"` 解析出的是 **「14日」**（带「日」字，不是「14」）。所以内容实际是「14日」+「·2」≈ 30pt，塞进 28pt 必然折行；无计数的「15日」刚好放得下，这就是为什么只有当天那张卡看起来是坏的。
>
> 修法：给紧凑分支加 `.lineLimit(1)` + `.minimumScaleFactor(0.75)`。**这是构造性保证**——加了两行之后折行不再可能发生，比加断言更硬。代价是带计数时字号缩到约 8pt。两位数计数（「14日 · 99」≈ 36pt，需要 0.78）仍在 0.75 地板之上，不会触发截断。对照图见 `04-compact-day-row-compare.png`（顺带也能看出同一张图里连线从「穿进圆卡」变成「停在卡上方」）。

### 7.9 连线穿框并未修完：扇出画法（放大复核后追加）

§7.8 的修复不完整。把「剩余 2 项」下方区域放大 4 倍后可以看清：那条线穿过缝隙、**进入「Draft Task A」卡片内部**并继续向下。

**为什么 §7.8 没抓住：** `WeekTopologyEdgeSpan` 只保证一条线段的**两个端点**有余量，管不了**中间夹着**的卡片。而当时的画法是「组 → 每一个任务」**扇出**，所以「组 → 第 2 个任务」这条边必然横穿第 1 张任务卡——而它两端的余量完全正常，端点断言看不出任何问题。

**根因（比想象的广）：** 布局把一整棵子树压在同一天的 x 上、纵向排列，所以子树其实是一条**竖直线性序列**。扇出画法在这个结构里天然会自穿：

| 扇出的边 | 穿过的卡片 |
|---|---|
| `day → 完成带` | `剩余带`（38pt，整张组卡高度） |
| `day → 遗忘带` | `剩余带` + `完成带` |
| `剩余带 → 任务3` | 任务1（30pt）+ 任务2 |
| `剩余带 → 任务2` | 任务1 |
| `day → 完成带`（tasks 档） | 组卡 + 三张任务卡 |

在「一天 3 剩余 + 2 完成 + 2 遗忘」的场景下共 **11 处穿越**。也就是说 §7.8 只修掉了最外层那一根，里层的线还在穿。

**修法：把扇出改成链。** 新增 `WeekTopologyLayout.SubtreeLink` 与 `subtreeLinks(for:semanticLevel:)`，按竖直顺序（日期 → 带0 → 带0的任务… → 带1 → …）只连接**相邻**的两个节点。于是每一段都只跨一个层级门槛的间隙——而那正是 `taskClearEffectiveScale` 已经在保证的东西。这不是「补偿」而是「消除可能性」：自穿在链式画法下不再是一个可以发生的状态。

```swift
for link in layout.subtreeLinks(for: day, semanticLevel: semanticLevel) {
    drawTreeEdge(
        from: transform.point(upper), to: transform.point(lower),
        startClearance: link.parentHeight / 2 + edgeGap,
        endClearance: link.childHeight / 2 + edgeGap,
        color: link.kind.color.opacity(entersBand ? 0.5 : 0.34),
        context: &context
    )
}
```

卡高随链接一起传递，因为一条链接是唯一同时知道「两个端点是谁」和「当前是哪个层级」的地方。原先把「进组带 0.5 / 进任务卡 0.34」的深浅差别保留下来了（用 `childID == day.groupID(for: kind)` 判定）。顺带把 `nodeIDs(for:)` 提到 `WeekTopologyDaySnapshot` 上，视图与测试不再各写一份 switch。

**新增测试：**

| 用例 | 守住什么 |
|---|---|
| `test_weekTopologyGeometry_cardsNeverOverlapAndLinksNeverCrossACard` | 在 **4 个尺度**（overview 0.5 / groups 门槛 / tasks 门槛 / 放大上限 1.8）× 一天三个带的场景下：① 任何两张卡片不压叠；② 任何一条连线不穿过它两端以外的任何卡片。视图的绘制几何直接取自 `subtreeLinks`，所以这条用例测的就是画布 |
| `test_weekTopologyFanOutLinks_wouldRunThroughTheCardsBetweenThem` | 反面证据：断言扇出画法**确实**会穿卡，说明上面那条断言有牙齿、也说明「改成链」不是多余的 |

**「守卫会失败」实测：** 把 `subtreeLinks` 临时改回扇出，`test_weekTopologyGeometry_...` 立刻报出 11 条穿越，例如
`[groups 门槛] day → group:completed 的连线穿过了 group:remaining（38.0pt）`、
`[tasks 门槛] group:remaining → task:… 的连线穿过了 task:…（30.0pt）`。改回链式后 115 条全通过。

**教训（写进技能了）：** 「端点有余量」不等于「线段不穿卡」。几何断言必须覆盖**中间**的障碍物，否则只能抓住最外层那一个实例。
