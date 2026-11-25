# 本周任务结构树（Week Topology）改动审查范围

日期：2026-09-14
仓库根：`/Users/luobowen/handwrittenfnn/weekyii`
项目目录（下文所有相对路径以此为准）：`Weekyii/Weekyii/`

> **给审查者的一句话：** 这是一次针对「本周任务结构树」绘制层的集中返工。核心不是加功能，而是**把两套各自算几何的渲染通道收敛成一套**，并把「层级阈值 / 连线端点 / 卡片尺寸」全部改成由节点几何推导。请重点质疑下面第 6 节列出的取舍。

---

## 1. 审查目标：四个用户可见缺陷 + 一个共同根因

| 编号 | 缺陷 | 现象 |
|---|---|---|
| B1 | 相邻日期的任务卡互相压叠 | 一天的任务用 3 列网格排布，行宽 276pt 而日间距只有 152pt |
| B2 | 任务层「够不到」 | 阈值写成手写倍数（1.5 / 2.2 / 2.6），与真实卡片尺寸脱钩 |
| B3 | **连线穿框** | 一根竖线笔直穿过日期节点、组节点、任务卡，把整棵子树串成糖葫芦 |
| B4 | 紧凑日期卡折行 | 「14日 · 2」折成两行并撞到自己的角标 |

**共同根因 R：** 卡片尺寸固定在「点」（不随缩放变化），而 `WeekTopologyTransform` 只缩放**位置**。于是：

- 语义层级的阈值如果写成缩放倍数，就会随着卡片尺寸改动而失效（→ B2）；
- 连线如果按「卡片中心 → 卡片中心」画，必然横穿卡片（→ B3）；
- 门槛如果只保证「卡片不压叠」而不保证「有地方画线」，两者会在同一尺度上打架（→ B3）。

**B3 有两层，第二层是修复后复核才发现的：**
1. 端点层：线按中心点画，两端都不让位；
2. 结构层：`WeekTopologyEdgeSpan` 只保证线段**两端**有余量，管不了**中间夹着**的卡片——而画法是「组 → 每一个任务」**扇出**，所以「组 → 第 2 个任务」必然横穿第 1 张任务卡。

---

## 2. 代码改动范围

工作树**未提交**，基线为 `HEAD`（该 commit 早于本次全部拓扑工作，因此下面的 diff 统计包含同一天内多轮拓扑改动，不含其他功能的改动）。

```
$ cd /Users/luobowen/handwrittenfnn/weekyii
$ git diff --stat -- Weekyii/Weekyii/Features/Week/WeekTopology.swift \
                   Weekyii/Weekyii/Features/Week/WeekTopologyView.swift \
                   Weekyii/Weekyii/Features/Week/WeekOverviewView.swift \
                   Weekyii/Weekyii/Tests/ModelTests.swift \
                   Weekyii/Weekyii/WeekyiiUITests/DraftReorderUITests.swift

 .../Weekyii/Features/Week/WeekOverviewView.swift   |  112 +-
 Weekyii/Weekyii/Features/Week/WeekTopology.swift   |  578 +++++++++-
 .../Weekyii/Features/Week/WeekTopologyView.swift   |  675 +++++++----
 Weekyii/Weekyii/Tests/ModelTests.swift             | 1213 +++++++++++++++++++-
 .../WeekyiiUITests/DraftReorderUITests.swift       |  108 +-
 5 files changed, 2404 insertions(+), 282 deletions(-)
```

| 文件（相对 `Weekyii/Weekyii/`） | 现总行数 | 本范围？ | 说明 |
|---|---|---|---|
| `Features/Week/WeekTopology.swift` | 780 | **是** | 数据 + 几何，改动最重 |
| `Features/Week/WeekTopologyView.swift` | 1126 | **是** | 画布、卡片、inspector |
| `Features/Week/WeekOverviewView.swift` | 640 | **部分**（见 2.4） | 仅拓扑相关的 3 处 |
| `Tests/ModelTests.swift` | 3492 | **部分**（见 2.5） | 仅第 1071–2041 行 |
| `WeekyiiUITests/DraftReorderUITests.swift` | 652 | **部分**（见 2.6） | 仅 1 个用例 |

### 2.1 `Features/Week/WeekTopology.swift`（780 行）

**新增类型 / 关键符号（含当前行号，便于跳转）：**

| 行号 | 符号 | 作用 |
|---|---|---|
| 86 | `WeekTopologyDaySnapshot.nodeIDs(for:)` | 把「一个结果带里有哪些节点」从视图收敛到数据层，视图与测试不再各写一份 `switch` |
| 220 | `enum WeekTopologyMetrics` | **全部**几何常量集中于此（原来散落在视图里） |
| 304 / 309 / 321 | `edgeGap` = 3、`minimumConnectorLength` = 4、`minimumNodeGap`（**推导值** = `2*edgeGap + minimumConnectorLength` = 10） | B3 的关键：门槛与连线问的是同一个间隙，折进一个常量后两个条件构造上恒等 |
| 330 | `verticalInset`（推导 = `rootNodeExpandedHeight/2 + canvasVerticalPadding` = 35） | 修 overview 档根卡被上边缘裁掉 7pt |
| 357 / 366 | `verticalClearEffectiveScale` / `horizontalClearEffectiveScale` | 由「两张卡的半高之和 + 门槛间隙」推出层级门槛 |
| 406 / 413 | `groupClearEffectiveScale` = 0.7875 / `taskClearEffectiveScale` = 0.8462 | 语义层级门槛，**取代原手写倍数 1.5 / 2.2 / 2.6** |
| 435 | `struct WeekTopologyLayout` | 坐标布局；组带按「最高的那一天」分带，避免第二行任务压到下一带 |
| 520 | `struct WeekTopologyRootRail` | 根横杆（trunk / rail） |
| 539 | `struct WeekTopologyEdgeSpan` | **B3 端点层的可断言载体**：`startY = 上卡中心 + 上卡半高 + edgeGap`、`endY = 下卡中心 − 下卡半高 − edgeGap`；空间不足返回 `nil`（宁可不画也不穿框） |
| 566 | `extension WeekTopologyLayout` | 绘制几何的纯函数区 |
| 573 | `struct SubtreeLink` | 一条连线 + 两端的卡高（卡高随链接传递，因为链接是唯一同时知道「两端是谁」和「当前哪个层级」的地方） |
| 596 | `func subtreeLinks(for:semanticLevel:)` | **B3 结构层的修复**：按竖直顺序只连接**相邻**两节点（日期 → 带0 → 带0的任务… → 带1 → …），取代扇出 |
| 661 | `func subtreeBounds(for:)` | 取景框：并入每个节点**自己**的卡片矩形（早期版本用最大卡片整体外扩，导致多出 ~19pt 把子树顶出画布） |
| 709 | `struct WeekTopologyViewportState` | 缩放状态 |
| 716 | `maximumEffectiveScale` = 1.8 | 缩放上限改为**渲染尺度**（卡片尺寸不随缩放变化，超过 1.8 只买到空白） |
| 721 | `tasksReachEffectiveScale`（= `taskClearEffectiveScale`） | 取景必须达到的下限 |
| 757 | `focusEffectiveScale(subtreeSize:canvasSize:)` | `min(max(fit, taskClear), 1.8)`：既能装进画布、又已经进入任务层 |

**关键常量改动（审查重点）：**

| 行号 | 常量 | 原值 | 现值 | 理由 |
|---|---|---|---|---|
| 252 | `taskColumnCount` | 3 | **1** | B1 的**结构性**修复。3 列时一天行宽 276pt > 日间距 152pt，相邻日期外列中心距 40pt 而卡宽 84pt → 必然重叠 44pt；要让 3 列互不压叠需 `taskColumnSpacing ≤ 34 < 84`，**几何上无解** |
| 239 | `groupTopOffset` | 68 | 80 | 让「日期→组」在组层门槛下真的分开 |
| 269 | `taskVerticalSpacing` | 42 | 48 | 给连线腾净空（加宽行距会抬高子树但让门槛掉得更快，净余量反而变大） |
| 270 | `taskFirstRowOffset` | 54 | 52 | 同上 |
| 304 | `edgeGap` | 6 | 3 | 每条连线要收两次 |
| 321 | `minimumNodeGap` | 6（写死） | **10（推导）** | 见上 |
| 283 / 284 | `dayNodeCompactWidth` / `Height` | 34 / 32 | **36 / 30** | 原 metrics 记错了（视图实际画 36×30）。按 34 宽，「14日 · 2」会折行撞角标 |

### 2.2 `Features/Week/WeekTopologyView.swift`（1126 行）

| 行号 | 符号 | 改动 |
|---|---|---|
| 84 | `topologyCanvas` | `snapshot` / `layout` 由 `body` 解析一次后传入（原来每个 computed property 都重建，一次 `body` 求值约 13 次） |
| 196 | `drawConnections` | **重写**：主干从根卡下边界出发；日支线止于日期卡上边界；子树部分改为遍历 `layout.subtreeLinks(...)`，每段两端各让 `edgeGap`。删掉了原先内联的 `nodeIDs` switch 与扇出循环 |
| 292 | `drawTreeEdge` | 改为按 `WeekTopologyEdgeSpan` 绘制；空间不足时直接 `return`（不画） |
| 343 | `dayButton` | 尺寸改读 metrics（原硬编码 88 / 68） |
| 476 / 496 | `inspector` / `daySubtreeInspector` | 把「找节点所属的那一天」从 4 次线性扫描收敛为 1 次。**分支顺序 `day → group → task → forgotten` 不可动**（见 §5） |
| 682 | `focus(day:)` | 改为取景 `subtreeBounds`（原来只居中日期节点，导致任务行落在画布外 ~208pt，轻点日期像是「没反应」） |
| 891 | `WeekTopologyDayNode` | 外框改读 metrics；紧凑分支加 `.lineLimit(1)` + `.minimumScaleFactor(0.75)`（**B4**，构造性保证折行不再可能） |
| 842 | `WeekTopologyRootNode` | 高度改读 `rootNodeCompactHeight` / `rootNodeExpandedHeight` |

### 2.3 审查时建议的阅读顺序

1. `WeekTopologyMetrics`（220–433）—— 所有几何的唯一来源
2. `WeekTopologyEdgeSpan`（539）+ `subtreeLinks`（596）—— B3 的两个层次
3. `drawConnections`（196–290）—— 消费上面两者
4. `focusEffectiveScale`（757）+ `subtreeBounds`（661）—— 取景预算

### 2.4 `Features/Week/WeekOverviewView.swift`（640 行）— 仅 3 处

| 位置 | 改动 |
|---|---|
| `WeekOverviewContentView` ~230 | `if WeekTopologySnapshot(week: week).hasContent` → `if WeekTopologySnapshot.hasContent(in: week)`（轻量探针，避免为了判断「有没有内容」就建整棵快照） |
| `reconcileTopologyState` ~314 | 把 `guard let selectedNodeID` 提到建快照之前 |
| 新增 `WeekTopologyEmptyState` ~361 | 空态从内联抽成独立视图（28 行） |

> 该文件的其余 diff 属于**同一轮拓扑改动之外**的内容，见 §4。

### 2.5 `Tests/ModelTests.swift` — 仅第 **1071–2041** 行

第 2043 行起是其他功能的测试（`suspendedCountdownPreset` 等），**不在本次范围**。

新增/改写的拓扑用例（行号）：

| 行号 | 用例 | 守住什么 |
|---|---|---|
| 1169 | `hasContentProbeMatchesBuiltSnapshot` | 轻量探针与完整快照结论一致 |
| 1210 | `SemanticLevel_derivesThresholdsFromNodeGeometry` | 阈值由几何推导（B2） |
| 1223 | `taskClearScaleKeepsCardsApart` | 门槛尺度下任务卡不压叠 |
| 1244 | `tierGatesLeaveVerticalClearance` | 每个层级门槛都留出 `minimumNodeGap` |
| 1281 | `tiersStayDistinguishable` | 组层与任务层落在不同尺度 |
| **1293** | **`EdgeSpan_stopsAtCardBorders`** | 端点落在卡外，且**剩余可见线长 ≥ `minimumConnectorLength`**（只断言「非 nil」不够——中间一点不剩等于裁没了） |
| 1368 | `Focus_everyEdgeStaysDrawableAtTheFramedScale` | 端到端：真实布局在取景尺度下每条边都画得出且不被裁没，同时子树仍装得进画布 |
| 1463 | `EdgeSpan_returnsNilWhenCardsAreTooClose` | 空间不足时返回 nil，不画穿框线 |
| 1475 / 1487 | `verticalInsetClearsRootCard` / `taskRowStaysInsideDayPitch` | 根卡不被裁顶；任务行不宽过日间距（B1 的结构性理由） |
| 1502 / 1526 / 1545 / 1586 | `Layout_buildsTreeLevels…` / `rootRailSpansEveryDayColumn` / `taskRowsNeverCollideWithNextGroupBand` / `taskCardsSeparateAtTaskTierZoom` | 布局与分带 |
| **1724** | **`Geometry_cardsNeverOverlapAndLinksNeverCrossACard`** | **核心不变量**：4 个尺度（0.5 / groups 门槛 / tasks 门槛 / 1.8）× 一天三个带的场景下，① 任何两张卡片不压叠；② 任何一条连线不穿过它两端以外的**任何**卡片 |
| **1805** | **`FanOutLinks_wouldRunThroughTheCardsBetweenThem`** | **反面证据**：断言扇出画法**确实**会穿卡，证明上一条有牙齿、且「改成链」不是多余的 |
| 1859 / 1900 / 1952 | `subtreeBoundsCoversItsOwnDayOnly` / `Focus_framesDaySubtreeInsideCompactCanvas` / `Focus_keepsTaskRowsReachableForLongDays` | 取景预算的两面性 |
| 1970 / 1987 / 2004 | `Viewport_clampsZoomToRenderedCeiling` / `dayNodesSeparateAtOverviewZoom` / `reachesTaskTierAtCompactCardFitScale` | 缩放与档位可达性 |
| 1624 / 1692 / 2021 | `topologyCardRects` / `makeThreeBandDay` / `assertNoVerticalCollision` | 私有辅助 |

### 2.6 `WeekyiiUITests/DraftReorderUITests.swift` — 仅 1 个用例

第 612 行 `testWeekTopologyTaskNodeShowsTaskInspectorNotForgotten`：断言 `查看任务详情` 存在、`任务已遗忘` 不存在。

> 用**分支唯一的文案**而不是 `weekTopologyInspector` 这个 identifier 做断言，因为 `.accessibilityIdentifier` 会**传播到所有子元素**，该 id 不唯一、作用域查询不可靠。
>
> 该文件其余 diff 是主题选择器的截图工具（`ThemePickerScreenshotTests`），**不在本次范围**。

---

## 3. 文档与资产范围

| 路径 | 类型 | 说明 |
|---|---|---|
| `docs/plans/2026-09-14-week-topology-layout-fix-plan.md` | **新增**，659 行 | 主文档。§1–§6 是修复计划；§7 是执行记录：§7.1 取景缺陷、§7.2 三列网格缺陷、§7.3 阈值改几何推导、§7.4 P6（快照只解析一次）、§7.5 未落地项、§7.6 验证截图、§7.7 环境注意、**§7.8 连线穿框（端点层 + `minimumNodeGap` 推导 + 连线长度取舍表）**、**§7.9 扇出画法（结构层）** |
| `docs/assets/week-topology-2026-09-14/` | **新增**，5 张 PNG | 第一轮验证截图（overview / 聚焦日 / 全屏两档 / 任务 inspector） |
| `docs/assets/week-topology-connectors-2026-09-14/` | **新增**，10 张 PNG | 第二轮（连线）验证截图，含 `00-compare-before-after.png`（连线穿框前后对比）、`04-compact-day-row-compare.png`（日期卡折行前后对比）、`05-fanout-vs-chain.png`（扇出 vs 链式对比） |
| `docs/WEEK_TOPOLOGY_REVIEW_SCOPE_2026-09-14.md` | **新增** | 本文档 |

---

## 4. 明确**不在**本次范围（同一工作树里的其他未提交改动）

工作树整体是脏的，以下改动**与拓扑无关**，审查时可以忽略：

| 路径 | 内容 |
|---|---|
| `Features/Extensions/*` | 扩展页 / 心智印记编辑器 |
| `Features/Today/*` | 主题状态插图、今日页 |
| `Models/MindStampItem.swift`、`Services/StateMachine.swift`、`Services/NotificationService.swift` | 其他功能 |
| `Shared/*`（含 `Components/`、`Extensions/`、`WidgetSupport/`） | 通用组件与主题 |
| `Resources/*`（`Localizable.xcstrings`、`SettingsView.swift`、`UserSettings.swift`） | 设置与本地化 |
| `Tests/NotificationServiceTests.swift`、`Tests/StateMachineTests.swift` | 其他功能的测试 |
| `Tests/ModelTests.swift` 第 **1–1070** 行与 **2043 行之后** | `userSettings*`、`theme*`、`suspended*` 等测试 |
| `WeekyiiUITests/DraftReorderUITests.swift` 中的 `ThemePickerScreenshotTests` | 主题选择器截图工具 |
| `ICLOUD_SYNC_REVIEW_2026-09-13.md`、`ICLOUD_SYNC_REVIEW_ROUND2_2026-09-13.md`、`docs/testflight-what-to-test.md`、`测试矩阵_2026-09-14.md`、`docs/ICLOUD_SYNC_REVIEW_RESPONSE_2026-09-13.md` | iCloud 同步评审与发布清单 |
| `.workbuddy-ai/` | 本地记忆目录，**请勿删除** |
| `weekyii-icon_副本.png` | 图标副本 |

---

## 5. 复现与验证

本机 Xcode 的宏插件服务在受限沙箱里会失败（`sandbox-exec: sandbox_apply: Operation not permitted`，表现为 `swift-plugin-server produced malformed response` / `'SwiftDataMacros.PersistentModelMacro' could not be found`）。**这不是代码问题**，命令行构建需补 `-disable-sandbox`：

```bash
cd /Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii
xcodebuild -scheme Weekyii \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ./.derived \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' \
  -only-testing:WeekyiiTests/ModelTests \
  -only-testing:WeekyiiTests/StateMachineTests \
  -only-testing:WeekyiiUITests/DraftReorderUITests/testWeekTopologyTaskNodeShowsTaskInspectorNotForgotten \
  test
```

当前结果：**155 个单测（ModelTests 115 + StateMachineTests 40）+ 2 个 UI 用例，0 失败。**

> 不要跑全量：`TaskPostponeServiceTests` 在 iOS 26 模拟器上有既有崩溃，与本改动无关。

**两条「守卫会失败」的实测记录**（审查者可自行复现，这是判断测试有没有用的关键）：

| 故意引入的缺陷 | 触发的失败 |
|---|---|
| `minimumNodeGap` 改回写死的 `6` | `日期→组 在门槛尺度下连线被裁得看不见了`（2.54 < 4.0）、`组→任务：两张卡片之间没有给连线留下任何空间`（nil） |
| `subtreeLinks` 改回扇出画法 | **11 条穿越**，例如 `[groups 门槛] day → group:completed 的连线穿过了 group:remaining（38.0pt）`、`[tasks 门槛] group:remaining → task:… 的连线穿过了 task:…（30.0pt）` |

---

## 6. 请重点质疑的取舍（已知、有意的决定）

1. **连线只有 4pt。** 门槛处两张卡的净空**恒等于** `minimumNodeGap`，所以门槛处的可见线长**恒等于** `minimumConnectorLength`。这不是没调好，是几何预算的直接结果。想拉到 8.5pt 需要把 `groupTopOffset / taskFirstRowOffset / taskVerticalSpacing` 加到 `104 / 76 / 68`（子树高 +30%），而且余量反而从 1% 掉到 0.5%。**当前选择最小改动，未动用户已过目的纵向节奏。**

2. **取景余量只有 ~1%。** `fitted` = 0.8559 vs `taskClearEffectiveScale` = 0.8462。余量偏紧但为正，且有测试守住。数值扫描显示 `T=96 / F=64 / S=58` 可把余量拉到 4.4%，代价是明显改变纵向节奏。

3. **`taskColumnCount` 3 → 1 改变了全屏任务层的观感**：从三列扇形变成纵向列表。这是唯一能结构性消除 B1 的改法（3 列与 152pt 的日间距几何上不相容）。**如需回退只需把该常量改回 3**，但 B1 会立刻回来。

4. **`inspector` 的分支顺序 `day → group → task → forgotten` 不可动。** 任务节点确实属于某一天（日查找成功），但它既不等于日期节点 id 也不匹配任何分组 id —— 正是这一点让它落到 `taskInspector`。调换顺序会让点任务卡显示「任务已遗忘」。已由 UI 用例守住。

5. **一天任务很多（≥4）时子树装不下紧凑画布**，取景退到任务层下限，后面的行需要拖动查看。这是画布高度决定的物理限制。**如果认为「需要拖动」本身不可接受，这是一个需要产品决策的开放项，本次未处理。**

6. **组节点 / 任务卡 / 遗忘节点目前没有 accessibility identifier**（只有 root / day / fullscreen / inspector 有）。UI 用例只能用文案匹配。建议后续按同一命名约定补齐（`weekTopologyGroup_*` / `weekTopologyTask_*`）。本次未做。

7. **`WeekTopologyMetrics` 里的两个常量（`horizontalInset` = 100、`dayY` = 212）仍是手写值**，没有像门槛那样从几何推导。它们只影响初始留白与根到日期层的间距，不影响任何「会不会压叠 / 会不会穿框」的结论。

---

## 7. 结论摘要

- 改动集中在 **3 个源文件 + 2 个测试文件**，其中真正需要细看的是 `WeekTopology.swift`（几何与推导）与 `WeekTopologyView.swift` 的 `drawConnections`（消费几何）。
- 文档新增 **1 份计划/执行记录 + 1 份本文档 + 2 个截图目录**。
- 缺陷 B1/B2/B3/B4 均已有对应测试；B3 的两条核心用例都实测过「故意改回缺陷实现 → 断言失败」。
- 尚未处理的开放项见 §6 的第 5、6 条，第 1、2 条是有意的取舍。
