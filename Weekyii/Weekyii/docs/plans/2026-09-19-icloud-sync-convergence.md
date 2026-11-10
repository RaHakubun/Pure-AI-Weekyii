# Weekyii iCloud 多端同步收敛方案 v3.2

日期：2026-09-19（v3.2，含第 3 轮裁决及方案 1 实施落地记录）
状态：**已按用户选择的方案 1 落地核心实现：保留 SwiftData，使用容器创建前注册的 CloudKit 事件观察者 + 进程内严格结算；B0/B、E-1'、C、F、A.7、D1、E-1.5/B.5、E-2' 已实现。方案 1 不实现 Core Data 持久化事件历史查询；进程被杀后不能把历史事件当作已验证事实，启动期间继续 fail-closed。D2（跨设备时区锚点）按 §6 裁决仍为独立立项，本轮不落地。**
范围：仅 iCloud 同步一致性与不可逆删除问题。不含 UI 改版、不含新功能（第 5 节的"同步开关"是唯一例外，它属于同步能力本身）。

## 修订记录

**实施记录（2026-09-19）**

- **Phase A 已完成**：`DayModel` 对终态隐藏 draft/focus/frozen getter 但保留原始 `tasks`；三条过期路径停止删除任务；修复层不再凭 zone 推导写入 `closedAt`；`.expired` 保持时间语义的软终态，`closedAt != nil` 仍优先提升为 `.completed`；`doneFocus` 与 `TaskPostponeService` 在闸门关闭时只完成/后移任务，不写硬完成证据；UI 增加“已完成最后一项，正在同步确认”。
- **Phase A 验证**：iPhone 17 Pro（iOS 26.2）运行 `ModelTests + StateMachineTests`，本轮兼容性修复后的目标回归为 198/198。原有“过期即删除”测试已改为验证 raw task 保留、UI getter 隐藏。
- **方案 1 的架构取舍**：Apple 的 `NSPersistentCloudKitContainerEventRequest` 需要 `NSManagedObjectContext`，而 SwiftData `ModelContainer` 的公开接口不提供可安全复用的 Core Data context/coordinator。为遵守 #16 的单容器与零隐式写入约束，本轮不引入第二套 Core Data 栈；改为在创建 SwiftData `ModelContainer` 前同步注册 `addObserver`，按事件 identifier 追踪在飞事件，并以容器加载时刻作为当前进程的初始基线。该机制只对当前进程观测到的事件负责，不能声称恢复被杀进程错过的历史事件；无当前进程证据时仍保持 fail-closed。
- **当前实现记录**：B0 的四态物理库分流、CloudSyncMonitor 结算闸门、账号身份护栏、双库显式迁移、前端只读控制、设备内时区锚点、KVS 截止时间镜像、习惯水位线闸门和受控 GC 已进入源码。设置页的 iCloud 开关不会热切换容器，必须快照、明确选择数据来源并重启。
- **E-1.5/B.5 落地记录（2026-09-20）**：`CloudSyncMonitor.settlement()` 在返回 `.settled` 时把 `currentUserRecordID` 持久化到设备本地 `UserDefaults.lastSyncedUserRecordIDKey`（不进 SwiftData schema，不开 V9），作为启动与运行期 `CKAccountChanged` 的身份比对基线。运行期账号切换经 `refreshAccountStatus → configureIdentity` 触发 `identityConfirmed = false` → `unsettled(.identityMismatch)` → 闸门关闭；单元测试覆盖“换到 B 关闭 / 重新登录 A 保持开启”两条路径。局限已写入代码注释：此护栏只挡 App 层写入，不能阻止框架在已建好的 `.private(B)` 容器上把 A 的记录导出到 B（那由 #19 甲的延后建容器阻止）。
- **E-2' 落地记录（2026-09-20）**：`cloudDetached` 身份不一致启动时自动导出待决快照到 `pendingIdentityResolutionKey`，并给云库/本地库各建一份恢复点；设置页提供三选（以云端为准 / 以本机为准 / 关闭同步转本地）；`performIdentityResolution` 把 archive 写入对应物理库、更新 `lastSyncedUserRecordID`、清除待决键，必要时清空云库文件并禁用同步。全程 `syncedWritesAllowed == false`，不在本进程重建可写容器，重启后生效。
- **验证边界（2026-09-20 更新：malloc 崩溃已根因修复，全量测试恢复）**：此前记录的 "iOS 26.2 模拟器测试宿主 malloc 崩溃" 已定位为三个独立问题并全部修复，6 个被隔离（XCTSkip）的用例全部恢复运行：① `TaskPostponeServiceTests.makeContainer()` 用 V4 schema 建容器而用例插入当前 V8 模型，触发 SwiftData "Failed to cast model" 致命错误——改用当前 schema；② iOS 26.2 的 Swift 6 back-deploy 路径在析构 `@MainActor` 类时 double-free task-local 存储（崩溃栈：`swift_task_deinitOnExecutorMainActorBackDeploy -> TaskLocal::StopLookupScope::~StopLookupScope -> ___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED`，涉及 `PendingViewModel`/`AppState` 的 deinit）——测试中以静态数组保留实例规避（与既有 `retainedUserSettings` 同手法，注释已注明框架缺陷，不是业务代码问题）；③ 四个 pending-VM 用例存在时间炸弹（固定日期 2026-03 被真实时钟越过，`canEdit` 抛 `cannotEditStartedDay`）——注入固定 `TimeProviding` 修复。

- **最终回归（2026-09-20，iPhone 17 Pro 模拟器 iOS 26.2）**：`WeekyiiTests` **255/255 通过（含 6 个恢复隔离用例、E-1.5 的 6 个身份护栏用例、E-2' 的 9 个身份决策用例；0 malloc 崩溃、0 重启、0 失败）**；`WeekyiiUITests` **20/20 通过**。全量绿色，一次跑完。

**v3.1（2026-09-19，响应用户第 3 轮裁决）**

| # | 裁决 | 判定 | v3.1 的落地 |
|---|---|---|---|
| **18** | **不接受** `noInboundChannel` 放行全部 Tier-2a | **完全接受否决，且它让设计更简单** | 三级谓词塌缩为**单一谓词** `syncedWritesAllowed`；`.production` 下只有 `settled` 放行任何 Tier-2；`maxWait` 不再恢复任何同步字段写入。未登录设备的可用性改由**切换 store** 解决：`launchStoreMode` → `resolveStoreMode`，`.noAccount`/`.restricted` → `.localOnly` → `Weekyii.local.store` → `noRemotePeer` → 全开（§4.2.1、§4.2.2）。`processKillTime` / 跨日过期按你的意见改判 **Tier-2b（终态语义写入）**（§4.2.3） |
| **19** | 选**甲**，并要求进程级终止边界 | **接受，四条边界全部写入** | §7.2.1 定案为甲，乙/丙标记为已否决；§7.2 新增"进程级终止边界"四条并逐条给出实现约束；§7.2.3 补齐启动代码改造面（`LaunchState.resolving`、`WeekyiiApp.swift:514-518` 异步化、`:619`/`:629` 两条重试路径的 storeMode 透传）。**#19 派生出一个 v3.1 起草时漏掉的洞**：只读降级容器不能被标成 `.localOnly`，否则会让 `settlement` 返回 `noRemotePeer` → 全部放行，等于复现 #18 否决的错误。方案 1 的 `cloudDetached` 保留源库语义，但实际从云库的进程级临时副本读取，源库不被打开。 |
| **20** | 接受"受控删除 + 已知残余风险" | **接受，五条强制表述全部写入** | §3.7 增加：GC 非绝对安全／离线跨回收窗口可能复活／属已知数据一致性风险／**GC 验收独立于 Phase A/B**／**不得对外宣称"删除绝不复活"**。tombstone/V9 明确排除在本轮之外 |
| **产品语义** | 选 **a. 保留但隐藏** | **接受** | §3.2 的路径 B 定案；四条理由（不再展示过期任务／不把未完成伪装成完成／不立即丢失迟到数据／可由 GC 回收）写入 §3.2 |

**v3.1 的结构性后果（第 3 轮裁决派生，不是新增裁决）**

- **Phase B 多了一个硬前置 B0**（§9）。#18 用"切库"替代"放行"之后，闸门的第一步不再是判定而是**决定打开哪个库**，它需要：账号状态（来自 #19 的阶段 1）+ 两个库的物理分离（#16 的路径部分，从 E-1 提前）。**不提前路径分离，#18 的"切库"是假的** —— `.localOnly` 仍会打开 `Weekyii.store`，等于在云库上以 `.none` 可写建数据，日后登录即隐式合并。
- **E-2 从"中优先级"上调为 B0 的组成部分**；E-1 拆为 B0（路径）+ E-1'（开关 UI 与迁移）；E-1.5 保留为 **Phase B 的最终验收前置**，覆盖进程存活期间的 Apple ID 切换，不能在 B 宣称完成后再补。

**已核实的启动事件问题（方案 1 已落地）**

5. **`setupSucceeded` 与 `lastEventEndedAt` 可能在 Monitor 启动前就已错过事件 → `settled` 永久不可达 → Tier-2 永久不执行。** 这是 v3 §4.10 的真实死锁。方案 1 的修法见 §4.12：同步注册观察者、容器加载后建立当前进程基线，并在无当前进程证据时继续 fail-closed。该实现明确不恢复被杀进程的历史事件。

6. **`WeekyiiApp.swift:619` / `:629` 两条重试路径会绕过全部 #18/#19 判定**（本次 Read 发现，非审查提出）。二者无参调用 `bootstrapPersistentContainer()` → 内部走 `launchStoreMode` → 生产环境恒 `.production`。若阶段 1 判定为 `.localOnly`/`.cloudDetached` 后容器构造失败，用户点"重试"就以 `.production` 重建。修法见 §7.2.3 ③，验收见 §13.2.0。

**因 #18 否决而撤回的 v3 内容**

- §4.2.4 的 `repair(referenceDate:allowsIrreversible:)` **撤回**：两档谓词塌缩后 `repair` 整体受单一闸门控制，无需加参，`DataInvariantRepairing`（`StateMachine.swift:47-49`）协议**不改**。这是对 v3 自己的第二次反向修正（v1 拆两半→v2 作废→v3 重新拆→v3.1 不拆）。最终形态恰好回到 v2 的"闸门在调用点、函数内部一行不改"，但**理由不同**：v2 是错的（认为派生写入天然安全），v3.1 是对的（因为两档放行条件已相同，拆分无意义）
- §4.2.3 的"⚠️ 有意偏离审查清单 3 项"标注**删除**：偏离不再存在
- §4.5 的"`maxWait` 放行 Tier-2a"**撤回**；§4.7 的"窗口 2：Tier-2a 恢复"**撤回**
- §7.3 给 E-1.5 的理由（"§4.2.1 的分级把重量压到了 E-2"）**作废**：那个分级已不存在，理由已在 §7.3 重新推导

---

**v3（2026-09-19，响应用户第 2 轮对抗审查 + 四项裁决）**

已裁决并落地：

| # | 裁决 | v3 落地位置 |
|---|---|---|
| 10 | 接受根因诊断；但不得再写"同步链路本身 100% 健康" | §0 改为限定表述：只声明"未发现手写 CKRecord 逻辑"，明确不覆盖服务端配置与传输故障 |
| 15 | 接受延迟完成 | §3.3：闸门期立即移入 complete zone，但不写 `closedAt`、不标硬 `.completed`，UI 显示"已完成最后一项，正在同步确认" |
| 16 | **裁定独立 store 文件**，不再是"先实测再决定" | §7.1：`Weekyii.store`（云）/ `Weekyii.local.store`（本地）；关闭时快照；双向切换流程各自定义数据来源，禁止隐式合并 |
| 17 | 异步账号检查，但 CloudKit 容器必须延后创建 | §7.2：`fetchUserRecordID()` 返回前不得构造 `.private(id)` 容器；阶段 1 为 `.none + allowsSave: false` |

审查补正：

| # | 审查意见 | 判定 | v3 的处理 |
|---|---|---|---|
| 1 | `.noAccount` / `.restricted` 不应直接放行 | **接受结论，但需分级**（⚠️ **v3.1 已推翻"分级"**，见 #18） | 生产下六种账号状态一律不再放行**不可逆操作**。派生写入按"是否存在可达的入站通道"分级（§4.2）。偏离之处见下"v3 新发现 1"。**v3.1：分级作废，全部 Tier-2 同档；未登录设备改走 `.localOnly` 独立库** |
| 2 | `maxWait` 仍绕过安全闸门 | **完全接受**（v3 只做了一半，v3.1 补完） | 单一布尔拆为三级谓词；`maxWait` **不再放行任何不可逆操作**（§4.2）。**v3.1：`maxWait` 不放行任何同步字段写入，它已完全退出数据闸门** |
| 3 | `CloudSyncMonitor` 未解决并发事件 | **完全接受，已定位到行** | `:138` 是单标量 `eventState`，`:213-238` 从不读 `event.identifier` / `storeIdentifier`；改为在飞事件集合 + `max(endDate)` 静止判据（§4.10） |
| 4 | 引导期不只是 `repair` | **完全接受，且比审查意见更严重** | `TaskTypeDefinition.swift:100-120` 确认写同步字段并在 `:118` 显式 save；更严重的是 `load()`（`:94-98`）每次都会重新播种，被 3 处 UI 代码在任意时刻调用（§4.11） |
| 5 | GC 不能声称"不需要 tombstone" | **完全接受** | §3.7 改为"有边界风险的受控删除"；离线旧设备重新上传登记为**已知未解决场景** |

**v3 新发现（审查与原方案都未提及）**

1. **审查规则 1 + 规则 2 字面叠加会永久冻结"未登录 iCloud 的设备"。** `launchStoreMode`（`WeekyiiPersistence.swift:89-91`）对所有非 XCTest 进程一律返回 `.production`，与是否登录 iCloud 无关。若六种账号状态全部 fail-closed 且 `maxWait` 不放行任何 Tier-2，则该设备永远无法创建本周（`createPresentWeek:297-306`）→ 首页空 → App 不可用；离线设备同理。~~v3 的解法是把 Tier-2 再分为"不可逆"与"派生写入"两类，`maxWait` 只放行后者。~~ **v3.1：问题成立，v3 的解法被 #18 否决。正确解法是切换 store —— `resolveStoreMode` 把 `.noAccount`/`.restricted` 映射到 `.localOnly`（`Weekyii.local.store`），落 `noRemotePeer` → 全开。问题依然存在，只是解法从"放宽闸门"换成"换一个没有对端的库"（§4.2.2）。**
2. **#16 与 #17 相互冲突。** #16 禁止同一 SQLite store 在 `.private(id)` 与 `.none` 之间反复打开；#17 阶段 1 要求以 `.none + allowsSave:false` 打开 store 让用户看到数据 —— 而用户数据就在 `Weekyii.store`（云库）里，阶段 1 打开的必然是同一文件。二者不可同时满足。**v3.1：#19 裁决为甲（阶段 1 不建任何容器），冲突消解 —— 全程只打开一次，不存在"反复"。乙、丙已否决（§7.2.1）。**
3. **审查点 4 的修复是 #17 的硬前置。** `TaskTypeDefinition.swift:118` 是 `try context.save()`，在 `allowsSave: false` 的容器上会抛错；而它由 `WeekyiiPersistence.swift:144` 在 `makeModelContainer` 内部无条件调用。**不先把播种移出容器构造，#17 的只读阶段 1 根本建不起来。**
4. **#16 的爆炸半径被低估。** `persistentStoreURL()`（`:148-153`）是单一固定路径，仓内有 **9 处外部调用点**，其中 `SettingsView.swift:2679` 是 `restoreSnapshot(named:to:)` —— 双库后若仍解析到云库路径，等于把快照恢复到错误的文件上，是一条数据丢失路径（§7.1）。

**v2 保留的新发现**：Phase A 的 getter 门控会让现有测试断言退化为同义反复（§3.6）。

---

**v2（2026-09-19，响应用户第 1 轮对抗审查）**

| # | 审查意见 | 判定 | v2 的处理 |
|---|---|---|---|
| 1 | 闸门 fail-open，`.checking` 期间会放行破坏性操作 | **完全接受** | 闸门改为 fail-closed；判据从 `hasStarted` 改为 `WeekyiiPersistence.StoreMode`（§4.2）。`.checking` 一律关闭 |
| 2 | 闸门覆盖不全，`normalizeStatus`/`normalizeFocusZone`/`normalizeTaskOrder`/`refreshWeekSummaryMetrics`/`HabitTaskMaterializer.sync` 仍会基于部分同步数据写同步字段 | **完全接受，且比审查意见更严重** | 放弃 v1 的"外科手术式门控"，改为 **reconcile 拆 Tier-1（仅本地）/ Tier-2（任何同步字段写入）**，闸门关闭时 Tier-2 整体不执行（§4.3）。v1 的收敛论证有逻辑错误，见 §4.1 |
| 3 | `closedAt` 可能被部分同步误写，一旦当永久锚点就锁死错误完成态 | **完全接受，这是 v1 最严重的漏洞** | 拆成"硬终态"（有 `closedAt`，仅由显式用户动作写入）与"软派生"（无 `closedAt`，每轮可重算可纠正）；**删除 `StateMachine.swift:689-691` 的修复侧回填**（§3.1）。修复层永不制造终态证据 |
| 4 | 时区问题未解决，延后只算承认限制 | **接受** | Phase D 拆成 D1（设备内锚点，便宜，本轮做）+ D2（跨设备共享锚点，贵，独立立项）。明确声明：**D2 未落地前，跨时区多端同步不算解决**（§6） |
| 5 | Apple ID 切换生命周期不完整；且全仓没有"本设备是否同步"的任何设置入口 | **接受，并补一条框架硬约束** | `ModelConfiguration.cloudKitDatabase` 在容器构造时固定（`WeekyiiPersistence.swift:127-136`），**运行中无法"停止 mirroring"**，只能重建容器。因此方案改为两阶段启动 + 偏好下次启动生效（§7）。这是本方案中最大的架构改动，量级超过 A+B 之和 |
| 6 | `records.max(dayId)` 仍依赖本地 records 完整；"保留最早记录"会丢 completed | **部分接受，且结论比审查意见更好** | "保留最早"确实错（v1 的 bug）。但读路径**已经**有正确合并语义：`HabitStatistics.swift:111-123` 明确按 `completed > missed > pending` 取最有利状态，注释直接写着"同日多条记录（CloudKit 多设备合并）"。所以正确修法是**删掉去重 pass**，不是修它（§8） |
| 7 | A.7 回收规则只是设想 | **完全接受** | 给出真实设计（§3.7），并指出 GC 会把 Phase A 消除的危险重新引入，因此必须同时满足"纯同步字段函数 + 闸门内执行" |

**v2 新发现（审查与原方案都未提及）**：Phase A 的 getter 门控会让**现有测试断言退化为同义反复**。已确认 1 例，需逐条审计（§3.6）。

---

## 0. 结论

**主要已确认风险：设备本地时间与本地可见数据被当成同步事实写回 SwiftData。**

适用边界（#10 裁决）：当前代码未发现手写 CKRecord 逻辑，同步全部由 `NSPersistentCloudKitContainer` 隐式镜像承担。本方案针对的是**应用层同步收敛风险**，**不覆盖** CloudKit 服务端配置错误或传输故障 —— 这些没有生产数据支撑，本文不作任何断言，也不得被引用为"同步链路健康"的证据。

病灶是**把"设备本地时间 + 本地可见数据算出来的派生结论"当成事实写进了会被同步的字段**。

修复主线四条：
1. **未静止不落盘**：生产云库只有 `settled` 才允许任何同步字段写入；`.localOnly`/`.inMemory` 因物理上没有远端对端而直接放行；`.cloudDetached`、账号未确认、事件在飞或当前进程没有足够证据时全部关闭。`maxWait` 永不放开同步字段写入（§4.2）。
2. **修复层永不制造证据**：终态只能由显式用户动作写入，修复层只能推导、不能伪造锚点。
3. **不可逆降级为可逆**：删除 → 保留 + 隐藏 + 受控回收（回收本身仍是受控删除，见 §3.7）。
4. **同步能力可选、账号可辨**：本设备是否同步由用户决定（独立 store 文件）；CloudKit 容器在账号身份确认前不得创建（§7）。

---

## 1. 根因证据（全部为本次会话 Read 到的当前代码）

### 1.1 派生态被当事实同步

`DayModel.status`（`Models/DayModel.swift:9`）是存储字段、会被 CloudKit 镜像，但同时又是被反复重算的派生值：

```swift
// Services/StateMachine.swift:633-705  normalizeStatus(in:now:)
let hasOpen = draftCount + focusCount + frozenCount > 0     // :639
switch day.status {
case .expired:
    if hasOpen { newStatus = focusCount + frozenCount > 0 ? .execute : .draft }   // :643-648  ← 过期日复活
case .completed:
    if focusCount + frozenCount > 0 { newStatus = .execute }                      // :679-681  ← 完成日回退
```

两处的输入都是"当前**本地可见**的任务集合"，而可见集合取决于同步进度。

**同一病灶的另一处，v1 低估了它**：
```swift
// Services/StateMachine.swift:338-343 + 363-367
private func refreshWeekSummaryMetrics() {
    let weeks = fetchWeeks(status: .past) + fetchWeeks(status: .present) + fetchWeeks(status: .pending)
    for week in weeks { updateMetrics(for: week) }
}
private func updateMetrics(for week: WeekModel) {
    week.completedTasksCount = week.days.reduce(0) { $0 + $1.completedTasks.count }   // :364
    week.expiredTasksCount   = week.days.reduce(0) { $0 + $1.expiredCount }           // :365
    week.totalStartedDays    = week.days.filter { [.execute,.completed,.expired].contains($0.status) }.count  // :366
}
```
三个计数器都是**同步字段**（`Models/WeekModel.swift:14-16`），却在每次 reconcile 无条件按本地可见集合重算并写回（`:118`）。部分同步期间会把"我暂时看不到"写成"不存在"，并传播到所有设备。

### 1.2 不可逆删除，三份实现，全局广播

```swift
// Services/StateMachine.swift:273-290
private func expire(day: DayModel, expiredCount: Int) -> Bool {
    guard day.status != .expired else { return false }
    day.status = .expired
    day.expiredCount = expiredCount
    day.isDraftZoneUnlocked = false
    removeTasks(in: [.draft, .focus, .frozen], from: day)     // :279
    ...
}
private func removeTasks(in zones: [TaskZone], from day: DayModel) {
    let toRemove = day.tasks.filter { zones.contains($0.zone) }
    day.tasks.removeAll { zones.contains($0.zone) }
    for task in toRemove { modelContext.delete(task) }         // :288
}
```

另两份内联副本：`Features/Today/TodayViewModel.swift:465-473` + `:475-481`（delete 在 `:479`）；`Resources/SettingsView.swift:1659-1667`（delete 在 `:1665`）。

`modelContext.delete` 被 CloudKit 转成 CKRecord 删除并广播到所有设备。全仓无 tombstone / 回收站 / undo（grep `tombstone|softDelete|deletedAt|trash|recycle|undoManager` 仅命中 UI 垃圾桶图标与 SwiftUI 的 `habit.isDeleted`）。

**事实边界**：删除范围是 `[.draft, .focus, .frozen]`，complete zone 任务不会被删。

### 1.3 设备本地参数写进同步字段

```swift
// Services/StateMachine.swift:249-263
todayDay.killTimeHour   = userSettings.defaultKillTimeHour     // :260
todayDay.killTimeMinute = userSettings.defaultKillTimeMinute   // :261
todayDay.followsDefaultKillTime = true                        // :262
```
`AppState` 与 `UserSettings` 都是 `UserDefaults.standard` 承载（`App/AppState.swift:13,20-25,29-34`），**不同步**。两设备默认值不同 → 每天各写一次 → LWW 拉锯 → `processKillTime`（`:230-247`）可能用对方的 kill time 判今天过期 → 触发 1.2。

### 1.4 身份锚点依赖设备时区

```swift
// Shared/Extensions/Date+Weekyii.swift:4-16
var dayId: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: self)        // 未设 timeZone → 设备本地时区
}
var weekId: String {
    let calendar = Calendar(identifier: .iso8601)   // 同样跟随当前时区
```
跨时区时同一物理日算出不同 `dayId` → 两条 DayModel → `mergeDuplicateWeeksAndDays`（`:491-501`，按 `dayId` 分组）**合并不了**。

### 1.5 修复服务自身会删除，判据依赖本地可见性

```swift
// Services/StateMachine.swift:531-533
private func weekRichness(_ week: WeekModel) -> Int {
    week.days.reduce(week.days.count) { $0 + $1.tasks.count }
}
```
`mergeDuplicateWeeksAndDays`（`:464-504`）用它选 canonical（`:470`），然后 `:486`、`:498` 删除；`mergeDuplicateBuiltInTaskTypes`（`:506-529`）在 `:523` 删除。部分同步下两设备可见集合不同 → 选出不同 canonical → **互删正本** → 经 `WeekModel.swift:11-12`、`DayModel.swift:22-23` 的 `.cascade` 放大。

### 1.6 引导期修复跑在任何 CloudKit 导入之前

```swift
// App/WeekyiiPersistence.swift:102-109
let container = try makeModelContainer(...)                                        // :103
_ = DataInvariantRepairService(modelContainer: container).repair(referenceDate: referenceDate)   // :107
try validateContainerConsistency(container: container)                             // :108
```
此刻**连 CloudSyncMonitor 都还不存在**（它在 `WeekyiiApp.swift:474` 作为 `@State` 构造、在 `:541` 才 `start()`），没有任何账号状态可查，本地数据最不完整，却正好在此执行 1.5 的删除。

**引导期不止 `repair`（v3 补，审查第 2 轮点 4）。** `makeModelContainer` 在返回容器前还无条件播种：

```swift
// App/WeekyiiPersistence.swift:139-145
let container = try ModelContainer(for: currentSchema,
                                   migrationPlan: WeekyiiMigrationPlan.self,
                                   configurations: config)
try TaskTypeCatalog.seedBuiltInTypesIfNeeded(in: container.mainContext)   // :144
return container
```

而播种本体是**写同步字段 + 显式 save**：

```swift
// Models/TaskTypeDefinition.swift:100-120
let existing = try context.fetch(FetchDescriptor<TaskTypeDefinition>())          // :101
for definition in ... where !existingIds.contains(definition.idRaw) {
    context.insert(definition)                                                   // :104
}
let tasks = try context.fetch(FetchDescriptor<TaskItem>())                       // :107
for task in tasks where task.taskTypeIdRaw.isEmpty { task.taskTypeIdRaw = ... }  // :108-110
let suspended = try context.fetch(FetchDescriptor<SuspendedTaskItem>())          // :112
for task in suspended where task.taskTypeIdRaw.isEmpty { ... }                   // :113-115
if context.hasChanges { try context.save() }                                     // :117-119
```

`TaskTypeDefinition` 是 `@Model`（`:5-6`）→ 会被镜像。`:101` 的 `existing` 判据同样依赖**本地可见性**：首次导入尚未到达时 `existingIds` 为空 → 三条内置类型被重复插入 → 之后靠 `mergeDuplicateBuiltInTaskTypes`（`StateMachine.swift:506-529`，删除在 `:523`）收拾，而那正是 1.5 的互删通道。

**比审查意见更严重的一处**：`TaskTypeCatalog.load(in:)` 看起来是读 API，实际每次调用都重新播种并 save：

```swift
// Models/TaskTypeDefinition.swift:94-98
static func load(in context: ModelContext) throws -> TaskTypeCatalog {
    try seedBuiltInTypesIfNeeded(in: context)      // :95  ← 读 API 里藏写
    ...
}
```

调用点在 UI 层、时刻任意：`Features/Pending/PendingViewModel.swift:206`、`:238`；`Shared/Components/TaskEditorSheet.swift:281`。**所以只门控 `WeekyiiPersistence.swift:144` 是不够的** —— 闸门期内用户打开 Pending 页或任务编辑器，播种照样会跑。详见 §4.11。

### 1.7 自动导入被贴上"手动重同步"标签

```swift
// App/WeekyiiApp.swift:577-582
.onChange(of: cloudSyncMonitor.importRevision) { _, _ in
    _ = appHealthCoordinator?.reconcile(trigger: .manualResync, force: true)   // :579
```
`:404` 把 `.manualResync` 当作绕过 `shouldSkipReconcile`（`StateMachine.swift:377-384`）的信号。远端导入到达（数据最可能不完整）走了"用户明确要求、可放开手脚"的通道。

### 1.8 CloudSyncMonitor 只有观测，没有闸门

`Services/CloudSyncMonitor.swift:134-259` 全文只暴露 `accountState` / `eventState` / `importRevision`，**无任何 pause/resume/settle API**。`importRevision` 的 debounce 默认 1 秒（`:157`），语义是"合并连续导入事件"，不等于"同步已静止"。

`accountState` 初值是 `.checking`（`:137`），只有在 `refreshAccountStatus()`（`:190-211`）异步返回后才变成别的值 —— 而 `start()` 在 `:187` 才发起这个异步调用。**v1 的 `default: return true` 会在这个最危险的窗口直接放行。**

**事件状态是单标量，无法表达并发（v3 补，审查第 2 轮点 3）。** `:138` 只有一个 `eventState`，`:213-238` 的 `consume` 全程只读 `event.endDate`（`:219`、`:225`）、`event.succeeded`（`:224`）、`event.error`（`:231`）、`event.type`（`:226`），**从不读 `event.identifier` 或 `event.storeIdentifier`**：

```swift
// Services/CloudSyncMonitor.swift:213-238
guard event.endDate != nil else { eventState = .syncing; return }   // :219-222  任意事件开始
if event.succeeded {
    eventState = .synced(event.endDate ?? Date())                   // :225      任意事件成功即宣告静止
    if event.type == .import { scheduleImportedChanges() }          // :226-228
} else {
    eventState = .failed(...)                                       // :230-236
}
```

后果（审查描述的场景在代码上成立）：事件 A（import）开始 → `.syncing`；事件 B（export）开始 → `.syncing`；B 先结束且成功 → **`.synced`，而 A 仍在飞行**。任何以 `eventState == .synced` 为静止判据的闸门都会在此刻误开。

连带两处：
- `:141-143` 的 `state` 由这个单标量派生，`:113-120` 的 `isWorking` 只把 `.checking` / `.syncing` 当作工作中 → **设置页的 iCloud 状态行本来就会在导入进行中显示"已同步"**。v2 若直接复用它做闸门，等于继承这个既有缺陷。
- `.synced(Date)` 存的是**最后一个**事件的 endDate，不是所有事件的最大值 → quiet period 的计时基准可能取自一个早已结束的短事件。

修法见 §4.10。

### 1.9 本设备是否同步，全仓无任何设置入口

`WeekyiiPersistence.swift:127-136` 无条件按 `StoreMode` 决定 `cloudKitDatabase`；`launchStoreMode`（`:89-91`）的唯一判据是"是否在跑 XCTest"。`SettingsView.swift:632-646` 只有只读状态行，**没有开关**。entitlements 里 `ubiquity-kvstore-identifier`（`:15-16`）已声明但全仓 `NSUbiquitousKeyValueStore` 零代码命中。

即：生产构建下同步是**硬编码常开、用户不可关闭、不可选择账户**的。

---

## 2. 场景矩阵

| 编号 | 场景 | 现在的后果 | 由哪个 Phase 修 |
|---|---|---|---|
| S1 | A 完成某日，B 离线跨过 kill time 后上线 | B 判过期；`normalizeStatus:679-681` 还可能把 `.completed` 打回 `.execute` | **A** |
| S2 | 新设备/重装首启，CloudKit 数据陆续下载中 | `:107` 引导修复 + `createPresentWeek:297-306` + `fetchOrCreateTodayDay:313-326` + `ensureTodayExists:707-720` 凭空造记录 → 重复 → 后续互删 | **B** |
| S3 | 两设备时区不同 | 同一物理日不同 `dayId` → 重复日不可合并 → present week 唯一性可能被破坏 | **D1 缓解 / D2 才真解决** |
| S4 | 两设备默认 kill time 不同 | `:260-262` 每天互写 → LWW 拉锯 → 误触发过期与删除 | **C** |
| S5 | 两设备同刻编辑同一天 | 字段级 LWW，无 App 层仲裁 | 不在范围（CRDT/锁定已否决，见项目记忆） |
| S6 | 部分同步期 `mergeDuplicateWeeksAndDays` 跑起来 | `weekRichness:531-533` 判据分歧 → 互删正本 + cascade | **B** |
| S7 | 习惯物化与同步交错 | `:149` dup 检查用本地 `day.tasks`，未到达即漏判 → 重复物化 | **B + F** |
| S8 | 退出 iCloud A、登入 B | `CloudSyncMonitor:180-185` 收到 `.CKAccountChanged` 只刷新状态 → A 的本地记录被推进 B 的私有库（跨账户泄露），B 的数据混入本地 | **E** |
| S9 | 用户想让某台设备不同步（测试机 / 共用设备 / 流量敏感） | **无任何入口**，只能删 App 或退 iCloud | **E** |

---

## 3. Phase A：终态契约 + 停止删除

### 3.1 硬终态 vs 软派生（v2 重写，修 §审查#3）

v1 的规则是"`closedAt != nil ⟹ .completed`，永久粘性"。**漏洞**：`closedAt` 自己会被修复层在部分同步期写出来。

```swift
// Services/StateMachine.swift:689-691
if newStatus == .completed && day.closedAt == nil {
    day.closedAt = now          // ← 修复层凭空制造"终态证据"
}
```
若设备暂时只看到 complete 任务、看不到尚未到达的 focus/frozen，`:674-675` 会推出 `.completed`，紧接着 `:690` 把它固化成 `closedAt`。此后 v1 的锚点规则会把**错误的完成态永久锁死**，且因为它"设备无关"，两台设备会一致地锁死同一个错误。

**v2 规则：证据只能由显式动作产生，修复层只能推导不能伪造。**

```
硬终态（sticky，永不离开）：day.closedAt != nil            ⇒ status = .completed
软派生（每轮可重算、可被新到数据纠正）：closedAt == nil 时，
    ├─ status == .expired                                  ⇒ 保持 .expired
    └─ 其余                                                ⇒ 按 zone 计数派生（现有 :649-688）
```

配套改动：**删除 `StateMachine.swift:689-691`**。理由：
- 修复层从此不写 `closedAt`，软 `.completed` 保持可纠正 —— focus/frozen 到达后 `:679-681` 会把它推回 `.execute`，这正是我们要的行为
- `closedAt` 的写入点收敛到三处，全部是**本机显式动作**：`TodayViewModel.swift:250-251`（`doneFocus`）、`TaskPostponeService.swift:432`、`:445`（顺延后队列空）
- 删除后无功能损失：`closedAt` 在 `Features/` 下**零个读取点**（全仓读取点只有 `DataArchiveService.swift:220,339` 归档导出/导入、`StateMachine.swift:552` 合并取 latest）。它当前是"写多读零"的字段，正好适合当纯证据锚点

**验证删除 `:689-691` 不破坏测试**：`Tests/ModelTests.swift:3891` `XCTAssertEqual(todayDay.closedAt, now)` 位于 `test_execute_fromFocusWithoutFrozenMarksSourceCompleted`（`:3868-3894`），该测试调的是 `TaskPostponeService.execute`（`:3888`），`closedAt` 由 `TaskPostponeService.swift:432` 写入，**测试全程不跑 reconcile** → 不受影响。

**R1（完成态优先）在 v2 下仍成立**：A 判过期（`expire():273-282` 从不写 `closedAt`），B 已完成（`closedAt = T`）。合并后两设备都是 `status = .expired` + `closedAt = T`（A 没碰该字段，CloudKit 只推变更字段）→ 都命中硬终态规则 → 都提升为 `.completed` → 一致、完成态胜出、一轮收敛、无 echo。

**`.expired` 为什么可以是软派生而不产生震荡**：过期由**时间**触发（`processKillTime:235` `now >= killDate`；`processCrossDay:146` / `processStaleOpenDaysBeforeToday:172` `day.date < today`），不由任务集合触发。时间判据单调，每台设备都会独立重推出同一个 `.expired`。唯一受可见集合影响的是 `expiredCount`，而 `mergeDay:550` 取 `max` → 只会向上自愈。

### 3.2 停止删除，改为保留 + 隐藏

**产品语义已裁决：选 a —— 保留但隐藏。** 终态日上"迟到的"任务不删除、不并入 complete、不丢回解冻区，而是**继续存在于 `tasks` 里、但被 getter 门控挡住不向用户展示**，等后续 GC（§3.7）稳定回收。

裁决给出的四条满足条件，逐条对应本方案的实现：

| 裁决要求 | 实现 |
|---|---|
| 不再向用户展示过期任务 | 三个 getter 在 `isTerminal` 时返回空（本节下方代码） |
| 不把未完成任务伪装成完成 | 任务 `zone` **不改**，不进 complete zone，`completedTasks`（`:55-57`）计数不受影响（红线 1） |
| 不立即丢失同步迟到的数据 | 停止 `modelContext.delete`，`tasks` 保持 raw（红线 2） |
| 可以由后续稳定 GC 回收 | §3.7，且 #20 已锁定 GC 独立验收 |

代价已在 §3.7 明示：**保留期内数据只增不减**，回收依赖 GC，而 GC 是有残余风险的受控删除（#20）。

**选路径 B（保留原 zone + getter 门控），否决路径 A（新增 `TaskZone.expired`）**，对比见 §3.5。

```swift
// Models/DayModel.swift:43-53  —— 改后
var sortedDraftTasks: [TaskItem] {
    guard !isTerminal else { return [] }
    return tasks.filter { $0.zone == .draft }.sorted { $0.order < $1.order }
}
var focusTask: TaskItem? {
    guard !isTerminal else { return nil }
    return tasks.filter { $0.zone == .focus }.min { $0.order < $1.order }
}
var frozenTasks: [TaskItem] {
    guard !isTerminal else { return [] }
    return tasks.filter { $0.zone == .frozen }.sorted { $0.order < $1.order }
}
```
`isTerminal` = `status == .expired || status == .completed`（新增**计算属性**，不入 schema）。

**红线 1：`completedTasks`（`:55-57`）绝不门控。** `StateMachine.swift:364` 与 `TodayViewModel.swift:240`（用于 `completedOrder` 递增）都消费它。

**红线 2：`tasks`（`:34-37`）必须保持 raw。** 修复层（`normalizeStatus:634-637`）、归档（`DataArchiveService.swift:212`）、习惯物化（`HabitTaskMaterializer.swift:149`）都依赖看到真相。

### 3.3 `doneFocus` 的"队列空"推断需要在闸门期降级（v2 新增）

审查 #3 的中毒路径不止修复层，**用户动作路径也会中毒**：
```swift
// Features/Today/TodayViewModel.swift:246-253
if let next = day.frozenTasks.first {
    next.zone = .focus
    next.startedAt = now
} else {
    day.status = .completed
    day.closedAt = now            // ← 若 frozen 尚未同步到达，这里写出的是伪证据
    day.isDraftZoneUnlocked = false
}
```
`TaskPostponeService.swift:423-434`、`:436-447` 同构。

用户动作不能被无限期阻塞（那是产品不可接受的），所以采取**保守降级**：闸门关闭时，"队列空"不足以支撑终态结论 —— 只移动任务、不写 `status = .completed` / `closedAt`，把日留在 `.execute`（无 focus）。随后：
- 若 frozen 到达 → 用户看到队列还有任务，符合事实
- 若 frozen 确实为空 → 闸门开启后的修复层按 `:669-678` 推出**软** `.completed`（无 `closedAt`，可纠正）

**#15 已裁决：接受延迟完成。** 闸门期内完成最后一个任务时：

| 动作 | 闸门期行为 |
|---|---|
| 任务移入 complete zone | **立即执行**（`:238-245` 的既有逻辑不变，用户动作必须有即时反馈） |
| 写 `closedAt` | **不写** |
| 标记硬 `.completed` | **不标** |
| UI 文案 | 显示"已完成最后一项，正在同步确认" |
| 最终状态 | 同步静止后由修复层按软派生规则补出（§3.1） |

裁决原文：不能为了即时 UI 牺牲 `closedAt` 的可信度。

延迟上界 = `maxWait`（§4.5）。新增 UI 文案一条，需入 `Resources/Localizable.xcstrings`（zh 为源语言，en 需补；键名建议 `today.done.awaiting_sync`）。`TaskPostponeService.swift:423-434`、`:436-447` 走同一降级，但它是无 UI 的服务层，只需不写 `closedAt` / `.completed`。

### 3.4 Phase A 改动清单

| 文件 | 行号 | 改动 |
|---|---|---|
| `Models/DayModel.swift` | 43-53 | 三个 getter 加 `isTerminal` 门控 |
| 同上 | 55-57 | **不动**（红线 1） |
| 同上 | 34-37 | **不动**（红线 2） |
| 同上 | 新增 | `var isTerminal: Bool { status == .expired \|\| status == .completed }` |
| 同上 | 59-61 | `hasSingleFocus` 是否门控 → 待裁决 #4 |
| `Services/StateMachine.swift` | 279 | 删除 `removeTasks(...)` 调用 |
| 同上 | 284-290 | `removeTasks` 失去调用者 → 整体删除 |
| 同上 | **689-691** | **删除修复侧 `closedAt` 回填**（§3.1） |
| 同上 | 633-705 | `normalizeStatus` 按 §3.1 三级判据重写 |
| `Features/Today/TodayViewModel.swift` | 246-253 | 闸门关闭时不写 `.completed` / `closedAt`（§3.3） |
| 同上 | 465-481 | `expire()` 去掉 `removeTasks`（`:469`）；`removeTasks`（`:475-481`）删除 |
| `Services/TaskPostponeService.swift` | 423-434, 436-447 | 同 §3.3 的降级 |
| `Resources/SettingsView.swift` | 1663-1665 | 删除过滤 + `forEach { modelContext.delete($0) }` |
| 同上 | 1659-1662, 1666 | 保留 `status = .expired` / `expiredCount` / 取消通知 |

### 3.5 路径对比

|  | 路径 A：新增 `TaskZone.expired` | **路径 B：getter 门控（选定）** |
|---|---|---|
| SwiftData schema | 不变（`TaskZone: String, Codable`，`Models/Enums/TaskZone.swift:1`） | 不变 |
| 需否开 V9 | 否（`WeekyiiPersistence.swift:1765-1783` 的 V8 只引用类型、不声明字段体，FROZEN 约束存储字段集合） | 否 |
| 迁移 stage | 不需要（**推断**，需 1 次 legacy-migration 测试，harness 在 `Tests/ModelTests.swift:372/:441/:1547`） | 不需要（无不确定性） |
| CloudKit schema 重推 | 不需要 | 不需要 |
| **CloudKit 线格式** | **变了**：`zone` 是同步的 String 属性，值域新增 `"expired"` 后未更新的设备解码失败 → 记录导入错误。多设备灰度期真实风险 | **不变** |
| 归档格式 | 变了（`DataArchiveService.swift:100`），旧版 App 无法导入新归档 → 需版本号提升 | 不变 |
| 穷举 switch 破坏面 | 9 处：`TaskPostponeService.swift:62,206,346,416`；`TaskZoneBadge.swift:19,28`；`PendingViewModel.swift:571`；`PendingWeekDetailView.swift:450`；`WeekTopology.swift:206`（`TaskZone` 无 `CaseIterable`；全仓仅 `StateMachine.swift:284`、`TodayViewModel.swift:475` 用 `[TaskZone]`） | 0 处 |
| 终态复活问题 | 自动消失（`hasOpen:639` 不含新 zone） | 需 §3.1 —— **但该工作因 R1 无论如何都要做**，故路径 B 额外成本为 0 |

### 3.6 v2 新发现：getter 门控会让现有测试断言退化为同义反复

`Tests/ModelTests.swift:3890-3893`：
```swift
XCTAssertEqual(todayDay.status, .completed)     // :3890
XCTAssertEqual(todayDay.closedAt, now)          // :3891
XCTAssertNil(todayDay.focusTask)                // :3892  ← 门控后恒真
XCTAssertTrue(todayDay.frozenTasks.isEmpty)     // :3893  ← 门控后恒真
```
`:3890` 已确立该日是 `.completed`，于是 `:3892`/`:3893` 在门控后**无论真实数据如何都会通过**。测试仍在跑，但已不再检验它原本要检验的不变量（"顺延走 focus 后源日队列确实清空"）。

这是静默的验证能力损失，编译与测试结果都不会报警。处置：把这类断言改为 raw 形式 `todayDay.tasks.filter { $0.zone == .focus }`。

**需逐条审计的候选**（在终态日上用 getter 断言"为空/为 nil"的位置）：`Tests/ModelTests.swift:3892-3893`（已确认）、`:3218`、`:3825-3829`；`Tests/StateMachineTests.swift:1171-1172`、`:956-957`、`:1056-1057`。复现命令：
```
grep -n 'focusTask\|frozenTasks\|sortedDraftTasks\|completedTasks' Tests/*.swift
```
逐条核对其所在测试的 `day.status` 是否终态。**列为 Phase A 的强制交付项，不是可选项。**

### 3.7 保留窗口 / GC（v3.1：#20 已裁决）

Phase A 停删后数据只增不减，必须有回收。

**核心约束：GC 会把 Phase A 消除的危险重新引入** —— 它又是一次"本机判断 → 全局不可逆删除"。因此必须同时满足两条：
1. **触发条件是同步字段的纯函数**，不读 `UserDefaults`、不读 `AppState`、不读设备时钟的"今天"
2. **只在 `syncedWritesAllowed == true` 时执行**（§4.2.1 的唯一数据闸门）

具体规则：
```
删除对象：day.status == .expired 且 day.date < 回收线 的日里，zone ∈ {draft, focus, frozen} 的 TaskItem
                                        （及其 cascade 的 TaskStep / TaskAttachment，见 TaskItem.swift:16-19）
不删：DayModel 本身（Past 需要 expiredCount / completedTasks）
不删：zone == .complete 的任务（AGENTS.md：Past 保留完成详情）
回收线：当前周 startDate - N 周，N = 8
```

**关于"回收线依赖设备时区"的精确评估**（这是我能给出的最强论证，不是回避）：回收线经 `timeProvider.today` → 设备本地时区，跨时区设备最多相差约 1 天。N = 8 周意味着边界有 7 天余量，**时区分歧不可能让两台设备对同一天的判断反复翻转**；最坏情况是"某台设备提前不到 1 天执行了删除"，删除经 CloudKit 传播后另一台也接受 —— 结果是单向的、一次性的，**不构成震荡**。

因此：**GC 不依赖 Phase D。** 但 N 必须 ≥ 2 周，否则余量被吃光。

**关于 tombstone（v3 修正，审查第 2 轮点 5）。** v2 写的是"不需要 tombstone"，**该结论撤回**。v2 的论证只证明了"相同完整输入下结果一致"，这不能覆盖以下场景：

```
设备 A：在线，GC 到期，删除过期日的开放任务
设备 B：长期离线，本地仍持有这些任务，且期间修改过其中某条
设备 B 重新上线 → 把修改过的任务重新上传
```

此时 A 的删除与 B 的写入冲突。"`NSPersistentCloudKitContainer` 下服务端删除通常胜出"**不是安全证明**，是经验观察，且本方案没有任何生产数据可验证它。

v3 的准确表述：

> **GC 是有边界风险的受控删除，不是绝对安全删除。离线旧设备重新上传属于已知未解决场景。**

边界风险的收敛依据（这些是真的，但只降低概率、不构成证明）：
- 回收线设在 8 周前 → 一条任务要在被删后仍被离线设备重新上传，该设备必须离线跨越整个 8 周窗口
- 被删的是 `.expired` 日的开放任务，正常路径下没有任何功能会重建它们（`HabitTaskMaterializer:138` 水位线守卫 + `:149` dup 检查）
- GC 只在闸门确认静止后执行（§4.2.1），此刻本地视图是完整的

**#20 已裁决：接受"受控删除 + 已知残余风险"，前提是在当前 V8 冻结、不引入 tombstone 的条件下。** 裁决要求以下五句必须原样进入本文与代码注释，缺一句都不算交付：

1. **GC 不是绝对安全**
2. **离线设备跨越回收窗口后重新上线，任务可能复活**
3. **这是已知数据一致性风险**
4. **GC 必须独立于 Phase A/B 验收**（不与 A、B 同轮提交、同轮验收，见 §13.6）
5. **不得对外宣称"删除绝不复活"**

裁决同时明确：**如果未来产品要求绝对防复活，再单独设计 tombstone / V9，不在本轮硬塞进来。** 因此本节不设计墓碑，也不把墓碑列为 Phase A/B 的前置。

**是否与 Phase A 同轮**：不同轮，N = 8 周（待裁决 #6，v2 建议三轮未被推翻，视为默认采纳）。"独立验收"另由 #20 第 4 条锁定为硬约束。

---

## 4. Phase B：同步静止闸门（v2 重写）

### 4.1 v1 的收敛论证错在哪

v1 说："`normalizeStatus` 等状态写入是设备无关的纯函数，所以放行。"

**这个推理无效。** 函数设备无关 ≠ 输出设备无关，因为**输入是本地可见集合**，部分同步期两台设备的输入不同。我把"同样的函数"偷换成了"同样的输入"。审查 #2 指出的五个位置全部命中这个错误。

正确的收敛条件是两个，缺一不可：
- **判据确定性**：函数不读设备本地状态
- **输入完整性**：函数读取的同步数据已全部到达

Phase A 解决前者（§3.1 的三级判据不读 `UserDefaults`、不读 `Date()`）。**只有闸门能解决后者。** 所以闸门必须覆盖全部 Tier-2 写入，不能只覆盖删除。

### 4.2 fail-closed，判据用 StoreMode 而非测试标志

审查 #1 建议"生产 fail-closed、测试放宽"。接受结论，但**换一个更好的判据**：仓库里已经有"是否存在远端对端"的唯一真源 —— `WeekyiiPersistence.StoreMode`：

```swift
// App/WeekyiiPersistence.swift:11-24
enum StoreMode: Equatable {
    case production
    case localOnly
    case inMemory
    var cloudKitContainerIdentifier: String? {
        switch self {
        case .production:            return WeekyiiPersistence.cloudKitContainerIdentifier
        case .localOnly, .inMemory:  return nil
        }
    }
}
// :89-91
static func launchStoreMode(environment: [String: String]) -> StoreMode {
    environment["XCTestConfigurationFilePath"] == nil ? .production : .localOnly
}
// :121-137  cloudKitDatabase 由此推导；.inMemory 直接 .none（:124）
```

`.localOnly` / `.inMemory` ⟺ `cloudKitDatabase == .none` ⟺ **物理上不存在远端对端** ⟹ 放行是安全的，且不是"为测试开后门"，是"没有需要同步的对象"。

好处：**不需要任何测试替身或环境判断**。单元测试走 `.localOnly`（`:90`），UI 测试走 `.inMemory`（`WeekyiiApp.swift:500-513`），二者自动 fail-open；生产走 `.production`，自动 fail-closed。

#### 4.2.1 v3.1：四态保留，三级谓词塌缩为单一谓词（#18 裁决）

演进：v2 = 一个布尔（错，`maxWait` 放行全部）→ v3 = 三级谓词（错，`noInboundChannel` 放行 Tier-2a）→ **v3.1 = 四态事实描述 + 单一数据闸门**。

`SyncSettlement` 四态保留，因为它描述的是**事实**（有没有对端、数据到齐没有），这个分类本身没有争议；被否决的是"事实 → 权限"的映射。

```swift
enum SyncSettlement {
    case noRemotePeer        // storeMode != .production：物理上不存在对端
    case settled             // .available + 零在飞事件 + setup 成功 + quiet 期满
    case noInboundChannel    // .noAccount / .restricted：当下不可能有导入到达
    case unsettled           // 其余一切（含 .checking / .temporarilyUnavailable / .unknown / .failed / 在飞 / quiet 未满）
}
```

| 状态 | Tier-1（本机） | Tier-2（**任何** SwiftData 同步字段写入） | 何时出现 |
|---|---|---|---|
| `noRemotePeer` | ✅ | ✅ | `.localOnly` / `.inMemory`。**含 #18 之后由 `.noAccount`/`.restricted` 映射过来的生产设备（§4.2.2）** |
| `settled` | ✅ | ✅ | 生产云库 + 账号可用 + CloudKit 静止 |
| `noInboundChannel` | ✅ | **❌** | 生产云库 + `.noAccount`/`.restricted`。**是过渡态，出口是重启（见下）** |
| `unsettled` | ✅ | **❌** | `.checking` / 账号暂时不可达 / 有在飞事件 / quiet 未满 / setup 未确认 / **`storeMode == .cloudDetached`（§4.2.2）** |

**`maxWait` 不出现在这张表里。** 按 #18 裁决原文"最多只恢复安全的本地展示和通知逻辑，不恢复会写 SwiftData 同步字段的逻辑" —— 本地展示与通知**本来就是 Tier-1**，恒放行，不需要 `maxWait` 来恢复。所以 `maxWait` 只剩占位页/只读降级策略的产品时限用途；它不改变任何 `settlement` 或同步字段写入权限。

```swift
func settlement(now: Date) -> SyncSettlement {
    guard storeMode != .cloudDetached else { return .unsettled }    // §4.2.2：只读云库，对端可能存在
    guard !storeMode.hasNoRemotePeer else { return .noRemotePeer }  // .localOnly / .inMemory
    guard hasStarted, monitorStartedAt != nil else { return .unsettled }   // .production 却拿不到 monitor = 异常

    switch accountState {
    case .checking:                                       return .unsettled
    case .unavailable(.noAccount), .unavailable(.restricted):
        return .noInboundChannel
    case .unavailable(.temporarilyUnavailable), .unavailable(.unknown), .failed:
        return .unsettled
    case .available:                                      break
    }

    guard inFlightEvents.isEmpty else { return .unsettled }     // §4.10
    guard setupSucceeded else { return .unsettled }             // §4.10 + §4.12 基线
    guard let quietStart = lastEventEndedAt else { return .unsettled }   // §4.12 基线
    guard now.timeIntervalSince(quietStart) >= quietPeriod else { return .unsettled }
    return .settled
}

var localReconcileAllowed: Bool { true }                        // Tier-1 恒定放行

/// 唯一的数据闸门。#18 后 Tier-2a 与 Tier-2b 的放行条件相同，故合并为一个谓词
func syncedWritesAllowed(now: Date) -> Bool {
    switch settlement(now: now) {
    case .noRemotePeer, .settled:       return true
    case .noInboundChannel, .unsettled: return false
    }
}
```

**为什么不保留 `derivedWritesAllowed` / `irreversibleOpsAllowed` 两个名字**：二者在 v3.1 下恒等，保留等于制造"看起来可以分开"的假象。Tier-2a / Tier-2b 的**分类表保留**（§4.2.3），因为它承担三件与闸门无关的事：GC 前置条件的表述、§13 的分级断言、以及记录"哪些操作不可逆"这一事实本身。

**为什么 `.noAccount` / `.restricted` 下必须关闭全部 Tier-2（#18 裁决的核心理由，用户原文）**：`.noAccount` 只代表"当前没有入站通道"，**不代表本地 store 已经拥有完整数据**。而 Tier-2a 并不都可逆：`processKillTime` 会把日标为 `.expired`，`.expired` 在 §3.1 下仍具有粘性（`closedAt == nil` 时"保持 `.expired`"），且 getter 门控会立刻隐藏该日内容；`createPresentWeek` / `fetchOrCreateTodayDay` 可能制造重复同步对象；习惯物化可能在迟到任务未到达时重复创建；计数器可能被暂时覆盖成较小值。**这些都会随账号恢复后的首次导出进入云端。**

`persistentStoreURL()`（`WeekyiiPersistence.swift:148-153`）是单一固定路径、与登录哪个账号无关，所以 `.noAccount` ≠ "store 是空的"，而 = "store 里可能仍装着账号 A 已镜像的记录，只是现在没有账号"。v2 的 `return true` 与 v3 的"2a 放行"均撤回。

#### 4.2.2 #18 的配套：未登录设备改走独立本地库

裁决原文："如果未登录设备必须可用，应切换到独立的 `.localOnly` store，而不是继续对云 store 执行 Tier-2a。" 这需要改 `launchStoreMode`。

**先补一个 v3.1 起草时漏掉的洞（本节最关键的一段）。** #19 的边界 1 与 §7.2 的身份不一致路径都会打开一个**只读的、`cloudKitDatabase == .none` 的容器**，而它打开的文件是**云库** `Weekyii.store`（`WeekyiiPersistence.swift:148-153`，单一路径、与账号无关）。若这个容器上报 `storeMode == .localOnly`，`settlement()` 的第一行 `guard storeMode == .production else { return .noRemotePeer }` 会**直接放行全部写入** —— 这正是 #18 否决的那个错误的复现，而且是在一个连写权限都没有的容器上放行，等于自相矛盾。

**修法：`StoreMode` 增加第四态 `cloudDetached`**（云库来源、无 CloudKit、只读）。它的存在就是把 #18 的教训写进类型系统：**"没有入站通道" ≠ "没有对端"**，这两件事必须由不同的枚举值表达，不能靠调用方记得传对参数。为满足源库零写入红线，方案 1 对源库做进程级临时副本后再打开。

```swift
// App/WeekyiiPersistence.swift:11-24 —— 改后
enum StoreMode: Equatable {
    case production        // Weekyii.store + .private(id)，可写
    case localOnly         // Weekyii.local.store（§7.1.1）+ .none，可写，物理上无对端
    case inMemory          // 内存 + .none，可写，物理上无对端（UI 测试）
    case cloudDetached     // Weekyii.store + .none + allowsSave:false；对端可能存在，只是够不着

    var cloudKitContainerIdentifier: String? {
        switch self {
        case .production:                      return WeekyiiPersistence.cloudKitContainerIdentifier
        case .localOnly, .inMemory,
             .cloudDetached:                   return nil
        }
    }
    /// 物理上是否不存在远端对端（= 闸门能否直接全开的唯一依据）
    var hasNoRemotePeer: Bool { self == .localOnly || self == .inMemory }
    var allowsSave: Bool { self != .cloudDetached }
}
```

`makeModelContainer`（`:116-146`）的 `:134` `allowsSave: true` 改为 `allowsSave: resolvedMode.allowsSave`；`:126` 的 URL 选择按 §7.1.1 分叉（`localOnly` → `Weekyii.local.store`，其余 → `Weekyii.store`）。

`settlement()`（§4.2.1，已同步更新）的前两行即为该枚举的消费点：`cloudDetached` 恒 `unsettled`，`hasNoRemotePeer` 才返回 `noRemotePeer`。因此 `cloudDetached` 下 `syncedWritesAllowed == false`，**`maxWait` 也不会改变它**（与 §4.5 一致）。

**`StoreMode` 的改动面（已核实，很小）**：`WeekyiiPersistence.swift:11-24`（枚举）、`:89-91`（`launchStoreMode` → `resolveStoreMode`）、`:121-137`（`makeModelContainer` 的配置分支，注意 `:123` 是 `if` 不是 `switch`，不破坏穷举）；测试侧 `Tests/ModelTests.swift:71-82`（三个 `cloudKitContainerIdentifier` 断言 + 两个 `launchStoreMode` 断言）需补 `cloudDetached` 的一行断言，`:288`、`:307`、`:337`、`:348` 四处显式传 `.localOnly` 的用例**不受影响**。

```swift
// App/WeekyiiPersistence.swift:89-91 现状：只看 XCTest
static func launchStoreMode(environment: [String: String]) -> StoreMode {
    environment["XCTestConfigurationFilePath"] == nil ? .production : .localOnly
}

// v3.1：增加账号输入（来自 §7.2 阶段 1 的 CKAccountStatus）
static func resolveStoreMode(
    environment: [String: String],
    accountStatus: CKAccountStatus?,      // nil = 解析失败/超时
    identityConfirmed: Bool,              // §7.2 阶段 1：userRecordID 比对结果
    cloudSyncEnabled: Bool                // §7.1 的用户开关，设备本地
) -> StoreMode {
    guard environment["XCTestConfigurationFilePath"] == nil else { return .localOnly }
    guard cloudSyncEnabled else { return .localOnly }
    guard identityConfirmed else { return .cloudDetached }   // 身份未确认 → 只读云库
    switch accountStatus {
    case .noAccount, .restricted:  return .localOnly      // ← #18：切库，不是关闸门
    case .available:               return .production
    case .temporarilyUnavailable,
         .couldNotDetermine,
         .none:                    return .cloudDetached   // 不确定 → 只读云库，不新建第二份数据
    @unknown default:              return .cloudDetached
    }
}
```

**为什么"不确定"必须落 `cloudDetached` 而不是 `.localOnly`**：`.temporarilyUnavailable` / `.couldNotDetermine` / 解析超时都无法区分"这台设备从未登录"与"这台设备有云端数据但此刻够不着"。若误判为 `.localOnly`，App 会在 `Weekyii.local.store` 上**新建一套与云端并行的数据集**，日后账号恢复时两份数据需要走 §7.1.1 的二选一，用户可能丢失其中一份。`cloudDetached` 的代价小得多：只是本进程只读、Tier-2 不执行，重启后账号可达即自动恢复，**不产生第二份数据**。

**为什么不是 `.production`**（v3.1 起草时的写法，已改）：#19 边界 1 明确要求超时只能进入**只读降级**。若超时仍建 `.production` 容器，就等于用一个身份未确认的会话开始向 `.private(id)` 导出 —— 正是 #17 裁决禁止的事。`cloudDetached` 是同时满足"不新建第二份数据"与"身份未确认不得导出"的唯一取值。

这条规则与 #17/#19 的阶段 1 天然合流：账号解析**本来就是**建容器前的必经步骤，它的结果现在同时决定 `cloudKitDatabase`、`allowsSave` 与 store 文件路径。

**由此产生的用户可见流程（必须在设置页说明）**：从未登录 iCloud 的设备，其数据落在 `Weekyii.local.store`；日后登录 iCloud 时**不会自动合并**，而是走 §7.1.1 的"本地 → 云"二选一流程（以本机为准 / 以云端为准）。这是 #16"禁止隐式合并"的直接推论，不是新增限制。

**运行中退出 iCloud（`.available → .noAccount`）**：容器已按 `.production` 建好且 `cloudKitDatabase` 构造时固定（`:127-136`），运行中无法改 → `settlement` 落 `noInboundChannel` → Tier-1 only + **提示重启**。重启后 `resolveStoreMode` 返回 `.localOnly` → 走本地库 → `noRemotePeer` → 全开。与 #19 的进程级终止边界是同一条规则。

#### 4.2.3 Tier-2a / Tier-2b 归类（v3.1：分类保留，闸门不再区分）

**重要**：#18 之后两档的**放行条件完全相同**（都只在 `noRemotePeer` / `settled` 放行）。分类表保留下来不是为了门控，而是为了三件事：①§3.7 GC 的前置条件表述；②§13 的分级断言；③把"哪些操作不可逆"这一事实记录在案，避免后人误判。

**Tier-2b（不可逆 / 终态语义写入）**

| 位置 | 动作 | v3 归类 | v3.1 |
|---|---|---|---|
| `StateMachine.swift:464-504` `mergeDuplicateWeeksAndDays` | 删除在 `:486`、`:498`，cascade 放大 | 2b | 2b |
| `StateMachine.swift:506-529` `mergeDuplicateBuiltInTaskTypes` | 删除在 `:523` | 2b | 2b |
| `StateMachine.swift:109` `processExpiredSuspendedTasks` | 含删除 | 2b | 2b |
| §3.7 GC | 受控删除 | 2b | 2b |
| `TaskTypeDefinition.swift:100-120` 播种的**插入部分** | 本身不删除，但会制造需要靠删除收拾的重复（§1.6） | 2b | 2b |
| **`StateMachine.swift:108` `processKillTime`** | 把日标为 `.expired` | 2a | **2b（改判）** |
| **`:105` `processCrossDay`** | 同上（跨日过期） | 2a | **2b（改判）** |
| **`:104` `processStaleOpenDaysBeforeToday`** | 同上（补扫历史开放日） | 2a | **2b（改判）** |

Phase A 之后 `StateMachine.swift:288`、`TodayViewModel.swift:479`、`SettingsView.swift:1665` 三处 `modelContext.delete` 全部消失，Tier-2b 的删除清单收敛到上表前四行。

**改判理由（采纳用户意见）**：这三项是**终态语义写入**，不是普通派生写入。`.expired` 在 §3.1 的规则下具有粘性（`closedAt == nil` 时"保持 `.expired`"），且 §3.2 的 getter 门控会在写入的瞬间隐藏该日的 draft/focus/frozen 内容。虽然 Phase A 已停止删除、数据本身可恢复，但**状态一旦写错就会自我维持**，且 §3.1 只保证 `closedAt` 出现时能纠正它 —— 若部分同步期误判过期而该日其实在另一台设备上仍 `.execute`，本地看不到反证。归入 2b 后，过期判定只在 `settled` 时发生。

**代价（必须明示）**：未静止期间**日不会过期**。一台 `.production + unsettled` 的设备上，昨天的 `execute` 日会持续显示为执行中，直到静止。这是 fail-closed 的直接后果，与 §4.7 的降级窗口合并描述。

**Tier-2a（派生写入 —— 可纠正，但仍只在 `settled` 时执行）**

| 位置 | 动作 | 可纠正性 |
|---|---|---|
| `StateMachine.swift:106` `processCrossWeek` | `week.status`、造周 | 造出的重复周只能靠 2b 的 merge 收拾 → 事实上不可逆 |
| `:107` `syncTodayDefaultKillTimeIfNeeded` | 造日、kill time 字段 | 同上；kill time 另有 Phase C 处理 |
| `:118` `refreshWeekSummaryMetrics` | 三个同步计数器 | 可纠正（下一轮按完整视图重算），但错误值会先导出一次 |
| `:413` `normalizeWeekStatuses`、`:417-427` 每日规范化 | status / order / zone | 可纠正 |
| `:429` `ensureTodayExists` | 造日 | 同造周 |
| `WeekyiiApp.swift:406-407` `HabitTaskMaterializer.sync` | 造任务、写水位线 | 重复任务只能靠 dup 检查（`:149`）事后避免 |
| `TaskTypeDefinition.swift:107-115` 播种的**回填部分** | 补 `taskTypeIdRaw` | 幂等，两端各跑一次结果一致 |

**v3 在此处的"⚠️ 有意偏离审查清单 3 项"标注已删除**：#18 否决后偏离不复存在，上表全部只在 `settled` / `noRemotePeer` 时执行。

#### 4.2.4 `repair` 不需拆参（v3.1 撤回 v3 的加参）

v3 曾要求 `repair(referenceDate:allowsIrreversible:)`，理由是"两档闸门放行时刻不同，而 `repair` 内部同时含 2a 与 2b"。**该前提已消失，加参撤回。**

- `DataInvariantRepairing` 协议（`StateMachine.swift:47-49`）**不改**
- `repair` 实现（`:396-437`）**一行不改**
- 门控只发生在调用点 `StateMachine.swift:111`：`syncedWritesAllowed == false` 时整个 `repair` 不调用
- `Tests/StateMachineTests.swift:795-822` 的 `mergeDuplicateBuiltInTaskTypes` 用例因此**完全不受影响**（v3 曾担心默认值问题，现在没有默认值问题）

这是本方案对同一处代码的第四次判定：v1 拆两半（理由错）→ v2 整体作废（结论对、理由不全）→ v3 重新拆参（理由对但前提后被否决）→ **v3.1 不拆（前提消失）**。记录在此是为了防止实施时按旧版本改。

### 4.3 reconcile 拆 Tier-1 / Tier-2

放弃 v1 的逐函数门控，改为**按写入目标分层**：

**Tier-1（永远执行）—— 只写设备本地、不写任何 SwiftData 同步字段**
- `AppState` 的 `markRollover` / `bumpStateTransitionRevision`（`UserDefaults`，`App/AppState.swift:13`）
- 通知调度（`WeekyiiApp.swift:438-464`，UNNotificationCenter 本地）
- Widget 快照（`WeekyiiApp.swift:646-655`，App Group `UserDefaults`）
- Live Activity（`WeekyiiApp.swift:410-416`）

**Tier-2（仅 `syncedWritesAllowed == true` 时执行）—— 任何写入 SwiftData 同步字段的动作**

| 位置 | 写什么 | v1 判定 | v2 判定 | v3 档位 | **v3.1 档位** |
|---|---|---|---|---|---|
| `StateMachine.swift:104` `processStaleOpenDaysBeforeToday` | `day.status` / `expiredCount` | 放行 | Tier-2 | 2a | **2b（终态语义）** |
| `:105` `processCrossDay` | 同上 | 放行 | Tier-2 | 2a | **2b（终态语义）** |
| `:106` `processCrossWeek` | `week.status`、造周 | 拆分 | Tier-2（整体） | 2a | 2a |
| `:107` `syncTodayDefaultKillTimeIfNeeded` | `killTimeHour/Minute`、造日 | 门控 | Tier-2 | 2a | 2a |
| `:108` `processKillTime` | `day.status` | 放行 | Tier-2 | 2a | **2b（终态语义）** |
| `:109` `processExpiredSuspendedTasks` | 删除 | 门控 | Tier-2 | 2b | 2b |
| `:111` `repair` | status / order / zone / 计数器 / 删除 / 造日 | 拆分 | Tier-2（整体） | 2a+2b 混合，需拆参 | **整体门控，不拆参（§4.2.4）** |
| `:118` `refreshWeekSummaryMetrics` | 三个同步计数器 | 放行 | Tier-2 | 2a | 2a |
| `WeekyiiApp.swift:406-407` `HabitTaskMaterializer.sync` | 造任务、写水位线 | 未覆盖 | Tier-2 | 2a | 2a |
| `WeekyiiPersistence.swift:144` + `TaskTypeDefinition.swift:95` 播种 | 造内置类型、回填 `taskTypeIdRaw` | 未覆盖 | 未覆盖 | 插入 2b / 回填 2a | 同 v3（§4.11） |

v1 拆 repair 的**理由**（认为规范化半天然安全）仍然作废，见 §4.1。v3 因两档放行时刻不同而重新拆参，该前提已被 #18 消除，见 §4.2.4。v1 待裁决 #5（`closedAt` 回填取值）已因 §3.1 直接删除而消解。

实现形态（v3.1：回到单参数）：

```swift
func reconcile(now: Date, force: Bool, allowSyncedWrites: Bool = true)
```

- `allowSyncedWrites == false`：`:104-109`、`:111`、`:118` **全部跳过**，直接到 `:119` 只做 Tier-1 收尾
- `allowSyncedWrites == true`：全部执行，函数内部逻辑一行不改
- 默认值 `true` 保证 `Tests/StateMachineTests.swift:319,730,731,1460,1474,1484,1498` 的既有两参调用继续可编译、行为不变；但**生产调用点必须显式传值**，不吃默认
- 控制只发生在调用点，被跳过的函数内部一行不改，以最小化波及面
- v3 的 `allowDerivedWrites` / `allowIrreversibleOps` 两参**作废**，不要按 v3 实施

### 4.4 引导期修复必须移除，不是降级

`WeekyiiPersistence.swift:107` 的 `repair` 跑在容器刚建好、monitor 尚不存在（§1.6）的时刻，**没有任何信号可用来判断是否静止**。v1 的方案是传 `allowDestructive: false`，v2 认为不够：按 §4.3，整个 repair 都是 Tier-2，而此刻闸门必然关闭 → 传参结果就是"什么都不做"。

**所以直接删掉 `:107` 这一行**，把首次修复交给第一次闸门开启后的 reconcile（`WeekyiiApp.swift:544` 的 `.launch` 触发会在闸门开启后重跑）。附带收益：启动路径少一次全表 fetch + 全表 save（与已知的启动性能痛点同向，见项目记忆 launch-perf-audit）。

`validateContainerConsistency`（`:108`，实现 `:198-205`）保留，但按 §6 的 D1 护栏改为不阻断启动。

### 4.5 `maxWait` 在 v3.1 不再是数据闸门（#18 裁决的直接后果）

**撤回**：v3 说"`maxWait` 只放行 Tier-2a"。#18 裁决原文是"`maxWait`：最多只恢复安全的本地展示和通知逻辑，不恢复会写 SwiftData 同步字段的逻辑"。而本地展示（读）与通知调度**本来就是 Tier-1、恒放行**，不需要超时来恢复。所以：

> **`maxWait` 对 `syncedWritesAllowed` 没有任何影响。它不再是数据闸门。**

它在 v3.1 只剩两个用途，都与数据安全无关：
1. **#19 甲方案的占位页时长上界**（§7.2.1）：阶段 1 不建容器、先解析账号；账号在 `maxWait` 内仍未确认 → 降级为只读容器，让用户至少能看到既有数据。**只读，不写任何同步字段**，且按 #19 的进程级终止边界，本进程内不再升级
2. **启动等待的宽限期**：Monitor 完全没观察到任何 CloudKit 事件时，决定何时停止等待并保持只读/未结算；它不是同步完成证明

建议值仍为 60s，但它的语义已经从"多久后放开写入"变成"多久后停止等待、进入只读降级"。

**仍然需要 `maxWait` 的理由**：框架不保证冷启动后短时间内一定发出 import 事件（无变更时可能长时间静默）。没有上界，#19 甲方案的占位页会无限期停在那里。

**长期 `unsettled` 的后果（#18 之后重新界定）**

`noInboundChannel` 已不再是稳态（§4.2.2：冷启动即切本地库，运行中退出则提示重启）。剩下会长期 `unsettled` 的只有：`.temporarilyUnavailable` / `.couldNotDetermine` / `.failed` / 事件长期在飞。此时：

- 已有数据的设备：能看、能操作当天任务流，但**日不会过期、不会造新周、习惯不会物化、重复不会被合并、计数器不更新**
- 全新安装 + 账号不可达的设备：**首页为空**，直到账号可达

三条出口，按优先级：
1. **账号自行恢复**（绝大多数 `.temporarilyUnavailable` 是网络瞬断）→ `settled` → 全部补齐
2. **设置页手动重试**：复用 `SettingsView.swift:632-646` 的状态组件，加一个"重试"按钮调 `refreshAccountStatus()`（`CloudSyncMonitor.swift:190-211`，已是 async，无需新代码）
3. **用户主动关闭同步**（§7.1 的 `cloudSyncEnabled`）→ 重启 → `.localOnly` → `Weekyii.local.store` → `noRemotePeer` → 完全可用。**但对已有云端数据的设备，这等于放弃云端副本**，UI 必须明确警告，且必须走 §7.1.1 的"云 → 本地"迁移流程而不是静默切库

第 3 条是最后的逃生口，不是常规路径。设置页需要一行持久说明当前处于哪一档（→ 已定项 #14：复用既有状态组件，不新设计）。

### 4.6 头号阻塞点：`markProcessed` 必须拆分

```swift
// Services/StateMachine.swift:102, 119
let lastProcessedBeforeRun = appState.lastProcessedDate      // :102
appState.markProcessed(at: now)                              // :119
// App/AppState.swift:42-47
func markProcessed(at date: Date) {
    lastProcessedDate = calendar.startOfDay(for: date)       // :44
    lastRolloverAt = date                                    // :45
```
闸门关闭时若仍执行 `:119`，`lastProcessedDate` 被推进到今天 → `syncTodayDefaultKillTimeIfNeeded` 的判据 `today > lastProcessedBeforeRun`（`:253`）当天**永假** → 今天的 kill time 静默停在模型默认 23:45（`DayModel.swift:11-12`）。

拆分：
```swift
protocol AppStateStore {
    func markRollover(at date: Date)     // 只写 lastRolloverAt：Tier-1，闸门期也写（维持节流）
    func markProcessed(at date: Date)    // 写 lastProcessedDate + lastRolloverAt：Tier-2
}
```
连带 conformer：`App/AppState.swift:4-69`、`Tests/StateMachineTests.swift:15`（`TestAppState`）、`Tests/ModelTests.swift:957`（`HabitTestAppState`）。

**为什么 `markRollover` 必须留在 Tier-1**：`shouldSkipReconcile`（`StateMachine.swift:377-384`）用 `lastRolloverAt` 的分钟键节流。闸门关闭期若连它也不写，每分钟 tick（`WeekyiiApp.swift:583-590`）都会触发一次全量 reconcile（只读，但仍全表 fetch）—— 与已知的启动性能痛点同向（见项目记忆 launch-perf-audit）。

跨日过期本身的损失有限：`processStaleOpenDaysBeforeToday`（`:167-180`）是无状态全量扫描，不依赖 `lastProcessedDate`，覆盖比 `processCrossDay` 更宽 —— 但 v3.1 已把三者一并归入 Tier-2b（§4.2.3），闸门期同样不跑，见 §4.7。

### 4.7 闸门期的功能降级（必须明示，不能藏）

v3 分两个窗口（因为两档谓词放行时刻不同）。**#18 之后只有一个窗口**：Tier-2 全有或全无。

**唯一窗口：`.production` 且未 `settled` —— 全部 Tier-2 不执行，Tier-1 照常**

用户可见的退化：
- 昨天的 `execute` 日**仍显示执行中且可操作**（过期判定已改判 Tier-2b，§4.2.3）
- 跨周时**不会出现新的 present week**，首页仍显示上一周
- 今天可能**还没有 today day** → 全新安装时首页为空
- 习惯任务今天**还没物化**
- 用户完成最后一个任务后当天**不会立刻显示已完成**（§3.3，文案见该节）
- 内置任务类型可能显示为兜底名（§4.11 第三步）
- 重复的周 / 日 / 内置类型**不会被合并**，可能看到两条相同的本周
- GC 不运行 → 保留窗口内的数据只增不减

以上全部在 `settled` 后的第一次 reconcile 自动补齐，无需用户操作。

**为什么这是正确取舍**：堆积是可恢复的，互删与错误终态不是。窗口长度由 CloudKit 决定，不由我们决定；能封顶的只有 #19 甲方案的占位页（`maxWait`），封不了"数据何时到齐"。

缓解手段：
- 只在**冷启动**武装 `maxWait`，`sceneActive`（`WeekyiiApp.swift:548-556`）不重新武装 → 日常切回 App 不受影响
- 首页在闸门期显示既有的 iCloud 状态行（`SettingsView.swift:632-646` 的组件复用）作为"正在同步"的可见解释（已定项 #14）
- 设置页需要一行持久说明当前档位与出口（§4.5 的三条出口）
- **未登录 iCloud 的设备根本不进入这个窗口**：`resolveStoreMode` 让它落 `.localOnly`（§4.2.2）→ `noRemotePeer` → 全开。这是 #18 用"切库"替代"放行"换来的关键收益

### 4.8 触发器与注入

```swift
// App/WeekyiiApp.swift:345-350
enum AppHealthTrigger: String {
    case launch, sceneActive, minuteTick, manualResync
    case remoteImport        // 新增
}
```
`:579` 改 `trigger: .remoteImport, force: true`；`:404` 的 force 条件加 `|| trigger == .remoteImport`。

两者都只绕过 `shouldSkipReconcile` 的节流，**都不绕过闸门** —— 闸门是数据安全边界，不是节流开关。`.manualResync`（用户手点）同样不绕过：用户点重同步通常正因为数据看起来不对，那是最不该执行 Tier-2 的时刻。

注入：`AppHealthCoordinator.init` 增加 `storeMode: WeekyiiPersistence.StoreMode` 与 `cloudSyncMonitor: (any CloudSyncSettling)?`。**这次不能给 fail-open 的默认值** —— 默认必须是 `.production` + `nil` → 关闭。

**v3.1 补注：默认值为什么仍选 `.production` 而不是 `.cloudDetached`。** 加了第 4 个 case 后，四个取值里有**两个是 fail-open 的**（`.localOnly` / `.inMemory`，因为 `hasNoRemotePeer == true` → §4.2.1 直接返回 `.noRemotePeer` → 全开）。所以默认值只能在 `.production` 与 `.cloudDetached` 之间选，二者都 fail-closed，但语义不同：`.cloudDetached` 断言"对端可能存在且容器只读"，而漏传 `storeMode` 的真实含义是"调用方忘了传"，此时容器**是可写的**。把可写容器标成 `.cloudDetached` 会让 `allowsSave` 的推导与实际配置矛盾。选 `.production` + `nil` monitor 的组合落到 §4.2.1 第三条 guard（`.production` 却拿不到 monitor = 异常）→ `.unsettled` → 关闭，且不与任何真实配置冲突。

兼容性代价：`Tests/StateMachineTests.swift:1250-1260` 的 6 参构造必须显式传 `.inMemory` 才能保持现有行为。这是有意的：让"放开"成为测试的显式声明，而不是生产的隐式默认。

`storeMode` 的**来源**是阶段 B0 的启动阶段 1（§7.2.3 ②），`AppHealthCoordinator` 只接收、不解析。它必须与 `makeModelContainer` 实际使用的那个值是同一个实例字段 —— 否则会出现"闸门按 `.localOnly` 全开，容器却按 `.production` 建"的错配。§13.2.0 的验收项覆盖了这一点。

### 4.9 Phase B0 / B 改动清单（v3.1）

**阶段 B0（硬前置，§9；不做则 #18 的"切库"是假的）**

| 文件 | 行号 | 改动 |
|---|---|---|
| `App/WeekyiiPersistence.swift` | **11-24** | **`StoreMode` 增第 4 个 case `cloudDetached`**；新增 `hasNoRemotePeer`、`allowsSave` 派生属性（§4.2.2）。`cloudKitContainerIdentifier` 的 `.localOnly, .inMemory` 分支扩为三 case |
| 同上 | **26-29** | **`LaunchState` 增 `case resolving`**（§7.2.3 ①），否则两阶段启动无法表达"账号解析中" |
| 同上 | **89-91** | **`launchStoreMode` → `resolveStoreMode(environment:accountStatus:identityConfirmed:cloudSyncEnabled:)`**（§4.2.2，#18 配套）。注意四个入参缺一不可：少 `identityConfirmed:` 就会在身份未确认时落 `.production`，违反 #17 |
| 同上 | **134** | `allowsSave` 由硬编码 `true` 改为 `storeMode.allowsSave`（§4.2.2）。`cloudDetached` 必须为 `false` |
| 同上 | **148-153** | **`persistentStoreURL()` 拆分为云库 / 本地库两条路径**（`Weekyii.store` / `Weekyii.local.store`，§7.1.1）。从 E-1 提前到 B0：`.localOnly` 若仍打开 `Weekyii.store`，等于在云库文件上以 `.none` 可写建数据，日后登录即隐式合并 —— 正是 #16 禁止的 |
| 同上 | **107** | **删除引导期 repair**（§4.4） |
| 同上 | **144** | **播种移出 `makeModelContainer`**，改为闸门开启后显式调用（§4.11）。这是只读容器能否构造出来的硬前置 |
| 同上 | 93-114 | `bootstrapPersistentContainer` 接受 storeMode 入参并回传，供上层注入 monitor |
| `App/WeekyiiApp.swift` | **514-518** | `_launchState` 由 `init()` 内同步赋值改为**异步**两阶段（#19 甲，§7.2.3 ②）；解析结果（`StoreMode`）存为实例字段 |
| 同上 | **523** | `switch launchState` 增 `.resolving` 分支 → 占位页（复用既有启动图） |
| 同上 | **619** | **`retryPersistentStore()` 必须显式传已解析的 `storeMode`**（§7.2.3 ③）。现状调无参 `bootstrapPersistentContainer()` → `launchStoreMode` → 恒 `.production`，重试即绕过 #18/#19 全部裁决 |
| 同上 | **629** | **`restoreLatestPersistentStoreSnapshot()` 同上**，且恢复目标 URL 也必须按 `storeMode` 选（§7.2.3 ③） |
| `Tests/ModelTests.swift` | 71-82 | `StoreMode` 相关构造补第 4 case 的覆盖（§4.2.2 的映射表逐行） |

**阶段 B（闸门本体）**

| 文件 | 行号 | 改动 |
|---|---|---|
| `Services/CloudSyncMonitor.swift` | 137-152 | 新增 `inFlightEvents: Set<String>`、`lastEventEndedAt`、`setupSucceeded`、`monitorStartedAt`、`storeMode`、`hasObservedCloudKitEvent` |
| 同上 | **137, 138** | **`setupSucceeded` / `lastEventEndedAt` 的初值改为基线值**，不再是 `false` / `nil`（§4.12，修 Monitor 启动前丢事件导致的永久死锁） |
| 同上 | 168-188 | `start()` 记录 `monitorStartedAt`；**新增 `markContainerLoaded(at:)`**，由容器成功创建后写入当前进程基线（§4.12） |
| 同上 | **213-238** | **`consume` 重写**：按 `event.identifier` 维护在飞集合；`lastEventEndedAt` 取 `max`；`.setup` 结果单独记录（§4.10） |
| 同上 | 141-143, 113-120 | `state` / `isWorking` 改为由在飞集合派生，修掉"导入中显示已同步"的既有缺陷 |
| 同上 | 新增 | `enum SyncSettlement` + `protocol CloudSyncSettling`（`settlement(now:)`、`localReconcileAllowed`、**`syncedWritesAllowed(now:)`**，§4.2.1）。v3 的三谓词版本作废 |
| `Services/StateMachine.swift` | 4-14 | `AppStateStore` 新增 `markRollover(at:)` |
| 同上 | **47-49** | **不改**（v3 曾要求加 `allowsIrreversible:`，§4.2.4 已撤回） |
| 同上 | 92-124 | 加 `allowSyncedWrites: Bool`；`false` 时 `:104-109`、`:111`、`:118` 全部跳过；`:119` 按其值选 `markRollover` 或 `markProcessed` |
| 同上 | **396-437** | **不改**（§4.2.4） |
| `Models/TaskTypeDefinition.swift` | **94-98** | **`load()` 不再调用 `seedBuiltInTypesIfNeeded`**（§4.11） |
| `App/AppState.swift` | 4-69 | 实现 `markRollover`，拆分 `markProcessed`；新增 `lastSyncedUserRecordID`（§7.3） |
| `App/WeekyiiApp.swift` | 345-350 | 新增 `.remoteImport` |
| 同上 | 370-391 | init 新增 `storeMode` + `cloudSyncMonitor`（`storeMode` 由 B0 的阶段 1 解析得出，此处只接收） |
| 同上 | 393-418 | 计算并下传 `syncedWritesAllowed`；`HabitTaskMaterializer.sync`（`:406-407`）纳入闸门 |
| 同上 | 404 | force 语义调整（加 `|| trigger == .remoteImport`，§4.8） |
| 同上 | 577-582, 635-644 | 改 `.remoteImport` / 注入 monitor |
| 同上 | 容器创建前后 | Monitor 先同步注册观察者；容器成功创建后调用 **`cloudSyncMonitor.markContainerLoaded(at:)`**，以当前进程基线避免初值死锁 |
| `Features/Pending/PendingViewModel.swift` | 206, 238 | `TaskTypeCatalog.load` 语义变化后确认仍正确（§4.11） |
| `Shared/Components/TaskEditorSheet.swift` | 281 | 同上 |
| `Resources/SettingsView.swift` | 1684-1693 | 补参 |
| `Tests/StateMachineTests.swift` | 15, 1250-1260 | `TestAppState` 补 conform；构造显式传 `.inMemory` |
| `Tests/ModelTests.swift` | 957, 1468-1505 | `HabitTestAppState` 补 conform；`:1494` 的 `load()` 测试需先显式播种 |

### 4.10 CloudSyncMonitor 改为追踪并发事件（审查第 2 轮点 3）

现状缺陷见 §1.8。v3 的判据必须同时满足四条：

1. **任意事件在飞 → 不稳定**
2. **所有事件结束后才开始计 quiet period**
3. **失败事件也必须刷新稳定状态**（否则在飞集合泄漏 → 闸门永不重开）
4. **import / export / setup 不能只看最后一个**

实现：

```swift
@ObservationIgnored private var inFlightEvents: Set<String> = []   // key = event.identifier
@ObservationIgnored private var lastEventEndedAt: Date?            // = max(所有已结束事件的 endDate)
@ObservationIgnored private var setupSucceeded = false

private func consume(_ notification: Notification) {
    guard let event = ... else { return }
    let key = event.identifier                       // ← v2 完全没读这个字段

    if event.endDate == nil {                          // 事件开始
        inFlightEvents.insert(key)
        eventState = .syncing
        return
    }

    inFlightEvents.remove(key)                         // 成功与失败都必须移除（第 3 条）
    if let end = event.endDate {
        lastEventEndedAt = max(lastEventEndedAt ?? end, end)   // 第 2、4 条：取最大，不是取最后
    }
    if event.type == .setup { setupSucceeded = event.succeeded }

    if event.succeeded {
        if event.type == .import { scheduleImportedChanges() }
        eventState = inFlightEvents.isEmpty ? .synced(event.endDate ?? Date()) : .syncing
    } else {
        eventState = .failed(...)
    }
}
```

要点：
- `eventState` 保留（设置页 UI 与 `CloudSyncState.resolve:35-58` 依赖它），但**闸门不读 `eventState`**，只读 `settlement(now:)`。这样 UI 改动面最小，而安全判据独立
- `eventState` 在仍有在飞事件时保持 `.syncing`，顺带修掉 §1.8 指出的"导入进行中显示已同步"
- `.setup` 失败必须让 `settled` 不可达：setup 没成功意味着 CloudKit schema 未就绪，此时任何"静止"判断都无意义
- `scheduleImportedChanges()` 仍只对 `.import` 成功触发（`:226-228` 语义不变）—— 它驱动的是 reconcile 重跑，与静止判据是两件事
- `deinit`（`:254-258`）无需改

**推断（需实测）**：Core Data 对同一事件发两次通知（start 时 `endDate == nil`，end 时带 `endDate`），且 `identifier` 在两次通知间稳定。这是 `NSPersistentCloudKitContainer.Event` 的文档语义，但本仓无生产数据验证过；若 `identifier` 不稳定，退路是改用 `(storeIdentifier, type, startDate)` 三元组做 key。

### 4.11 引导期播种（审查第 2 轮点 4）

证据见 §1.6。v3 的处理分三步：

**第一步：把播种移出容器构造。** 删除 `WeekyiiPersistence.swift:144`，改为由 `AppHealthCoordinator` 在闸门允许时显式调用。这同时是 #17 / #19 的**硬前置**（v3 新发现 3）：`TaskTypeDefinition.swift:118` 的 `try context.save()` 在 `allowsSave: false` 的容器上会抛错，而 `:144` 就在 `makeModelContainer` 内部 —— 不移出去，`cloudDetached` 只读容器（#17 身份未确认 / #19 边界 1 超时降级）根本构造不出来。**因此本步属阶段 B0，不属阶段 B。**

**第二步：拆开播种的两个动作，归入不同档位。**

```swift
// Models/TaskTypeDefinition.swift:100-120 现状是一个函数做两件事
```

| 子动作 | 行号 | 档位 | 理由 |
|---|---|---|---|
| 插入缺失的内置类型 | `:101-105` | **Tier-2b** | 判据 `existingIds` 依赖本地可见性；首次导入未到达时会插入重复，而重复只能靠 `mergeDuplicateBuiltInTaskTypes`（`:506-529`，删除在 `:523`）收拾 —— 即"制造需要不可逆操作来清理的状态" |
| 回填 `taskTypeIdRaw` | `:107-115` | **Tier-2a** | 幂等：只在字段为空时写入，写入值来自任务自身的 `taskType`，不依赖可见集合大小；两端各跑一次结果一致 |

**v3.1 补注（#18 的后果）**：上表的档位区分在 #18 裁决后**不再产生门控差异** —— Tier-2a 与 2b 现在由同一个 `syncedWritesAllowed` 开关控制（§4.2.1、§4.3），两个子动作要么一起跑、要么一起不跑。档位标注仍保留，用途有三个：①§3.7 的 GC 前置条件只看 2b；②§13.2 的断言按档位写；③记录"哪些动作不可逆"这一事实本身，供日后若拆分档位时直接取用。**不要把这个表读成"2a 会比 2b 早放行"。**

**第三步：修掉 `load()` 里的隐藏写。** `:95` 的 `try seedBuiltInTypesIfNeeded(in: context)` 必须删除，`load()` 变成纯读。理由：`load()` 被 `PendingViewModel.swift:206`、`:238`、`TaskEditorSheet.swift:281` 在任意时刻调用，**包括闸门期内**；只门控 `:144` 拦不住它。

空 catalog 的安全性（已核）：`definition(for:)`（`:122-124`）有三级兜底 —— 精确匹配 → `idRaw == regular` → `builtInFallback`（`:90-92`，一个纯内存构造的对象，不入库）；`SettingsView.swift:1415` 与 `TaskEditorSheet.swift:265` 走的也是 `builtInFallback`。所以"播种推迟到闸门后"最坏只是 UI 短暂显示兜底类型名，不会崩、不会写库。

删除 `:95` 与 `:144` 的测试影响面（**已逐条 Read 核实**）：

| 测试 | 行号 | 是否受影响 | 依据 |
|---|---|---|---|
| `test_taskTypeCatalogSeedsBuiltInDefinitions` | `Tests/ModelTests.swift:1464-1475` | 否 | `:1468` 显式播种 |
| `test_taskTypeCatalogResolvesCustomDefinitionAndFallback` | `:1477-1499` | 否 | `:1481` 显式播种后才在 `:1494` 调 `load()` |
| `test_taskMutationStoresCustomTaskTypeIdAndBaseKind` | `:1501-1531` | 否 | `:1505` 显式播种 |
| V6→V8 迁移 | `:412-428` | 否 | `:428` 只断言 `taskTypes.contains { $0.idRaw == "custom-v6" }`，不断言内置类型存在 |
| V7→V8 迁移 | `:481-496` | 否 | `:496` 同上，只断言 `custom-v7` |
| `mergeDuplicateBuiltInTaskTypes` | `Tests/StateMachineTests.swift:795-822` | 否，但**必须保持 `allowSyncedWrites` 默认 `true`**（§4.3 的唯一入参；v3 曾名 `allowsIrreversible`，§4.2.4 已撤回该名） | 该测试直接依赖 repair 的 merge pass；它是 Tier-2b 门控的现成回归护栏。若默认值改成 `false`，此测试会**静默通过而不再验证任何东西**（§13.2 的 getter 门控同型风险） |

即：现有测试全部自带显式播种或只断言自定义类型，**移除隐式播种不会打破任何一条**。这本身也说明 `:144` 的隐式播种在生产路径上是"替测试省事"的副产品，而不是被测试锁定的契约。

### 4.12 Monitor 启动前的事件丢失（方案 1 的最终实现）

原问题仍然成立：`NotificationCenter` 不重放历史通知，CloudKit 的 `.setup` 或首次 `.import` 可能在旧版 Monitor 注册观察者前已经结束。方案 1 不通过第二套 Core Data 栈补历史查询，而是把“当前进程必须先观察到事件”的边界编码进启动顺序与结算状态：

1. `CloudSyncMonitor.start()` 使用同步的 `addObserver(forName:object:queue:)` 注册块式观察者；正常应用分支在创建 `ModelContainer` 前启动 Monitor。
2. `CloudSyncMonitor.consume` 按 `event.identifier` 维护在飞事件集合，结束时间取最大值；失败事件也会从集合移除，`.setup` 失败会重新关闭 `setupSucceeded`。
3. 容器成功加载后调用 `markContainerLoaded(at:)`，把容器加载时刻作为当前进程基线；只要当前进程无失败事件且 quiet period 满足，生产库才可进入 `settled`。
4. `.cloudDetached` 永远是 `unsettled`，不能因为它打开的是本地文件而错误地返回 `noRemotePeer`。

这不是“恢复历史事件”的证明：进程被杀后，之前错过的通知无法由 SwiftData 公开 API 重建。因此这是方案 1 的明确边界——当前进程以可观测事件和 fail-closed 结算为准；若未来必须做到跨进程历史证明，需另起 Core Data/持久层迁移设计，不在本轮偷偷引入。

**空私有库**：不把“是否产生 `.import` 通知”当成放行依据。容器加载、账号身份、setup 事件、在飞集合和 quiet period 都由当前进程的状态决定；无法得到当前进程足够证据时继续 `unsettled`，不会因为 `maxWait` 自动打开同步字段写入。

**强制配套已落地**：

- 设置页显示 `settlement` 的具体 blocker 与 monitor diagnostics，能区分 `noRemotePeer`、`cloudDetached` 的 `unsettled`、账号问题、在飞事件和 quiet period。
- 事件只用于诊断和当前进程结算，不以“等够时间”替代同步事实。
- 方案 1 明确不使用 `NSPersistentCloudKitContainerEventRequest`，也不创建第二套共享 SQLite 的写容器。

**与 #19 甲方案的协同**：#19 定案后，阶段 1 就要创建 `CKContainer` 做 `fetchUserRecordID()`，Monitor 的 `start()` 自然被提到容器创建之前。这**缩小**了丢事件的窗口（阶段 2 建容器时观察者已就位），但**没有消除**它（AsyncSequence 的投递时机问题仍在）。所以基线规则是必需的，不是可选加固。

---

## 5. Phase C：kill time 去设备本地化

### C.1 幂等化（低成本，先做）
```swift
// 仅在日值仍为模型默认（DayModel.swift:11-12 = 23:45）时写入
guard todayDay.killTimeHour == 23, todayDay.killTimeMinute == 45,
      todayDay.followsDefaultKillTime else { return }
```
每设备对每天最多写一次；两设备默认不同时仍有一次拉锯，但不再每天重复。

### C.2 同步默认值本身（彻底解法）
启用已声明未用的 KVS（`Resources/Weekyii.entitlements:15-16`；全仓 `NSUbiquitousKeyValueStore` 零命中）镜像 `defaultKillTimeHour` / `defaultKillTimeMinute`。不改 SwiftData schema、不改 CloudKit schema、不需闸门（KVS 按键 LWW，两个 Int）。改动面：`Resources/UserSettings.swift` 读写处 + `didChangeExternallyNotification` 监听。

### C.3 遗留
kill time 是"日期的墙上时间"，`killDate(for:)`（`StateMachine.swift:265-271`）用跟随设备时区的 `Calendar(identifier: .iso8601)` 合成 instant。跨时区设备对同一 `day.date` 算出不同 instant → 一台可能提前/延后判过期。**属 Phase D，本 Phase 不解决。**

---

## 6. Phase D：身份锚点（v2 拆成 D1 / D2）

审查 #4 成立：v1 把它整体延后，等于承认"跨时区多端同步未解决"却仍称方案完整。v2 拆开。

### D1（本轮做，便宜）：设备内锚点稳定

问题不止跨设备。**同一台设备**改时区或跨时区旅行后，历史 `dayId` 也会与新算出的不匹配 → 自己的数据裂成两套。

做法：首次启动把 `TimeZone.current.identifier` 存进 `UserDefaults`（设备本地，**不同步**），`Date.dayId` / `Date.weekId`（`Date+Weekyii.swift:4-16`）改用该锚点时区（`DateFormatter.timeZone` / `Calendar.timeZone`）。

- 零 schema 变更、零 KVS 依赖
- 解决"设备自己时区漂移"这一更常见的情况
- **不解决**跨设备时区不同（每台设备各选自己的锚点）

配套护栏：`validateContainerConsistency`（`WeekyiiPersistence.swift:198-205`）失败时不再 `.failed` 阻断启动（`:110-113`），改为记录 + 走 `BackupRecoveryService`（`:302-531`）提示恢复。**这只防锁死，不防重复数据** —— 明确记为局限。

### D2（独立立项，贵）：跨设备共享锚点

锚点必须跨设备一致才解决 S3。三个约束使它昂贵：
1. 锚点要同步 → 放 SwiftData 就是改 schema = **开 V9**（违反 [[weekyii-schema-migration-constraints]]）；放 KVS 则**到达时机不保证** → 锚点未知期间算出的 `dayId` 仍是本地时区的 → 又造重复
2. 存量数据是用设备本地时区写的 `dayId`。锚点若与之不同，需要一次性**重键迁移**（改 `dayId` / `weekId` 主键），而重键在 CloudKit 下等价于"删旧记录 + 建新记录" → 全局不可逆
3. 锚点未确定前不能造日 → 与 §4.7 的降级叠加，首启空窗变长

**建议：D2 单独立项，在 A/B/C 落地并有真机双端验证数据之后再评估。** 在此之前，方案文档不得声称"多端同步已完整解决"；准确表述是"同时区多设备收敛，跨时区为已知未解限制"。

---

## 7. Phase E：同步能力开关 + Apple ID 切换（v2 重写，升为高优先级）

审查 #5 成立，且比审查意见更硬：**运行中无法"停止 mirroring"。**

```swift
// App/WeekyiiPersistence.swift:127-136
let cloudKitDatabase = resolvedMode.cloudKitContainerIdentifier.map {
    ModelConfiguration.CloudKitDatabase.private($0)
} ?? .none
config = ModelConfiguration("Weekyii", schema: currentSchema, url: url,
                            allowsSave: true, cloudKitDatabase: cloudKitDatabase)
```
`cloudKitDatabase` 在 `ModelConfiguration` 构造时固定，`ModelContainer`（`:139-143`）建成后不可变更。所以"停止 mirroring"只有两条路：**重建容器**，或**从一开始就不启用**。

### 7.1 同步偏好（S9）

- 新增设备本地偏好 `cloudSyncEnabled`（`UserDefaults`，**必须设备本地** —— 一个被同步的"关闭同步"标志自相矛盾）
- 读取点在 **#19 甲的启动阶段 1**（`WeekyiiApp.init()`，`:481-519`，容器创建之前），作为 `resolveStoreMode` 的第四个入参：`cloudSyncEnabled == false` → `.localOnly`（§4.2.2 的第二条 guard，优先于账号判定）。`cloudKitContainerIdentifier` 自动为 `.none`，store 路径自动为 `Weekyii.local.store`（§7.1.1）
- **v3.1 更正**：`cloudSyncEnabled == false` 落 `.localOnly` 的前提是 §7.1.1 的路径分离已实施（阶段 B0）。否则它会以 `.none` 打开 `Weekyii.store`，即在云库文件上建可写数据 —— 与 #16 裁决直接冲突。**这条依赖关系使 §7.1 的开关不能早于 B0 上线**
- **切换后下次启动生效**，不做运行时热切换。理由：运行时换容器要重建 `.modelContainer(modelContainer)`（`:529`）注入、重绑全树 `@Query` 与 `@Environment(\.modelContext)`、重建持有 `modelContainer` 的 `AppHealthCoordinator`（`:360`）—— 风险与收益完全不成比例
- UI：`SettingsView.swift:632-646` 的只读状态行下方加开关 + "重启后生效"说明

#### 7.1.1 #16 已裁决：独立 store 文件（架构决定，不是待实测项）

裁决原文：不要把同一个 SQLite store 在 `.private(id)` 和 `.none` 之间反复打开，CloudKit 元数据可能残留，风险不值得承担。**实测只用于验证迁移流程，不再用于决定是否分库。**

```
云同步库：Application Support/Weekyii/Weekyii.store        ← StoreMode.production（可写 + .private(id)）
                                                            StoreMode.cloudDetached（只读 + .none，v3.1 新增）
本地独立库：Application Support/Weekyii/Weekyii.local.store ← StoreMode.localOnly
内存库：（无文件）                                          ← StoreMode.inMemory
```

**`cloudDetached` 为什么仍解析 `Weekyii.store` 而不是另开第三个持久数据文件**：它的语义是"对端可能存在，只是这台设备当下够不着"（账号解析超时 / 身份未确认 / `.temporarilyUnavailable`）。它要展示的是云端那份数据，因此源路径仍是 `Weekyii.store`；但打开前复制到进程级临时目录，以 `allowsSave: false` + `.none` 读取副本。临时副本不是第三份用户数据，也不参与后续同步。

**实测结论（已落地）**：直接以 `allowsSave: false` 打开源库时，主库与 WAL 不变，但 SQLite 的 `-shm` 侧车会变化。因此 `cloudDetached` 不直接打开源库，而是先复制 `Weekyii.store` 及存在的 `-wal/-shm` 到当前进程的临时目录，再以只读配置打开副本；源库文件及其侧车保持零字节变化。副本在当前进程内只用于展示/导出，不参与 CloudKit，也不改变 `settlement` 的 `unsettled` 语义。

这是 #16 裁决的一个受控例外，须在代码注释中写明理由与实测结论。

**改动 1：`persistentStoreURL()` 必须按模式解析。**

```swift
// App/WeekyiiPersistence.swift:148-153 现状：单一固定路径
static func persistentStoreURL() -> URL { ... "Weekyii.store" }
```
改为 `persistentStoreURL(for storeMode: StoreMode) -> URL`，并保留无参版本**仅在能确定当前模式时使用** —— 更好的做法是删掉无参版本，强制所有调用点显式传模式，让漏改在编译期暴露。

**改动 2：9 处外部调用点全部要改（v3 新发现 4）。** 这些调用点当前都硬解析到云库路径：

| 文件 | 行号 | 用途 | 双库后不改的后果 |
|---|---|---|---|
| `App/WeekyiiPersistence.swift` | 99 | `bootstrapPersistentContainer` 的 `storeURL ?? persistentStoreURL()` | 打开错误的库 |
| 同上 | 126 | `makeModelContainer` 的 `storeURL ?? persistentStoreURL()` | 打开错误的库 |
| 同上 | 184 | `failureDiagnostics()` | 诊断信息指向错误的库 |
| `App/WeekyiiApp.swift` | 607-608 | `canRestore:` 快照列表 | 显示另一个库的快照 |
| 同上 | 623 | 错误页 storeURL | 同上 |
| `Resources/SettingsView.swift` | 115-116 | 快照列表 | 同上 |
| 同上 | 777 | `createSnapshot(storeURL:)` | **给错误的库打快照** |
| 同上 | 923-924 | 快照列表 | 显示错误的库 |
| 同上 | 2672 | 快照列表 | 同上 |
| 同上 | **2679** | `restoreSnapshot(named:to:)` | **把快照恢复到错误的文件 = 数据丢失路径** |

`SettingsView.swift:2679` 是其中唯一一条会静默破坏数据的路径，必须在同一轮里改掉，不能留到后续。

**改动 3：切换流程（两个方向都必须显式定义数据来源，禁止隐式合并）。**

关闭同步（云 → 本地）：
```
1. 快照当前云库           BackupRecoveryService.createSnapshot(storeURL: 云库, reason: "disable-sync")
                          （:155-166 的 backupPersistentStoreIfExists 已参数化 storeURL，可直接复用）
2. 从云库导出归档         WeekyiiDataArchiveService.export(modelContext:settings:appState:)  （DataArchiveService.swift:144-158）
3. 建本地库容器           makeModelContainer(storeURL: 本地库, storeMode: .localOnly)
4. 导入并替换             importReplacing(_:modelContext:settings:appState:storeURL:)        （:174-207）
                          :185 会再打一次 reason: "import" 的快照；:188 deleteAllData → :189 insert → :190 save；:192 失败即 rollback
5. 云库文件保留不动       （用户日后重新开启同步要用）
6. 置 cloudSyncEnabled = false，提示重启
```

开启同步（本地 → 云）：**数据来源必须唯一**。
```
1. 快照本地库
2. 从本地库导出归档
3. 建云库容器（.production / .private(id)）
4. 若云库非空 → 不允许静默 importReplacing（那会用本机数据覆盖云端，再经镜像抹掉其它设备的数据）
   → 必须走"二选一"对话框：
      a. 以本机数据为准（importReplacing 到云库，云端旧数据被替换；先强制快照）
      b. 以云端为准（丢弃本地库内容，挂上 CloudKit 等首次导入；本地库文件改名留存）
5. 置 cloudSyncEnabled = true，提示重启
```

**明确禁止**：任何形式的"两个 store 隐式合并"。合并需要跨库记录级 diff + 冲突策略，量级等同一个新功能，且与 §1.5 的互删风险同源。

**改动 4：归档格式版本。** `currentFormatVersion = 1`、`currentSchemaVersion = 8`（`DataArchiveService.swift:46-47`）。切换流程复用现有导出/导入，**不需要提升格式版本**（payload 结构未变）。

**改动 5：`WeekyiiSchemaV8` 与迁移计划不变。** 两个库用同一 schema、同一 `WeekyiiMigrationPlan`（`WeekyiiPersistence.swift:139-143`），只是文件路径与 `cloudKitDatabase` 不同。**不需开 V9，不需重跑 `-initializeCloudKitSchema`。**

### 7.2 Apple ID 切换（S8）

**关键约束：检测不能晚于容器创建。** 一旦以 `.private(id)` 建好容器并处于账户 B 的会话下，A 的本地记录就会自动向 B 的私有库导出。在 `applicationDidBecomeActive` 里检测**已经太晚**。

因此唯一可靠的结构是**两阶段启动**。**#17 已裁决**：异步可以，但硬条件是 `fetchUserRecordID()` 未返回前**不得创建 `.production` 的 CloudKit-backed `ModelContainer`**。

**#19 已裁决：选甲，并补充"进程级终止边界"。** 裁决原文：**"阶段 1 不创建任何 `ModelContainer`，先解析账号；账号确认后一次性创建正确模式的容器。"** 在此之上，四条边界**全部为强制项**，理由是：

> 否则仍会出现同一进程内 `.none → .private(id)`，与 #16 的双库隔离原则冲突。

```
阶段 1（无容器）：不创建任何 ModelContainer
                → 启动页显示占位（复用既有启动图，见项目记忆 launch-experience）
                → 读上次成功同步的 userRecordID（本机 UserDefaults）
                → 异步 CKContainer.fetchUserRecordID()

阶段 2（一次性建容器）：
   ├─ 账号 available 且身份一致 → 以 .private(id) 建 .production 容器 → 正常启动
   ├─ 账号 noAccount/restricted → 以 .none 建 .localOnly 容器（§4.2.2 的 resolveStoreMode）
   ├─ 身份不一致               → 以 .none + allowsSave:false 建只读容器，闸门全关，弹三选
   └─ maxWait 内取不到账号      → 以 .none + allowsSave:false 建只读容器（只读降级）
```

**#19 的四条进程级终止边界**（逐条对应实现约束）：

| # | 边界（裁决原文） | 实现约束 |
|---|---|---|
| 1 | `maxWait` 后如果仍无法确认账号，只能进入只读降级 | 超时路径建 `storeMode == .cloudDetached` 的容器（`.none + allowsSave:false`，从 `Weekyii.store` 复制进程级临时副本，§4.2.2）；`settlement` 恒 `unsettled` → `syncedWritesAllowed == false`。**不得**降级为 `.localOnly`（会新建第二份数据）或 `.production`（会用未确认身份开始导出） |
| 2 | 一旦只读容器打开，本进程内不得再切换到 `.private(id)` | 容器创建点必须**单一且只执行一次**：用一次性 `let container = ...`（或 `@State` + 幂等守卫），禁止任何"账号到了就重建容器并重新绑定 `.modelContainer`"的代码路径。`WeekyiiApp.swift:529` 的 `.modelContainer(...)` 修饰符消费的是同一个实例 |
| 3 | 账号后来恢复时，提示用户重启 | 在只读降级态收到 `CKAccountDidChange` / 设置页手动刷新命中 `available` 时，**只弹提示、不重建容器**（文案入 `Localizable.xcstrings`，键名建议 `settings.cloud.restart_required`） |
| 4 | 重启后重新走阶段 1 | 阶段 1 是无状态的（不依赖上次降级结果），重启即重新解析 → 账号已 available → 直接建 `.private(id)` 容器，全程仍只打开一次 |

**边界 2 是本条裁决的技术核心**：它把"容器模式在进程内单调"变成一条硬不变量，与 #16 的"同一 store 文件不在 `.none` ↔ `.private(id)` 间反复打开"同源。实现时任何试图绕过它的"优化"（例如在只读态下预热 CloudKit 容器）都直接违反裁决。

**只读降级态的用户可见行为**：能看数据、能滚动，但所有写操作被 UI 禁用或提示"正在等待同步确认"；不静默吞掉用户的点击（否则会误以为已保存）。具体禁用面见 §4.7。

裁决理由（原文）：否则"异步"仍然可能在检查完成前把旧数据导出到新账号。

#### 7.2.1 #16 与 #17 直接冲突（v3 新发现 2）—— **#19 已裁决**

- #16 说：**不要**把同一个 SQLite store 在 `.private(id)` 和 `.none` 之间反复打开
- #17 阶段 1 说：以 `.none + allowsSave:false` 打开 store，让用户在等待期间看到自己的数据

而用户的数据就在 `Weekyii.store`（云库）里。阶段 1 要显示数据，就必须打开**同一个文件**；阶段 2 再以 `.private(id)` 打开它 —— 这正是 #16 禁止的序列。

三条出路，**#19 裁决为甲，乙与丙已否决**：

| 选项 | 做法 | 代价 | 是否违反 #16 | v3.1 状态 |
|---|---|---|---|---|
| **甲** | 阶段 1 **不建任何容器**，启动页显示占位（复用既有启动图，见项目记忆 launch-experience），账号解析完成后一次性以正确模式建容器 | 冷启动多一段无数据的等待；账号不可达时**永远停在占位页** → 由 `maxWait` 后降级为只读容器兜底（边界 1） | **不违反**（全程只打开一次） | ✅ **选定**，附四条进程级边界 |
| 乙 | 阶段 1 以 `.none + allowsSave:false` 打开云库，阶段 2 销毁后以 `.private(id)` 重开 | 正是 #16 禁止的序列 | **违反** | ❌ 已否决 |
| 丙 | 阶段 1 只读打开一个**旁路快照副本**（把云库文件复制一份到临时目录再只读打开） | 冷启动多一次全库文件复制（大库代价高）；副本与正本可能在阶段 2 之间失同步 | 不违反，但引入新文件与新失败模式 | ❌ 已否决 |

**`maxWait` 的角色（与 §4.5 一致）**：它**不是数据闸门**，`syncedWritesAllowed` 完全不看它。它只界定占位页/只读降级策略的产品时限；超时后**不会**因为"等不下去了"而放开任何同步字段写入。

#### 7.2.2 只读容器的两个硬前置（v3.1：仍适用于 #19 的边界 1 超时路径）

1. **播种必须先移出 `makeModelContainer`**（§4.11 第一步）。`TaskTypeDefinition.swift:118` 是 `try context.save()`；`allowsSave: false` 的容器上 save 会抛错，而 `WeekyiiPersistence.swift:144` 在容器构造内部无条件调用它。**不移出去，只读容器建不起来。**
2. **`bootstrapPersistentContainer:107` 的 repair 必须删除**（§4.4）。repair 内部 `:433-435` 会 save，同样在只读容器上抛错。

**推断（需实测）**：`WeekyiiPersistence.swift:139-143` 带 `migrationPlan: WeekyiiMigrationPlan.self`。若磁盘上的 store 版本低于 V8（例如用户从旧版本升级），迁移需要写权限，`allowsSave: false` 的容器可能直接构造失败。**#19 定案后这条风险大幅缩小但不能忽略**：甲方案让容器只在阶段 2 建一次，正常路径建的是可写容器，迁移能正常跑；**唯一暴露面是边界 1 的超时降级**（建只读容器时若 store 版本低于 V8 会失败）。处置：超时降级路径若容器构造失败，退回"占位页 + 设置页手动重试"，**不得**为了建起只读容器而放弃 `allowsSave: false`（那会让一个身份未确认的进程获得写权限）。

账户不一致时的三选（**全部先自动打快照**，复用 `BackupRecoveryService`，`WeekyiiPersistence.swift:302-531`）：
1. **保留本地数据并与新账户合并**（= 现状行为，会把 A 的数据推进 B 的库）
2. **清空本地，从新账户重新拉取**（挂上 CloudKit 后走首次导入）
3. **保持本地、本设备关闭同步**（= 把 `cloudSyncEnabled` 置 false，走 §7.1，落到 `Weekyii.local.store`）

在用户选择前：闸门保持关闭，`syncedWritesAllowed == false`（Tier-2a 与 Tier-2b 都不执行）。**选项 1 与 2 都需要重建为可写容器 → 受边界 2 约束，必须提示重启后执行**，不得在只读进程内直接切换。

#### 7.2.3 甲方案对启动代码的具体改造面（v3.1 新增，本次 Read 核实）

甲方案不是"加个开关"，它改变了容器创建的**时机与同步性**。三处现状必须改：

**① `LaunchState` 缺一个中间态。** `WeekyiiPersistence.swift:26-29` 现在只有两态：
```swift
enum LaunchState {
    case ready(ModelContainer)
    case failed(String)
}
```
阶段 1 没有容器，但也不是失败 → 必须新增 `case resolving`。`WeekyiiApp.swift:523` 的 `switch launchState` 随之增加一个分支，渲染占位页（复用既有启动图，见项目记忆 launch-experience；不新建视觉资产）。

**② `_launchState` 现在是 `init()` 里同步赋值的 `@State`。** `WeekyiiApp.swift:514-518`：
```swift
} else {
    _launchState = State(
        initialValue: WeekyiiPersistence.bootstrapPersistentContainer()
    )
}
```
甲方案下这一行必须先赋 `.resolving`，再由阶段 1 的异步账号解析在完成后赋 `.ready(...)`。**这与启动性能痛点直接相关**（见项目记忆 launch-perf-audit：橙屏间隔 = 主线程同步全量 reconcile）—— 异步化本身是改善，但账号解析进入关键路径会让"有账号设备"的冷启动多一次网络往返。缓解：阶段 1 先用本机缓存的 `lastSyncedUserRecordID` 与 `CKContainer.accountStatus`（同步、无网络）做一次快速判定，只有快速判定不足以确认时才等 `fetchUserRecordID()`。这是实现细节，不改变裁决。

**③ 仓内已有两条"进程内重建容器"的路径，必须一并收编。** `WeekyiiApp.swift:618-620` 与 `:622-633`：
```swift
private func retryPersistentStore() {
    launchState = WeekyiiPersistence.bootstrapPersistentContainer()
}
private func restoreLatestPersistentStoreSnapshot() {
    ...
    launchState = WeekyiiPersistence.bootstrapPersistentContainer(storeURL: storeURL)
}
```
二者都从 `PersistenceFailureView`（`:604-612`）触发，即**只在 `.failed` 态可达** —— 此时从未成功打开过容器，所以重建**不违反边界 2**。但它们现在调用的是无参 `bootstrapPersistentContainer()`，内部走 `launchStoreMode(environment:)`（`WeekyiiPersistence.swift:105`）→ 生产环境恒 `.production`。

**这是一个真实的洞**：若阶段 1 判定为 `.localOnly` 或 `.cloudDetached`，而容器构造失败进入 `.failed`，用户点"重试"会**以 `.production` 重建**，绕过 #18 与 #19 的全部判定。修法：阶段 1 解析出的 `StoreMode` 必须存为 `WeekyiiApp` 的实例字段，`:619` 与 `:629` 两处显式传入 `storeMode:`；`bootstrapPersistentContainer` 的 `storeMode` 参数（`:96`）已存在，无需改签名。

**边界 2 的自动化守卫（建议，非裁决要求）**：在 `WeekyiiApp` 上加一个 `didOpenContainer: Bool` 断言字段，任何容器创建路径先检查它 —— 已为 true 且新模式为 `.production` 时直接 `assertionFailure`。理由：边界 2 是"不写某段代码"的约束，靠人肉 review 守不住，而这类不变量一旦破防是静默的数据导出。

#### 7.3 E-1.5：账号身份护栏（v3.1：在塌缩后的闸门下重新论证）

**v3 给 E-1.5 的理由已作废。** v3 写的是"§4.2.1 的分级把重量压到了 E-2" —— v3.1 里那个分级（`derivedWritesAllowed` / `irreversibleOpsAllowed` 两档）**已经不存在**，两档塌缩成单一的 `syncedWritesAllowed`（§4.2.1）。所以 E-1.5 的理由必须重新推导，不能沿用。

**v3.1 的理由**：`syncedWritesAllowed` 唯一的放行条件是 `settlement ∈ {noRemotePeer, settled}`，而 `settled` 只看**事件静止**，不看**身份是谁**。于是存在这条路径：

```
设备上次以账号 A 同步 → settled → 全部写入放行
用户登出 A、登入 B     → CKAccountDidChange（CloudSyncMonitor.swift:180-185）
                      → 事件静止 → 仍然 settled → 仍然全部放行
                      → 但此刻本地数据是 A 的，写入会经 .private(B) 容器导出到 B 的私有库
```

**闸门感知到了账号变化，却无法区分"重新登录 A"与"登录 B"**。E-1.5 就是补这个缺口：

- 每次成功 `settled` 后，把 `CKContainer.fetchUserRecordID()` 的结果存进本机 `UserDefaults`（`lastSyncedUserRecordID`，**设备本地，不同步**）
- `syncedWritesAllowed` 增加一个前置：`currentUserRecordID == lastSyncedUserRecordID`，或 `lastSyncedUserRecordID == nil`（从未同步过）
- 身份不一致 → `settlement` 直接返回 `unsettled`（不是新增第五态；身份未确认在语义上就是"输入不完整"）→ 全部同步字段写入关闭，直到用户在 §7.2 的三选里做出决定

**它修什么、不修什么（必须说清楚）**：
- ✅ 阻止跨账号的删除/合并/终态写入（审查点 1 担心的"破坏后带入新账号"）
- ❌ **不阻止 A 的记录导出到 B 的私有库**。因为容器已经以 `.private(id)` 建好了（`WeekyiiPersistence.swift:127-136`），导出由框架自动进行，App 层拦不住。那需要 E-2 的容器延后创建 —— 也就是 **#19 甲方案本身**
- 因此 E-1.5 是**减害**，不是解决 S8。S8 的解决只能靠 E-2

**#19 定案后 E-1.5 与 E-2 的关系变化（v3.1 新增判断）**：甲方案把账号解析提到了容器创建之前，**这已经覆盖了 E-1.5 想防的主要场景**（进程启动时身份不一致 → 根本不建 `.private(id)` 容器）。E-1.5 剩余的独立价值只有一处：**进程存活期间发生的账号切换**（用户不重启 App，直接去系统设置换 Apple ID，再切回来）。这是真实场景但不是高频场景。

→ **#9 最终裁决**：E-1.5 保留为 Phase B 的最终验收前置，可作为 B.5 独立提交（改动面：`AppState` 加一个字段 + `settlement` 加一个前置 + 一处 `fetchUserRecordID` 缓存），但 B 不得在其缺席时宣称覆盖运行期 Apple ID 切换。

---

## 8. Phase F：习惯水位线（v2 大幅缩小）

### 8.1 水位线改推导（保留）
```swift
// Services/HabitTaskMaterializer.swift:186-190 现状：存储的 String，LWW 可回退
guard habit.generatedThroughDayId < todayKey else { return }
```
改为由 `records`（`Models/HabitModel.swift:115-118`）推导 `records.map(\.dayId).max() ?? ""`。

**精确界定它能抵抗什么**（v1 过度声称，审查 #6 正确）：
- ✅ 抗 LWW 回退：`max()` 单调，合并后不会变小
- ❌ **不抗部分同步**：最新 record 未到达时 `max` 被低估 → 仍会重新物化

所以它**必须与 Phase B 的闸门配合**：`HabitTaskMaterializer.sync`（`WeekyiiApp.swift:406-407`）已在 §4.3 纳入 Tier-2。闸门抵抗部分同步，推导抵抗 LWW 回退，两者缺一不可。零 schema 变更（旧字段可保留不用）。

### 8.2 去重 pass（v2 撤销）

v1 提议"按 `(dayId, habitId)` 去重，保留 `createdAt` 最早的一条"。审查 #6 指出这会丢掉后来的 completed 状态 —— **正确，这是 v1 的 bug**。

但进一步核实发现：**读路径早已有正确的合并语义，去重 pass 根本不需要。**
```swift
// Services/HabitStatistics.swift:111-123
/// 同日多条记录（CloudKit 多设备合并）取"最有利"状态：completed > missed > pending。
static func recordStatusMap(for habit: HabitModel) -> [String: HabitDayRecordStatus] {
    ...
    map[record.dayId] = Self.rank(status) > Self.rank(existing) ? status : existing
}
// :144-150  rank: completed = 2, missed = 1, pending = 0
```
注释直接写明是为 CloudKit 多设备合并设计的。`currentStreak`（`:125-132`）、`longestStreak`（`:134-140`）都经这个 map。

**结论：同日多条 `HabitDayRecord` 是设计上被容忍的，统计口径已正确。撤销去重 pass**，理由：
- 它不修复任何现存 bug
- 它是一次删除操作，会把 §1.5 那类"判据依赖本地可见性 → 互删"的风险重新引入
- 保留重复记录的存储成本远低于误删完成状态的成本

若将来确实要清理存储，正确判据是复用 `HabitStatistics.rank`（`:144-150`）保留最高秩、同秩保留最早 `createdAt`，且必须在闸门内执行。**本轮不做。**

---

## 9. 实施顺序

**v3.1 结构性变化：Phase B 多了一个硬前置 B0。** #18 用"切库"替代"放行"之后，闸门的第一步不再是判定，而是**决定打开哪个库**；而这个决定需要账号状态（#17/#19 的阶段 1）与两个库的物理分离（#16 的路径部分）。这三件事原先分散在 B、E-1、E-2 里，现在必须合成一轮做完，否则 B 无法 fail-closed。

```
Phase A（硬/软终态 + 停删 + 删除 :689-691 + §3.3 降级 + "正在同步确认"文案）
   │   含强制交付项：§3.6 测试断言审计
   │
Phase B0（容器模式解析 —— B 的硬前置，v3.1 新增）
   │   ① StoreMode 加 cloudDetached / hasNoRemotePeer / allowsSave（§4.2.2）
   │      ← 已完成源库零写入实测：直接源库打开会变更 -shm，现改为进程级临时副本；
   │        §13.2.0 校验副本读取与源文件校验和均通过
   │   ② persistentStoreURL(for:) 分叉出 Weekyii.local.store + 9 处调用点显式传模式
   │      ← #16 的"路径分离"部分从 E-1 提前。**不提前则 #18 的"切库"是假的**：
   │        .localOnly 仍会打开 Weekyii.store，等于在云库文件上以 .none 可写建数据，
   │        日后登录即隐式合并 —— 正是 #16 禁止的
   │   ③ launchStoreMode → resolveStoreMode(environment:accountStatus:identityConfirmed:cloudSyncEnabled:)
   │   ④ LaunchState 加 .resolving + 阶段 1 异步账号解析（WeekyiiApp.swift:514-518、:523）
   │   ⑤ :619 / :629 两条重试路径显式传 storeMode（§7.2.3 ③：否则重试会绕过全部判定）
   │   ⑥ §4.4 删引导期 repair + §4.11 播种移出 makeModelContainer
   │      ← §7.2.2：cloudDetached 是 allowsSave:false，这两项不做则只读容器建不起来
   │   ⑦ cloudSyncEnabled 键（默认 true；设置页开关、显式快照/导入迁移已落地）
   │
Phase B（fail-closed 闸门：四态 + 单一谓词 syncedWritesAllowed + Tier-2a/2b 分类
   │     + §4.6 拆 markProcessed + §4.10 并发事件追踪 + §4.12 事件基线）
   │   ← 依赖 A：A 让 Tier-2 的语义变干净（§3.1 的判据不读本地状态）
   │   ← 依赖 B0：闸门读 storeMode，而 storeMode 由 B0 决定
   │   ← §4.12 按方案 1 落地：同步观察当前进程事件 + 容器加载基线；不引入持久化事件历史查询，无证据时保持 `unsettled`
   │
Phase E-1'（同步开关 UI + 双向迁移流程）
   │   ← 路径分离已在 B0 做完，本轮只剩开关 UI、快照、export/importReplacing 双向流程
   │   ← 仍串行在 B 之后：与 B 同改 App/WeekyiiPersistence.swift，并行会撞车
   │
Phase E-1.5（账号身份护栏）                ← #9 最终裁决：作为 Phase B 最终验收前置；可拆为 B.5，但 B 不得在其缺席时宣称完成
   │
Phase C（kill time 幂等化 → KVS 镜像）
   │
Phase F（水位线推导化）                    ← 依赖 B 的闸门
   │
Phase A.7（GC 回收窗口）                   ← 依赖 B；不依赖 D（§3.7 已论证）
   │   #20 锁定：**独立于 Phase A/B 验收**，不同轮提交、不同轮验收
   │   交付物含 §3.7 的五条强制表述，缺一不算完成
   │
Phase D1（设备内时区锚点 + 校验护栏）
   │
Phase E-2'（身份不一致的三选 UI + 快照 + 重启提示）
   │   ← 阶段 1 的解析已在 B0 做完，本轮只剩"不一致时给用户什么选择"
   │   ← S8 的完整解；B0 已阻止启动期的跨账号导出，本轮补运行期与用户决策
   │
Phase D2（跨设备时区锚点）                 ← 独立立项，可能需 V9
```

**每个 Phase 单独一轮、单独可回滚、单独验收。** A 与 B 都改 reconcile 写入行为，混在一起无法定位回归。B0 与 B 可以同轮**提交**（B0 单独不可验收：没有闸门，`cloudDetached` 只是一个建得起来但没人读的枚举），但**验收清单必须分开写**（§13.2 与 §13.2.0），否则回归时无法区分是模式判定错了还是闸门判定错了。

---

## 10. 全局影响范围清单

### 10.1 会被修改的文件（v3.2：已落地文件清单，Phase 标签按 §9 更新）

> 命名说明：`AppHealthCoordinator` 类型声明在 `App/WeekyiiApp.swift:359`，仓内**没有** `AppHealthCoordinator.swift` 这个文件。本文中所有 `WeekyiiApp.swift:359-464` 区间的引用都指该协调器。

| 文件 | Phase | 行号锚点 |
|---|---|---|
| `Models/DayModel.swift` | A | 43-57, 59-61, 新增 `isTerminal` |
| `Services/StateMachine.swift` | A, B, C | 4-14, 92-124, 249-263, 273-290, **689-691（删）**, 633-705。**47-49 与 396-437 不改**（§4.2.4） |
| `Features/Today/TodayViewModel.swift` | A | 246-253, 465-481 |
| `Services/TaskPostponeService.swift` | A | 423-434, 436-447 |
| `Resources/Localizable.xcstrings` | A, B0, E-1' | 新增 `today.done.awaiting_sync`（§3.3）、`settings.cloud.restart_required`（§7.2 边界 3）、E-1 的开关与说明文案 |
| `Resources/SettingsView.swift` | A, B, C, E-1' | 115-116, 632-646（显示 `settlement` 具体值）, 777, 923-924, 1659-1667, 1684-1693, 2672, **2679** |
| `Services/CloudSyncMonitor.swift` | B | 113-120, 137-152, 141-143, 168-188, **213-238（重写）**, 新增 `markContainerLoaded(at:)` / `CloudSyncEventSnapshot` / `CloudSyncSettlement` |
| `Models/TaskTypeDefinition.swift` | B0 | **94-98（删 `:95`）**, 100-120（拆两档） |
| `Features/Pending/PendingViewModel.swift` | B0 | 206, 238（`load()` 语义变化后复核） |
| `Shared/Components/TaskEditorSheet.swift` | B0 | 265, 281（同上） |
| `App/WeekyiiApp.swift` | B0, B, E-1', E-2' | 345-350, 359-391, 393-418, 406-407, 481-519（**514-518 同步赋值改异步**、**523 switch 加 `.resolving` 分支**）, **619 / 629（重试路径显式传 storeMode，§7.2.3 ③）**, 577-582, 607-608, 623, 635-644 |
| `App/WeekyiiPersistence.swift` | B0, B, D1, E-1' | **11-24（`StoreMode` 加 `cloudDetached` / `hasNoRemotePeer` / `allowsSave`）**, **26-29（`LaunchState` 加 `.resolving`）**, **89-91（→ `resolveStoreMode`）**, 93-114, **107（删）**, 116-146, **134（`allowsSave` 按模式）**, **144（移出）**, **148-153（按模式解析）**, 155-166, 183-196, 198-205 |
| `App/AppState.swift` | B, E-1.5 | 4-69（新增 `markRollover`；E-1.5 的 `lastSyncedUserRecordID`） |
| `Resources/UserSettings.swift` | C, E-1' | kill time 读写；新增 `cloudSyncEnabled`（键在 B0 建立，UI 在 E-1'） |
| `Shared/Extensions/Date+Weekyii.swift` | D1 | 4-16 |
| `Services/TimeProvider.swift` | D1 | 10-25 |
| `Services/HabitTaskMaterializer.swift` | F | 138, 186-190 |
| `Models/HabitModel.swift` | F | 77, 115-118, 153-156 |
| `Tests/StateMachineTests.swift` | A, B | 15, 160-164, 795-822, 1250-1260 |
| `Tests/ModelTests.swift` | A, B0, B | **71-82（`cloudDetached` 断言 + `resolveStoreMode` 映射表）**, 412-428, 481-496, 957, 1464-1531, **3892-3893（§3.6）**, 及审计命中的其它断言 |

**明确不改**：`Models/Enums/TaskZone.swift`、`Models/TaskItem.swift`、`WeekyiiSchemaV8`（`:1765-1783`）、`WeekyiiMigrationPlan.stages`（`:729-745`）、`Services/HabitStatistics.swift`（§8.2 已确认其合并语义正确）、**`StateMachine.swift:47-49` 的 `DataInvariantRepairing` 协议与 `:396-437` 的 `repair` 实现**（§4.2.4，v3 的加参已撤回）。

### 10.2 不改但必须回归验证（9 组）

| 文件 | 行号 | 验证点 |
|---|---|---|
| `Services/TaskPostponeService.swift` | 62-71, 206-215, 404-465 | 终态日不可达；非终态日排序/顺延不变 |
| `Services/NotificationService.swift` | 136 | `unfinishedCount` 对 open day 仍正确（仅对 open day 调用，见 `WeekyiiApp.swift:445-446`） |
| `Services/DataArchiveService.swift` | 46-47, 144-158, **174-207**, 212, 221, 233, 256-271 | 导出含保留任务；`validate` 通过；老归档可导入。**E-1' 的双库迁移直接复用 `export` + `importReplacing`，其"先快照（`:185`）→ deleteAllData（`:188`）→ insert（`:189`）→ save（`:190`）→ 失败 rollback（`:192`）"的语义成为迁移正确性的承重墙，必须回归** |
| `Services/BackupRecoveryService.swift` | — | E-1' 关闭同步时的 `createSnapshot(reason: "disable-sync")`；`hasValidSnapshot` / `listSnapshots` / `restoreSnapshot` 在双库路径下都指向当前活动库。**B0 拆路径后，`WeekyiiApp.swift:607-608` 与 `:623` 传的 `storeURL` 也必须按 `storeMode` 解析**，否则 `.localOnly` 设备会去列云库的快照（§7.2.3 ③） |
| `Services/WidgetSnapshotComposer.swift` | 89-92, 113, 135 | 终态今日快照为空；`:135` 完成数仍正确 |
| `Services/HabitStatistics.swift` | 111-123, 144-150 | 同日多条记录的 rank 合并未被 Phase F 破坏 |
| `Models/TaskTypeDefinition.swift` | 81-92, 122-128 | `activeDefinitions` 排序、`definition(for:)` 三级兜底在空 catalog 下不崩（§4.11 第三步删掉隐式播种后） |
| `Features/Past/*` | — | 过期日仍只显示数量、不显示详情（AGENTS.md 语义） |
| `Features/Week/*` | — | 终态日不出现"幽灵任务" |

### 10.3 明确不动的东西

- SwiftData schema：V8 保持冻结，**A/B0/B/C/E-1'/F/D1 全程不开 V9**（D2 可能开，属独立立项）
- 迁移计划：不新增 stage
- CloudKit schema：不需重跑 `-initializeCloudKitSchema`（`:33-39`、`:42-86`），不需重新部署 production
- 归档格式版本：不变
- `reconcile(now:force:)` 两参调用（`Tests/StateMachineTests.swift:319,730,731,1460,1474,1484,1498`）：靠第三参 `allowSyncedWrites` 的默认值 `true` 保持可编译（§4.3）。**但这个默认值只服务测试**：生产调用点必须显式传值，不吃默认（§4.3 第 3 条、§4.8 的 fail-closed 原则）。§13.2 有一条断言专门盯这件事

---

## 11. 事实 / 推断分离

**事实（本次会话 Read 到的当前代码）**
- `CloudSyncMonitor.swift:137` `accountState` 初值 `.checking`；`:187` 才发起异步刷新 → v1 的 `default: return true` 在此窗口放行
- `WeekyiiPersistence.swift:11-24` `StoreMode` 是"有无远端对端"的唯一真源；`:89-91` 测试走 `.localOnly`；`:124` `.inMemory` 直接 `.none`；`:127-136` `cloudKitDatabase` 构造时固定
- `WeekyiiPersistence.swift:103-108` 引导期 repair 跑在 monitor 存在之前
- `StateMachine.swift:689-691` 修复层会写 `closedAt`；`:364-366` 三个同步计数器每轮无条件重算
- `closedAt` 在 `Features/` 下零读取点；全部读取点是 `DataArchiveService.swift:220,339`、`StateMachine.swift:552`
- `closedAt` 写入点：`TodayViewModel.swift:251`、`TaskPostponeService.swift:432,445`、`StateMachine.swift:690`、`SettingsView.swift:1786`（样例数据）；清空点仅 `TodayViewModel.swift:138`，在 UI 测试专用函数 `:108-110` 内
- `Tests/ModelTests.swift:3891` 的 `closedAt` 断言由 `TaskPostponeService.swift:432` 满足，该测试不跑 reconcile → 删除 `:689-691` 不破坏它
- `Tests/ModelTests.swift:3890-3893` 在 `.completed` 日上用 getter 断言空 → 门控后退化为同义反复
- `HabitStatistics.swift:111-123` + `:144-150` 已实现"同日多条记录取最有利状态"，注释明写 CloudKit 多设备合并
- `HabitDayRecord.swift:4-16` 状态为 pending / completed / missed
- `AppState.swift:13` 为 `UserDefaults.standard`，不同步
- `Date+Weekyii.swift:4-16` `dayId` / `weekId` 未固定时区
- `SettingsView.swift:632-646` 只有只读状态行，无同步开关；entitlements `:15-16` KVS 已声明、全仓零代码命中
- `DataInvariantRepairing` 无测试替身（唯一实现 `DataInvariantRepairService`）
- 9 处 `TaskZone` 穷举 switch 位置（§3.5）
- `TaskPostponeService` 写路径被 `TodayViewModel.swift:157,175,191,200,208,236,303,361,372,534,541` 的 status guard 挡在终态日之外

**v3 新增事实（第 2 轮核查）**
- `CloudSyncMonitor.swift:138` `eventState` 是单标量；`:213-238` 的 `consume` 只读 `endDate`/`succeeded`/`error`/`type`，**从不读 `event.identifier` 或 `event.storeIdentifier`** → 无法表达并发事件
- `CloudSyncMonitor.swift:113-120` `isWorking` 只把 `.checking`/`.syncing` 当工作中 → 导入进行中设置页会显示"已同步"（既有缺陷，与闸门无关但会被闸门继承）
- `WeekyiiPersistence.swift:144` `TaskTypeCatalog.seedBuiltInTypesIfNeeded` 在 `makeModelContainer` 内部无条件调用，早于容器返回、早于 monitor 存在
- `Models/TaskTypeDefinition.swift:100-120` 播种写 `@Model`（`:5-6`）+ 回填 `taskTypeIdRaw` + `:117-119` 显式 `try context.save()`
- `Models/TaskTypeDefinition.swift:94-98` `load()` 在 `:95` 调用播种 —— 一个读 API 内含写与 save；调用点 `PendingViewModel.swift:206,238`、`TaskEditorSheet.swift:281`
- `Models/TaskTypeDefinition.swift:122-124` `definition(for:)` 三级兜底，`:90-92` `builtInFallback` 是纯内存对象
- `WeekyiiPersistence.swift:148-153` `persistentStoreURL()` 单一固定路径，**9 处外部调用点**（`:99`、`:126`、`:184`；`WeekyiiApp.swift:607-608`、`:623`；`SettingsView.swift:115-116`、`:777`、`:923-924`、`:2672`、`:2679`），其中 `SettingsView.swift:2679` 是 `restoreSnapshot(named:to:)`
- `WeekyiiPersistence.swift:155-166` `backupPersistentStoreIfExists(storeURL:)` 已参数化 storeURL，可直接用于 B0 拆路径后 / E-1' 切换前的快照
- `WeekyiiPersistence.swift:130-136` 与 `Tests/ModelTests.swift:1633` 证明 `ModelConfiguration(_:schema:url:allowsSave:cloudKitDatabase:)` 签名存在；全仓**零处** `allowsSave: false`
- `DataArchiveService.swift:144-158` `export(modelContext:settings:appState:)`；`:174-207` `importReplacing(_:modelContext:settings:appState:storeURL:)`，`:185` 快照、`:188` deleteAllData、`:189` insert、`:190` save、`:192` rollback；`:46-47` `currentFormatVersion = 1` / `currentSchemaVersion = 8`
- `Tests/ModelTests.swift:1468`、`:1481`、`:1505` 三个 catalog 测试都**显式**播种；`:428`、`:496` 两个迁移测试只断言自定义类型存在，不断言内置类型 → 移除 `:144` 不破坏任何现有测试
- `Tests/StateMachineTests.swift:795-822` 是 `mergeDuplicateBuiltInTaskTypes` 的现成测试，可充当 Tier-2b 门控的回归护栏
- `AppHealthCoordinator` 声明在 `App/WeekyiiApp.swift:359`，仓内无同名文件（v2 的文件名引用有误，v3 已全部更正）

**v3.1 新增事实（第 3 轮核查，全部为本次会话 Read/Grep 到的当前代码）**
- `WeekyiiPersistence.swift:11-24` `StoreMode` 只有 `production` / `localOnly` / `inMemory` 三态；`:16-23` 的 `cloudKitContainerIdentifier` 是**全仓唯一**对它的 `switch`（`:123` 是 `if resolvedMode == .inMemory`，`:121` 是 `??`）→ 增加第四态的编译破坏面只有 1 处
- `WeekyiiPersistence.swift:26-29` `LaunchState` 只有 `.ready(ModelContainer)` / `.failed(String)`，**没有"进行中"态**
- `WeekyiiPersistence.swift:134` `allowsSave: true` 硬编码；全仓显式写 `allowsSave:` 的另有 7 处，全在测试里（`Tests/ModelTests.swift:371,440,1546,1584,1610,1633,3676`），**全部为 `true`**，无一处 `false`
- `WeekyiiPersistence.swift:148-153` `persistentStoreURL()` 返回单一固定路径 `Application Support/Weekyii/Weekyii.store`，**与登录哪个账号无关、与 storeMode 无关**
- `WeekyiiApp.swift:514-518` `_launchState` 是在 `init()` 里**同步**赋值的 `@State`，`bootstrapPersistentContainer()` 直接作为 `initialValue`
- `WeekyiiApp.swift:523` `switch launchState`；`:604-612` 是 `.failed` 分支，渲染 `PersistenceFailureView`
- `WeekyiiApp.swift:618-620` `retryPersistentStore()` 与 `:622-633` `restoreLatestPersistentStoreSnapshot()` 是**仓内仅有的两条进程内重建容器路径**，二者都**无参**调用 `bootstrapPersistentContainer(...)` → 内部走 `:105` 的 `launchStoreMode(environment:)` → 生产环境恒 `.production`
- 这两条路径的唯一入口是 `PersistenceFailureView`（`:604-612` 的 `onRetry` / `onRestore`），即**只在 `.failed` 态可达** → 此时从未成功打开过容器
- `WeekyiiApp.swift:529` `.modelContainer(modelContainer)` 消费的是 `case .ready(let modelContainer)` 绑定出来的同一个实例
- `Tests/ModelTests.swift:71-82` 是 `StoreMode` 的现成断言点：`:71` `.production.cloudKitContainerIdentifier`、`:74-75` 两态为 nil、`:77-79` `launchStoreMode(environment: [:])`、`:81-82` 带 XCTest 环境变量 → `.localOnly`
- `Tests/ModelTests.swift:288,307,337,348` 四处显式传 `storeMode: .localOnly`（迁移测试），不依赖枚举穷举
- `CloudSyncMonitor.swift:172-179` 的事件观察用 `notificationCenter.notifications(named:)` 这个 AsyncSequence，包在 `Task { @MainActor in ... }` 内；`:219-222` `guard event.endDate != nil else { eventState = .syncing; return }` 证明**开始通知先于工作发生**
- `CloudSyncMonitor.swift:190-211` `refreshAccountStatus()` 已是 async，可直接作为 §4.5 的"设置页重试"出口

**推断（需验证）**
- **方案 1 的事件边界** —— 私有库为空的新账号是否产生 `.import` 事件不再决定是否放行；只依据当前进程已观察到的事件、setup 状态、在飞集合与 quiet period。无法证明收敛时保持 `unsettled`。日志只用于诊断
- `Task { @MainActor in for await ... }` 在 `WeekyiiApp.init()` 全程占用主 actor 期间不会开始观察，因此"把 `start()` 提前"不能修复 §4.12 的丢事件 —— 这是**对 Swift 并发语义的推断**，不是 Read 到的代码事实。**但 §4.12 的设计不依赖它成立**：基线值方案在两种情况下都正确，该推断只影响"是否存在更省事的替代修法"这一判断
- `CKContainer.accountStatus`（同步、无网络）能否在多数设备上替代 `fetchUserRecordID()` 完成 §7.2.3 ② 的快速判定 —— 影响有账号设备的冷启动耗时，不影响正确性
- 路径 A"枚举加 case 不需 SwiftData 迁移" —— 需 1 次 legacy-migration 测试
- 路径 B 对 CloudKit 记录类型零影响 —— 逻辑成立，最终以 CloudKit Dashboard schema 对比为准
- ~~同一 store 文件在 `.private(id)` 与 `.none` 之间来回打开是否安全~~ —— **#16 已裁决为独立 store、#19 已否决乙方案**，此项不再是任何决策的依据
- `NSPersistentCloudKitContainer.Event.identifier` 在同一事件的 start / end 两次通知间是否稳定 —— §4.10 的在飞集合以此为 key，不稳定则退到 `(storeIdentifier, type, startDate)`
- `cloudDetached`（`allowsSave: false`）的容器能否在需要迁移（store 版本 < V8）时成功构造 —— §7.2.2；**#19 定案后暴露面只剩边界 1 的超时降级路径**，处置已写明（退回占位页，不得放弃 `allowsSave: false`）
- **`cloudDetached` 的零写入边界已实测** —— 直接打开源库会改变 `-shm`，因此实现改为先复制源库及其侧车到当前进程临时目录，再以 `.none` + `allowsSave: false` 打开副本。主库、`-wal`、`-shm` 的源文件校验和保持不变；副本的侧车变化不影响用户数据。
- `fetchUserRecordID()` 的实际耗时与其对冷启动的影响 —— #17/#19 已裁决为异步 + 容器延后，但"占位页多久用户能忍"仍需实测
- 账号不可达期间 Core Data 是否仍会尝试导出（若会，E-1.5 的护栏只挡删除、挡不住导出）
- KVS 镜像 kill time 的到达延迟 —— KVS 推送不保证时效
- GC 边界日在跨时区下"提前不到 1 天删除"的论证（§3.7）—— 逻辑推导，未实测
- **GC 后离线旧设备重新上传的实际行为（§3.7）—— #20 已裁决为"接受为已知残余风险"，不再寻求实测解决，但也不得声称已解决**
- 闸门期 UI 降级观感（§4.7 单一窗口 + #19 甲的占位页）—— 未做视觉验证

---

## 12. 裁决清单（v3.2：#10/#15/#16/#17/#18/#19/#20 + 产品语义；方案 1 为实施取舍）

**已裁决（不再讨论）**

| # | 裁决结果 | 落点 |
|---|---|---|
| 5 | 消解：直接删除 `StateMachine.swift:689-691`（§3.1），不再是取值问题 | §3.1 |
| **10** | **接受**根因诊断。表述改为"设备本地时间与本地可见数据被当成同步事实写回 SwiftData"；同时删除"同步链路本身 100% 健康"的断言 | §0 |
| **15** | **接受延迟完成**。闸门期不写 `closedAt`、不标硬 completed，UI 显示"已完成最后一项，正在同步确认" | §3.3 |
| **16** | **裁定独立 store 文件**：`Weekyii.store` / `Weekyii.local.store`；关闭时快照；双向切换各自定义数据来源；禁止隐式合并 | §7.1.1 |
| **17** | **异步账号解析，但未确认前不建 CloudKit 容器**：`fetchUserRecordID()` 返回前不得创建 CloudKit-backed 容器 | §7.2 |
| **18** | **不接受 v3 的建议。** `.production + noAccount/restricted` **不放行 Tier-2a**，只放行 Tier-1；`maxWait` 最多只恢复安全的本地展示与通知逻辑，不恢复任何写 SwiftData 同步字段的逻辑。未登录设备必须可用时，**切换到独立的 `.localOnly` store**，而不是继续对云 store 执行 Tier-2a。附带改判：`processKillTime`、跨日过期属"终态语义写入"，归 **Tier-2b** | §4.2.1 / §4.2.2 / §4.2.3 / §4.5 |
| **19** | **选甲，并补充进程级终止边界**：阶段 1 不创建任何 `ModelContainer`，先解析账号；账号确认后一次性创建正确模式的容器。四条边界全部强制：①`maxWait` 后仍无法确认账号 → 只读降级；②只读容器一旦打开，本进程内不得再切换到 `.private(id)`；③账号后来恢复时提示用户重启；④重启后重新走阶段 1。理由：否则仍会出现同一进程内 `.none → .private(id)`，与 #16 的双库隔离原则冲突 | §7.2 / §7.2.1 / §7.2.3 |
| **20** | **接受"受控删除 + 已知残余风险"**，前提是当前 V8 冻结、不引入 tombstone。五条强制表述：GC 不是绝对安全；离线设备跨越回收窗口后重新上线，任务可能复活；这是已知数据一致性风险；GC 必须独立于 Phase A/B 验收；不得对外宣称"删除绝不复活"。未来若要求绝对防复活，再单独设计 tombstone / V9，不在本轮硬塞 | §3.7 |
| **产品语义** | **选 a：保留但隐藏**。不再向用户展示过期任务；不把未完成任务伪装成完成；不立即丢失同步迟到的数据；可以由后续稳定 GC 回收 | §3.2 |

**本轮新增裁决**

| # | 问题 | 选项与我的建议 |
|---|---|---|
| **方案 1** | §4.12 启动基线 | **保留 SwiftData，不引入第二套 Core Data 事件历史查询。** 在创建容器前同步注册 CloudKit 事件观察者；容器成功加载后以 `markContainerLoaded(at:)` 建立当前进程基线；进程内无足够事件证据时保持 `unsettled`。进程被杀后不把历史事件当作已验证事实；`maxWait` 不放开任何同步字段写入。 |

**其余已定项（v2 建议三轮未被推翻，视为默认采纳，若有异议请指出）**

| # | 问题 | 结论 |
|---|---|---|
| 1 | `quietPeriod` | **5s** |
| 2 | `maxWait`，及是否每次 sceneActive 重新武装 | **60s**；**只冷启动武装一次**（`WeekyiiApp.swift:548-556` 不重新武装）。**v3.2 修正**：它只界定占位页时长上界（§7.2.1），不再参与事件基线，也不改变任何 `settlement` 或同步写入权限 |
| 3 | `.manualResync` 是否绕过闸门 | **不绕过**（§4.8） |
| 4 | `hasSingleFocus`（`DayModel.swift:59-61`）是否门控 | **门控**，但先 grep 全部调用点确认无写路径依赖 |
| 6 | GC 的 N 值，及是否与 Phase A 同轮 | **单独一轮**；N = **8 周**（与 `WeekyiiPersistence.swift:251-254` 备份保留数 8 对齐）。硬下限 2 周（§3.7）。独立验收另由 #20 第 4 条锁定 |
| 7 | `SettingsView.swift:1684-1693` 的 coordinator 是否注入真实 monitor | **注入**（复用 `:18` 的 `@Environment`），否则设置页成为闸门外后门 |
| 8 | D1 的 `validateContainerConsistency` 护栏 | **做**。成本极低，避免用户被锁死 |
| 9 | E-1 / E-2 / E-1.5 的优先级 | **裁决：E-1.5 作为 Phase B 最终验收前置**。E-1（同步开关 + 双库 + 迁移）串行在 B 之后；E-2（#19 甲两阶段启动）是 B0/B 的直接依赖；E-1.5 至少作为 B.5 完成后才能对外宣称闸门覆盖运行期 Apple ID 切换。 |
| 11 | A 与 B 是否必须分两轮 | **必须分** |
| 12 | §4.6 拆 `AppStateStore` 连带改 2 个测试替身 | **接受**。不拆会导致闸门期 kill time 静默失效 |
| 13 | Phase F 是否与 A 同轮 | **不同轮** |
| 14 | 闸门期是否需要专门的"正在同步"占位 UI | **复用** `SettingsView.swift:632-646` 的状态组件，不新设计。另需一行降级窗口的持久说明（§4.7）。**v3.1 追加**：#19 甲方案让占位页成为冷启动的正常一站，其视觉必须复用既有启动图（见项目记忆 launch-experience），不新建资产 |

### 产品语义（已裁决：a）

终态日里"迟到的" focus/frozen/draft 任务如何归置 —— **裁决为 a. 保留但隐藏**，四条满足条件与实现的逐条对应见 §3.2。

| 选项 | 语义 | 代价 | 状态 |
|---|---|---|---|
| **a. 保留但隐藏** | 兼顾 AGENTS.md"过期即遗忘"的展示与可恢复性 | 数据只增不减，必须配 §3.7 的 GC | ✅ **选定** |
| b. 并入 complete zone | 当作已完成 | 违背事实，污染 `completedTasksCount`（`StateMachine.swift:364`） | ❌ 已否决 |
| c. 丢进解冻区 | 给用户"这些还活着"的入口 | 破坏终态封闭性，与 [[weekyii-time-philosophy]] 冲突 | ❌ 已否决 |
| d. 直接删除 | 最贴近 AGENTS.md | 回到 §1.2 的不可逆删除，Phase A 白做 | ❌ 已否决 |

---

## 13. 验收清单（不由我执行）

> **v3.1 重写。** v2 的本节围绕单一布尔 `destructiveOpsAllowed`；v3 围绕三级谓词 `localReconcileAllowed` / `derivedWritesAllowed` / `irreversibleOpsAllowed`。**两者都已作废，不得照抄。** v3.1 只有两个谓词：`localReconcileAllowed`（恒 true）与 `syncedWritesAllowed(now:)`（唯一数据闸门）。
>
> 新增 §13.2.0 覆盖 Phase B0（容器模式解析），它必须**独立于** §13.2 验收（§9）。§13.6 按 #20 第 4 条**独立于 Phase A/B 验收**。

### 13.1 Phase A（终态契约 + 停止删除）

**终态分界（§3.1）**
- 单元：`.completed` 日注入一条 focus 任务后跑 `repair` → 若 `closedAt != nil` 保持 `.completed`；若 `closedAt == nil` 回退 `.execute`（覆盖硬/软分界）
- 单元：`repair` 后 `closedAt` **不会**被凭空写出（覆盖删除 `StateMachine.swift:689-691`）
- 单元：`.expired` 日保留 draft 任务后跑 `repair` → 状态仍 `.expired`，`sortedDraftTasks` 为空而 `tasks.count > 0`
- 单元：`closedAt != nil` 且 `status == .expired` → 修复后 `.completed`（R1，完成态优先）
- 单元：`updateMetrics` 在过期日保留任务后两个计数器均不变

**保留而非删除（§3.2，产品语义 a 已裁决）**
- 单元：跑 `expire()` 后，`day.tasks` 中 `zone ∈ {draft, focus, frozen}` 的记录**仍在库内**（`context.fetch(FetchDescriptor<TaskItem>())` 计数不减），`day.status == .expired`，`completedTasks` 不受门控影响
- 单元：`TodayViewModel.swift:465-481` 与 `SettingsView.swift:1663-1665` 两条内联路径同样不产生 `modelContext.delete`
- 单元：迟到任务**不被改写 zone** —— 向终态日注入一条 `.frozen` 任务并跑 `repair`，其 `zone` 仍为 `.frozen`（不并入 complete、不丢回解冻区），且 `completedTasksCount` 不变（覆盖产品语义 a 的"不把未完成伪装成完成"）
- 断言方式：`modelContext.deletedModelObjects.count == 0`，或直接比对删除前后 fetch 计数

**#15 延迟完成（§3.3）**
- 单元：闸门关闭（`syncedWritesAllowed == false`）时对最后一个 focus 任务调 `doneFocus` →
  - 该任务进入 complete zone（**允许**）
  - `day.closedAt == nil`（**必须**）
  - `day.status != .completed`，停留在 `.execute`（**必须**）
  - 视图模型对外暴露"等待同步确认"标志为 true
- 单元：同一场景下 `TaskPostponeService.swift:423-434` 与 `:436-447` 两条路径的 `closedAt` 均为 nil
- 单元：闸门开启后重跑 `repair` → 该日被推出**软** `.completed`（`status == .completed` 且 `closedAt == nil`）
- 单元：闸门开启后用户再完成一项任务 → 走 `TodayViewModel.swift:250-251` 的显式路径，`closedAt != nil`
- 人工：闸门期内完成最后一项 → UI 文案为"已完成最后一项，正在同步确认"，不是"已完成"
- i18n：`today.done.awaiting_sync` 在 `Resources/Localizable.xcstrings` 中有 en 与 zh 两条（zh 文案 = 代码 defaultValue，见项目记忆 string-catalog-artifacts）

**测试审计（§3.6，强制交付项）**
- `grep -n 'focusTask\|frozenTasks\|sortedDraftTasks\|completedTasks' Tests/*.swift` 的输出逐条核对；凡所在测试的 `day.status` 为终态、且断言"为空/为 nil"的，改为 raw 形式 `day.tasks.filter { $0.zone == ... }`
- 已确认必改：`Tests/ModelTests.swift:3892-3893`；待核：`:3218`、`:3825-3829`、`Tests/StateMachineTests.swift:956-957`、`:1056-1057`、`:1171-1172`
- 验收判据：门控落地后，被改写的断言在"故意注入一条 focus 任务到终态日"时**会失败**（证明它仍在检验不变量，没有退化为同义反复）

**人工双机**
- A 完成某日 → 关机；B 跨过 kill time 后上线 → 该日在所有设备上仍为完成态，complete zone 详情完好，无任务被删除

### 13.2.0 Phase B0（容器模式解析，**独立于 §13.2 验收**）

**`StoreMode` 第四态（§4.2.2）**
- 单元：`StoreMode.cloudDetached.cloudKitContainerIdentifier == nil`；`.hasNoRemotePeer == false`；`.allowsSave == false`
- 单元：`.localOnly.hasNoRemotePeer == true`、`.inMemory.hasNoRemotePeer == true`、`.production.hasNoRemotePeer == false`
- 单元：`makeModelContainer(storeMode: .cloudDetached)` 构造出的容器 `ModelConfiguration.allowsSave == false`
- 回归：`Tests/ModelTests.swift:71-82` 五条既有断言**一行不改**仍通过

**`resolveStoreMode` 映射表（#18 的核心，逐行断言）**

| `environment` | `accountStatus` | `identityConfirmed` | `cloudSyncEnabled` | 期望 |
|---|---|---|---|---|
| 含 `XCTestConfigurationFilePath` | 任意 | 任意 | 任意 | `.localOnly` |
| `[:]` | 任意 | 任意 | `false` | `.localOnly` |
| `[:]` | `.available` | `true` | `true` | `.production` |
| `[:]` | `.noAccount` | `true` | `true` | `.localOnly` ← **#18：切库** |
| `[:]` | `.restricted` | `true` | `true` | `.localOnly` ← **#18：切库** |
| `[:]` | `.temporarilyUnavailable` | `true` | `true` | `.cloudDetached` |
| `[:]` | `.couldNotDetermine` | `true` | `true` | `.cloudDetached` |
| `[:]` | `nil`（解析超时，#19 边界 1） | `true` | `true` | `.cloudDetached` |
| `[:]` | `.available` | **`false`**（身份不一致） | `true` | `.cloudDetached` |
| `[:]` | `.noAccount` | **`false`** | `true` | `.cloudDetached`（`identityConfirmed` 优先于账号分支） |

- 反向断言：`resolveStoreMode` 的返回值为 `.cloudDetached` 时，**任何输入组合下都不得**返回 `.localOnly`（否则会新建第二份数据）；反之 `.noAccount + identityConfirmed` 时**不得**返回 `.production` 或 `.cloudDetached`

**store 路径分离（#16 提前到 B0 的部分）**
- 单元：`persistentStoreURL(for: .production).lastPathComponent == "Weekyii.store"`；`(for: .localOnly)` → `"Weekyii.local.store"`；`(for: .cloudDetached)` → `"Weekyii.store"`（**源路径保持云库语义，但实际容器读取其进程级临时副本，不直接打开源库**）
- 编译期：无参 `persistentStoreURL()` 已删除，9 处调用点全部显式传模式
- **本项是 #18 的承重墙**：断言 `.localOnly` 与 `.production` 打开的 URL **不同**。若相同，#18 的"切库"退化为"在云库上以 `.none` 可写建数据"，日后登录即隐式合并 → 违反 #16

**两阶段启动（#19 甲 + 四条边界）**
- 单元：`LaunchState` 存在 `.resolving`；阶段 1 期间 `WeekyiiApp` 持有的 `launchState` 为 `.resolving` 且**未创建任何 `ModelContainer`**
- 单元（边界 1）：账号解析超过 `maxWait` 仍未确认 → 建 `cloudDetached` 容器，**不是** `.production`、**不是** `.localOnly`
- 单元（边界 2）：容器创建路径全仓只有**一处**（`WeekyiiApp.init` 的阶段 2 + 两条 `.failed` 态重试）；断言不存在任何"账号到达后重建容器"的代码路径。建议以 §7.2.3 的 `didOpenContainer` + `assertionFailure` 守卫实现
- 单元（边界 2 的洞，§7.2.3 ③）：阶段 1 判定为 `.localOnly` 或 `.cloudDetached` 后进入 `.failed`，调 `retryPersistentStore()`（`WeekyiiApp.swift:619`）→ 重建的容器 storeMode **等于阶段 1 的判定值**，不是 `.production`。`:629` 的 `restoreLatestPersistentStoreSnapshot()` 同
- 单元（边界 3）：只读降级态下把 `accountState` 改为 `.available` → 容器**未被重建**，且"需要重启"提示被触发
- 单元（边界 4）：阶段 1 不读取任何上一次降级的持久化结果（无状态）
- 人工：飞行模式冷启动 → 占位页 → `maxWait` 后进入只读态，能看到既有数据，任何写操作被禁用或提示，**不静默吞点击**
- 人工：只读态下去系统设置登录 iCloud → 回到 App → 出现"需要重启"提示 → 重启后进入 `.production` 且数据完整

**`cloudDetached` 容器可构造（§7.2.2 两个硬前置）**
- 单元：`bootstrapPersistentContainer(storeMode: .cloudDetached)` 成功返回 `.ready` —— 这要求 §4.4 的引导期 repair 已删除、§4.11 的播种已移出 `makeModelContainer`。二者任一未做，本用例失败；实际读取路径为进程级临时副本
- 单元：`cloudDetached` 容器上任何 `context.save()` 抛错（确认只读是真的）
- **实测（已通过）**：`cloudDetached` 打开前后，比对 `Weekyii.store` 及其 `-wal` / `-shm` 源文件的校验和；源文件保持**零字节变化**。直接打开源库时发现 `-shm` 会变化，已通过“进程级临时副本”退路修复，因此不再直接打开任何源库文件。

**`storeMode` 单点解析、多处一致（§4.8 的错配风险）**
- 单元：`makeModelContainer` 实际使用的 `storeMode`、注入 `AppHealthCoordinator` 的 `storeMode`、`persistentStoreURL(for:)` 解析出的 URL 三者**来自同一个实例字段**。断言方式：构造 `.localOnly` 后检查 coordinator 的 `settlement(now:)` 返回 `.noRemotePeer` 且容器 URL 是 `Weekyii.local.store`；构造 `.cloudDetached` 后检查返回 `.unsettled` 且 URL 是 `Weekyii.store`
- 反向断言：**不存在**"闸门按 `.localOnly` 全开、容器却按 `.production` 建"的组合。这是 §4.8 补注里那条错配的回归护栏
- 单元（`AppHealthCoordinator` 默认值）：不传 `storeMode` 与 `cloudSyncMonitor` 时，`settlement(now:)` 返回 `.unsettled`（**不是** `.noRemotePeer`）→ 闸门关闭。默认值必须 fail-closed，且不得是 `.localOnly` / `.inMemory`

### 13.2 Phase B（四态闸门）

**闸门真值表（§4.2.1，单一谓词；取代 v3 的三级谓词表）**

| 构造条件 | `settlement(now:)` | `localReconcileAllowed` | `syncedWritesAllowed(now:)` |
|---|---|---|---|
| `storeMode == .localOnly`，**不创建 monitor** | `noRemotePeer` | true | **true** |
| `storeMode == .inMemory`，同上 | `noRemotePeer` | true | **true** |
| `storeMode == .cloudDetached`（#19 边界 1 超时降级） | `unsettled` | true | **false** |
| `.production` + monitor 未 start | `unsettled` | true | false |
| `.production` + `accountState == .checking` | `unsettled` | true | false |
| `.production` + `.unavailable(.temporarilyUnavailable)` | `unsettled` | true | false |
| `.production` + `.unavailable(.unknown)` | `unsettled` | true | false |
| `.production` + `.failed(_)` | `unsettled` | true | false |
| `.production` + `.unavailable(.noAccount)` | `noInboundChannel` | true | **false** |
| `.production` + `.unavailable(.restricted)` | `noInboundChannel` | true | **false** |
| `.production` + `.available` + 未调 `markContainerLoaded(...)` | `unsettled` | true | false |
| `.production` + `.available` + `setupSucceeded == false`（基线后收到 setup 失败事件） | `unsettled` | true | false |
| `.production` + `.available` + 有在飞事件 | `unsettled` | true | false |
| `.production` + `.available` + 事件已结束 < `quietPeriod` | `unsettled` | true | false |
| `.production` + `.available` + 事件已结束 ≥ `quietPeriod` | `settled` | true | **true** |
| 以上任一 `unsettled` 行 + `now - monitorStartedAt ≥ maxWait` | **仍 `unsettled`** | true | **仍 false** |

四条**必须与旧版本期望相反**的断言（v2 与 v3 的用例都已作废，不得照抄）：
1. `.noAccount` / `.restricted` 的 `syncedWritesAllowed` 为 **false**（v2 写 true；v3 写"2a true / 2b false"，**都错**，#18 裁决为全关）
2. 超 `maxWait` 的 `syncedWritesAllowed` 为 **false**（v2 写 true；v3 写"2a true"，**都错**）
3. 超 `maxWait` 的 `settlement` 仍是 `unsettled`，不是 `settled` —— **`maxWait` 不出现在这张表里**，它不改变任何事实判定，也不放开任何写入
4. `cloudDetached` 是 `unsettled` 而**不是** `noRemotePeer` —— 这是 §4.2.2 那个洞的回归护栏，一旦有人把只读云库标成 `.localOnly`，本行立即失败

**并发事件追踪（§4.10，审查第 2 轮点 3）**
- 单元：投递"事件 A 开始（identifier A）"→"事件 B 开始（identifier B）"→"事件 B 成功结束"三条通知 → `settlement == .unsettled`（v2 的单标量会在此误报 `.synced`）
- 单元：紧接投递"事件 A 成功结束，`endDate` 晚于 B" → quiet 期从 **A 的 endDate** 起算，不是 B 的；断言 `now = A.endDate + quietPeriod - ε` 时 `unsettled`，`now = A.endDate + quietPeriod` 时 `settled`
- 单元：**失败事件也必须清出在飞集合** —— 投递"A 开始"→"A 失败结束" → `inFlightEvents.isEmpty == true`（不得让失败事件把闸门永久锁死），`eventState == .failed`
- 单元：`.setup` 类型事件失败 → `setupSucceeded == false` → 即便 account `.available` 且无在飞事件，`settlement == .unsettled`
- 单元：`.setup` 成功后再失败一次 → `setupSucceeded` 回到 false（覆盖"曾经成功过"的粘滞）
- 单元：`.export` / `.import` 交错时，`scheduleImportedChanges()` 仍**只**由 `.import` 成功触发（`importRevision` 不因 export 递增）
- 单元：`eventState` 的取值仅供 UI；闸门只读 `settlement`。断言二者可以不一致（例：A 在飞、B 成功 → `eventState` 为 `.syncing` 而非 `.synced`）
- 推断项（需在实施时验证）：`Event.identifier` 在同一事件的"开始/结束"两次通知中稳定不变。若实测不稳定，改用 §4.10 的兜底键 `(storeIdentifier, type, startDate)`，并补一条"A 开始 + A 结束"能被正确配对删除的用例

**事件基线（§4.12，用户第 3 轮提出的死锁）**
- 单元：容器建成后调 `markContainerLoaded(at: T)` → `setupSucceeded == true`、`lastEventEndedAt == T`
- 单元（规则②，基线可被覆盖）：`baseline` 之后投递一个**失败的 `.setup` 事件** → `setupSucceeded == false` → `settlement == .unsettled`。这是"基线不是粘滞"的回归护栏
- 单元（严格 fail-closed）：`.production` + `.available` + 仅调 `markContainerLoaded` + 零事件 → `settlement == .unsettled`；当前进程的 setup 成功、无在飞事件且 quiet period 满足后才允许 `settled`
- 单元：未调 `baseline` 时（monitor 已 start）→ `settlement == .unsettled`，不得因 `lastEventEndedAt == nil` 而崩
- **实施期诊断**：记录当前进程事件序列与结算 blocker，覆盖 (a) 已有云端数据的设备、(b) 私有库为空的新账号；日志只用于诊断，不得决定是否放开 Tier-2
- 人工（诊断可见性）：`SettingsView.swift:632-646` 的状态行能区分 `noRemotePeer` / `settled` / `noInboundChannel` / `unsettled`，且 `unsettled` 时能看出卡在哪条 guard（在飞事件 / setup / quiet 未满 / 无基线）

**Tier 分层生效（§4.3，单一开关）**
- 单元：`allowSyncedWrites == false` 时 reconcile 后**所有同步字段零变化** —— 逐项断言 `day.status`、`day.expiredCount`、`day.killTimeHour/Minute`、`week.status`、`week.completedTasksCount`、`week.expiredTasksCount`、`week.totalStartedDays`、`HabitModel.generatedThroughDayId`
- 单元：同一场景下 Tier-1 **有**变化 —— `AppState.lastRolloverAt` 被写、通知被调度、Widget 快照被更新；且 `AppState.lastProcessedDate` **无**变化（覆盖 §4.6，否则 kill time 在闸门期静默失效）
- 单元（#18 的改判，Tier-2b 终态语义）：`allowSyncedWrites == false` 时，一个 `killTime` 已过的 `execute` 日**不会**被标 `.expired`（`processKillTime` / `processCrossDay` / `processStaleOpenDaysBeforeToday` 三者全部短路）；`allowSyncedWrites == true` 时会
- 单元：`allowSyncedWrites == false` 时 `mergeDuplicateWeeksAndDays`（`:486`、`:498`）、`mergeDuplicateBuiltInTaskTypes`（`:523`）、`processExpiredSuspendedTasks`（`:109`）**零删除**
- 单元：`allowSyncedWrites == true`（默认值）→ 上述全部发生。**默认值必须为 true**，否则 `Tests/StateMachineTests.swift:795-822` 与 `:319,730,731,1460,1474,1484,1498` 七处两参调用回归
- 单元（§4.2.4 的反向护栏）：`DataInvariantRepairing` 协议**仍是单参** `repair(referenceDate:)`；`repair` 实现（`:396-437`）diff 为空。断言方式：编译期即可（若有人按 v3 加了 `allowsIrreversible:`，`Tests/StateMachineTests.swift:795-822` 的调用点会编译失败）
- 单元：`reconcile(trigger: .manualResync, force: true)` **不**绕过闸门（§4.8，覆盖待裁决 #3）
- 单元：`reconcile(trigger: .remoteImport, force: true)` 同样**不**绕过闸门（§4.8）—— `force` 只绕过节流，不绕过数据安全边界
- 单元：`WeekyiiApp.swift:579` 的 `importRevision` 变更回调传的是闸门判定结果，不是硬编码 `force: true`

**播种移出容器构造（§4.11，审查第 2 轮点 4）**
- 单元：`makeModelContainer(storeMode: .localOnly)` 返回后，`context.fetch(FetchDescriptor<TaskTypeDefinition>())` **为空**（`WeekyiiPersistence.swift:144` 已移除）
- 单元：`TaskTypeCatalog.load(in:)` 是纯读 —— 调用前后 `context.hasChanges == false`（`TaskTypeDefinition.swift:95` 已删除）
- 单元：闸门开启后播种执行 → 三条内置类型存在且 `idRaw` 为 `["regular","ddl","leisure"]`
- 单元：闸门关闭期间调 `load()` → 返回空 catalog，`definition(for: "regular")` 落到 `builtInFallback`，**不抛错、不写库**（§4.11 空 catalog 安全性）
- 单元：`seedBuiltInTypesIfNeeded` 拆分后，**插入分支与回填分支都只在 `syncedWritesAllowed == true` 时执行**（v3 曾写"插入受 `allowsIrreversible` 控制、回填不受控制"，#18 后二者同档，该表述作废）。分类上插入 = Tier-2b、回填 = Tier-2a，仅用于文档，不用于门控
- 回归：`Tests/ModelTests.swift:1464-1475`、`:1477-1499`、`:1501-1531`、`:412-428`、`:481-496` 五条全部保持通过且**一行不改**（§4.11 已核实它们自带显式播种）

**引导期（§4.4）**
- 单元：`bootstrapPersistentContainer` 内不再出现 `DataInvariantRepairService(...).repair(...)` 调用（静态断言或行为断言：构造一个含重复周的 store → bootstrap 后重复**仍在**，未被合并）
- 单元：`validateContainerConsistency` 失败时不阻断启动（D1 护栏，§6）

**人工双机**
- 新设备首次登入 iCloud，下载完成前：不出现重复周/重复日、不物化习惯任务、不改写周三个计数器、不合并内置任务类型、**日不会过期**
- 下载完成并静止后：上述全部自动发生，无需用户手动"重同步"
- 一台设备退出 iCloud（运行中 `.available → .noAccount`，容器已是 `.production`）→ 落 `noInboundChannel` → Tier-2 全关 + 出现"需要重启"提示；**重启后**落 `.localOnly` → 走 `Weekyii.local.store` → `noRemotePeer` → 全开，首页可用（本周/今日存在）
- **注意上条的语义变化**：v3 曾期望"退出 iCloud 后该机首页仍立即可用"。#18 裁决后，**重启前不可用（只读 + Tier-2 全关），重启后走独立本地库才可用**。这是 #18 的有意代价，不是回归

### 13.2.5 Phase E-1.5 / B.5（账号身份护栏，#9 裁决为 Phase B 最终验收前置）

> B 的闸门核心可以先实现，但 Phase B 不得在本节用例未通过时宣称完成。

**已落地（2026-09-20）**：`CloudSyncMonitor.settlement()` 作为 `settled` 的唯一判定点，在返回 `.settled` 时把 `currentUserRecordID` 写入设备本地 `UserDefaults.lastSyncedUserRecordIDKey`；`configureIdentity(currentUserRecordID:storedUserRecordID:)` 在启动与 `CKAccountChanged` 后比对，不一致即 `identityConfirmed = false` → `unsettled(.identityMismatch)`。本节下列用例在 `ModelTests` 中均有对应测试：`test_identityGuard_nilStoredRecordID_doesNotBlockSettlement`、`test_identityGuard_matchingStoredRecordID_doesNotBlockSettlement`、`test_identityGuard_mismatchedStoredRecordID_closesGateEvenWhenQuiet`、`test_identityGuard_settledPersistsCurrentUserRecordID`、`test_identityGuard_runtimeAccountSwitchToDifferentID_closesGate`、`test_identityGuard_runtimeAccountSwitchBackToSameID_keepsGateOpen`。

- 单元：`lastSyncedUserRecordID == nil`（从未同步） → 不影响 `syncedWritesAllowed`
- 单元：`lastSyncedUserRecordID == currentUserRecordID` → 不影响
- 单元：两者**不一致** → 即便事件已静止，`settlement == .unsettled` 且 `syncedWritesAllowed == false`（身份未确认 = 输入不完整，不新增第五态）
- 单元：每次进入 `settled` 后 `lastSyncedUserRecordID` 被更新为当前值
- 单元：该键存于设备本地 `UserDefaults`，**不在** SwiftData schema 中（不开 V9）
- 单元：B0 的阶段 1 已阻止启动期跨账号导出后，E-1.5 的**独立**覆盖面是"进程存活期间换账号"—— 断言这条路径：`settled` 状态下投递 `CKAccountDidChange` 且新 `userRecordID` 不同 → 闸门关闭
- 明确记录局限：E-1.5 **不能**阻止框架在 `.private(id)` 容器上把 A 的记录导出到 B；只有 #19 甲的延后建容器能阻止。此条须在代码注释与本文件中同时存在

### 13.3 Phase C（kill time）
- 人工双机：两设备设不同默认 kill time → 24 小时后今日 kill time 稳定为同一值，不再每日拉锯
- 单元：`syncTodayDefaultKillTimeIfNeeded` 在 `followsDefaultKillTime == false` 或日值非模型默认（`DayModel.swift:11-12` = 23:45）时**不写入**（§5 C.1 幂等化）
- 单元：C.2 落地后，`defaultKillTimeHour/Minute` 的变更经 `NSUbiquitousKeyValueStore` 到达对端（`Resources/Weekyii.entitlements:15-16` 已声明）

### 13.4 Phase E-1'（#16 双库的开关 UI 与双向迁移，串行在 B 之后）

> **路径分离部分已在 §13.2.0 验收**（B0 的承重墙），本节只覆盖开关 UI 与数据迁移流程。

- 单元：设置页切换前导出当前库并为目标库建立恢复点；当前实现使用 `backupPersistentStoreIfExists(storeURL:)` + `DataArchiveService.export/importReplacing`，不依赖记录级合并
- 单元：四个快照列表调用点（`:115-116`、`:923-924`、`:2672`、`WeekyiiApp.swift:607-608`）只列出当前模式对应库的快照
- **重点用例**：`SettingsView.swift:2679` `restoreSnapshot(named:to:)` 在 `cloudSyncEnabled == false` 时恢复目标是 `Weekyii.local.store`，**不是** `Weekyii.store`（这是唯一一条静默数据丢失路径）
- 人工（云 → 本地）：关闭同步 → 导出当前云库并建立恢复点 → 本地库内容与关闭前一致 → 云库文件**保留未动** → 重启后 CloudKit Dashboard 不再出现该设备写入
- 人工（本地 → 云）：重新开启 → 云库非空时**必须弹二选一**，不得静默 `importReplacing`；选 a 前自动快照；选 b 时本地库文件改名留存
- 人工：两个方向切换后数据条数与切换前一致（导出/导入经 `DataArchiveService.export:144-158` / `importReplacing:174-207`，`currentFormatVersion` 仍为 1、`currentSchemaVersion` 仍为 8，**不需重跑 `-initializeCloudKitSchema`**）
- 反向断言：仓内不存在任何"两个 store 记录级合并"代码路径（§7.1.1 明确禁止）
- 人工：切换开关后提示"重启后生效"，运行时**不**热切换容器
- 人工（#18 派生流程，§4.2.2）：从未登录 iCloud 的设备（数据在 `Weekyii.local.store`）日后登录 → **不自动合并**，走同一套二选一流程；设置页有一行持久说明这一点

### 13.5 Phase E-2'（身份不一致的三选 UI，#19 甲的收尾）——已实现

> 两阶段启动、身份 mismatch 的 fail-closed 与只读提示已落地；三选 UI 已实现。

- 已落地：`identityConfirmed == false` 时进入 `cloudDetached` 只读保护，设置页显示账号变化与重启提示，且不允许在本进程内升级写入。
- 已实现：身份不一致后的三选（以云端为准 / 以本机为准 / 关闭同步转本地）、启动时自动快照后的用户决策持久化（`pendingIdentityResolutionKey`），以及重启后按选择执行（`performIdentityResolution`）。
- 验收约束：无论三选最终如何实现，`syncedWritesAllowed == false` 必须全程保持；不得在当前进程内重建为可写 CloudKit 容器。**当前实现满足此约束。**
- 已宣称：设备退出 A、登入 B 的完整用户决策路径已完成，S8 的三选 UI 验收标为通过。

### 13.6 Phase A.7（GC，**#20 锁定：独立于 Phase A/B 验收**）

> #20 第 4 条：GC 不与 Phase A、B 同轮提交、同轮验收。本节自成一轮。

- 单元：回收线 = 当前周 `startDate - 8 周`；只删 `day.status == .expired` 且 `day.date <` 回收线的日里 `zone ∈ {draft, focus, frozen}` 的任务
- 单元：`DayModel` 本身不删；`zone == .complete` 的任务不删；`day.expiredCount` 与 `completedTasks` 保持
- 单元：GC 触发条件是**同步字段的纯函数** —— 不读 `UserDefaults`、不读 `AppState`、不读 `Date()` 以外的设备本地状态（可用"同一 store + 同一注入 now → 两次运行删除集合完全相同"验证）
- 单元：GC 只在 `syncedWritesAllowed == true` 时执行；`noInboundChannel` 与 `unsettled` 下**不**执行
- 单元：GC 在 `storeMode == .cloudDetached` 下**不**执行（只读容器上 `save()` 本就抛错，但必须显式短路，不得靠抛错兜底）
- 人工双机：A 执行 GC 后，B 上同一批任务同样消失且只消失一次；对已删记录的再删为 no-op
- **#20 的五条强制表述必须逐条出现在代码注释与本文件中**（§3.7）：①GC 不是绝对安全；②离线设备跨越回收窗口后重新上线，任务可能复活；③这是已知数据一致性风险；④GC 独立于 Phase A/B 验收；⑤不得对外宣称"删除绝不复活"
- 交付检查：仓内（含 README、App Store 文案、设置页说明）**不存在**任何"删除绝不复活 / 绝对安全 / 永不恢复"一类表述
- 明确不做：tombstone、版本水位、V9。若未来产品要求绝对防复活，另起设计（#20 裁决原文）

### 13.7 Phase F（习惯物化）
- 单元：`records` 含同日 pending + completed 两条时，`recordStatusMap` 返回 completed（`HabitStatistics.swift:111-123` 既有行为不回归）
- 单元：v2 的"保留最早记录"去重 pass 已删除；同日多条记录合并语义为 `completed > missed > pending`
- 单元：水位线由 `records` 推导后，删除最新 record 不会导致重复物化（依赖闸门 + `HabitTaskMaterializer.swift:149` dup 检查）
- 单元：闸门关闭（`syncedWritesAllowed == false`）时 `HabitTaskMaterializer.sync` 整体不执行，`generatedThroughDayId` 不变，且**不产生任何 `TaskItem`**（分类上属 Tier-2a，§4.3；#18 后与 2b 同档门控）
- 单元：闸门关闭时**不物化习惯任务**是 #18 点名的风险之一（"习惯物化可能在迟到任务未到达时重复创建"）—— 断言 `HabitTaskMaterializer.swift:149` 的 dup 检查在部分同步视图下**不足以**防止重复，故必须靠闸门
- 人工双机：A 物化某日习惯任务后离线；B 上线 → 该日**不出现**重复习惯任务
- 人工双机（#18 的切库路径）：从未登录 iCloud 的设备在 `Weekyii.local.store` 上物化习惯任务 → 落 `noRemotePeer` → 正常物化，**不受闸门影响**（这是 #18 用切库换来的可用性）

### 13.8 文档与表述（不由测试覆盖，但属交付项）
- 本文件 §0 不含"同步链路本身 100% 健康"一类断言；只保留"当前代码未发现手写 CKRecord 逻辑"+ 适用边界声明（#10）
- 本文件 §3.7 含 #20 的**五条**强制表述（GC 不是绝对安全 / 离线跨窗口重上线任务可能复活 / 已知数据一致性风险 / 独立于 A、B 验收 / 不得对外宣称"删除绝不复活"）
- 本文件 §3.2 记录产品语义 = **a. 保留但隐藏**，并逐条对应裁决给出的四条满足条件
- 本文件 §7.2 记录 #19 的**四条**进程级终止边界，且 §7.2.1 标明乙、丙已否决
- 本文件 §4.2.2 记录 `cloudDetached` 的存在理由：**"没有入站通道" ≠ "没有对端"**
- 本文件 §4.12 记录 Monitor 事件丢失导致的永久只读风险，以及方案 1 的当前进程事件边界；不声称可恢复被杀进程历史
- 本文件 §6 含"D2 未落地前，跨时区多端同步不算解决"
- 本文件 §4.5 / §7.2.1 / §4.2.1 三处一致声明：**`maxWait` 不是数据闸门**，超时不放开任何同步字段写入
- 全仓（含 README、App Store 文案、设置页说明）不存在"删除绝不复活 / 绝对安全 / 同步完全可靠"一类绝对表述
- 本文件不把时间等待当作同步完成证明；`maxWait` 永不放开同步字段写入。方案 1 已完成当前进程事件路径；B0 的只读零写入校验已在 iPhone 17 Pro 模拟器上通过
