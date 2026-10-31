# iCloud 同步第五轮修复 · 本地 Agent 接续文档

- 分支：`notion-claude/feat-in-app-purchase`（GitHub `RaHakubun/Pure-AI-Weekyii`）
- 起点：`0803e76`（第四轮审查报告 `ICLOUD_SYNC_REVIEW_ROUND4_2026-10-27.md`）
- 编写方：云端 Agent（无 Xcode，**所有改动未经编译**）
- 接续方：本地 Agent（macOS + Xcode + Computer Use）

## 0. 你需要先知道的

1. 云端 Agent 只能通过 GitHub API 推送单文件 < 64KB 的改动。以下 3 个大文件的改动**没有直接推送**，而是放在补丁里：
   `docs/handoff/icloud-round5-large-files.patch`
   - `Resources/SettingsView.swift`
   - `Services/CloudSyncCoordinator.swift`
   - `Tests/CloudSyncCoordinatorTests.swift`
2. 其余小文件已直接提交到分支。**不打补丁也应能编译**；但 `CloudSyncCoordinatorTests.test_bannerKind…`（第 81 行附近）会失败，因为 `.initialEnableDecisionRequired` 现在会显示横幅——补丁里已改断言。
3. 工程文件 `project.pbxproj` 不是文件夹同步型：本轮**没有新增任何 Swift 文件**，新类型都放在已有文件里。
4. 新文案一律 `String(localized: "key", defaultValue: "中文")`，没有改 `Localizable.xcstrings`。编译后让 Xcode 自动抽取，再补英文。
5. 提交身份随意；完成后 push 回同一分支。

## 1. 操作步骤

```bash
git fetch origin && git checkout notion-claude/feat-in-app-purchase && git pull
cd "$(git rev-parse --show-toplevel)"   # 补丁路径相对仓库根目录
git apply --3way Weekyii/Weekyii/docs/handoff/icloud-round5-large-files.patch
```

1. 用 Xcode 打开 `Weekyii/Weekyii/Weekyii.xcodeproj`，Scheme `Weekyii`，目标 iOS 模拟器，`⌘B`。
2. 修编译错误（见 §3“高风险 API”）。只做最小修改，不改设计。
3. 跑测试：先 `CloudSyncETests`、`CloudSyncD1Tests`、`CloudSyncD2Tests`、`CloudSyncCoordinatorTests`，再全量（上一轮全量为 528 个）。
   ```bash
   xcodebuild test -project Weekyii/Weekyii/Weekyii.xcodeproj -scheme Weekyii \
     -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WeekyiiTests/CloudSyncReconcilerTests
   ```
4. 新测试失败时，先判断是测试假设错还是实现错（§4 有每个测试的意图）。实现错就修实现。
5. 本地化：Xcode 打开 `Localizable.xcstrings`，确认新 key 已抽取，补英文（§5 列表）。
6. 删除补丁文件（已应用），提交并推送：
   ```bash
   git rm Weekyii/Weekyii/docs/handoff/icloud-round5-large-files.patch
   git commit -am "fix(icloud): 第五轮——应用大文件补丁、编译修正、英文文案"
   git push origin notion-claude/feat-in-app-purchase
   ```
7. 按 §6 在 CloudKit Console 部署 Production Schema，再按 §7 做双设备验收，结果追加到本文末尾“验收记录”。

## 2. 本轮改了什么（按文件）

| 文件 | 改动 | 对应问题 |
|---|---|---|
| `Services/CloudSyncMetadataStore.swift` | 元数据新增 `quarantinedRecords`、`quarantineCodecSignature`（可选，旧文件兼容）；`discardPendingChanges(for:through:)`；隔离增删查；`resetSynchronizationStateForAllAccounts()`；收件箱 `prepare()` 在解码器签名变化时清空隔离并重置引擎状态（触发全量拉取）；`append`/`appendAuthoritativeSnapshot` 支持隔离名单，全量快照不会因“解不开”而误删 | H1、N1 |
| `Services/CloudRecordCodec.swift` | `decoderSignature`（各 kind 的 payloadVersion 列表） | H1 |
| `Services/CKSyncEngineTransport.swift` | 逐条解码，解不开的隔离而非整批失败；处理 `.fetchedDatabaseChanges` 的 Zone 删除 → 重置本账号同步状态并抛 `remoteZoneDeletedReason`；发送/拉取遇 `zoneNotFound`/`userDeletedZone` 同样处理；冲突返回的服务器记录解不开时隔离；删除遇 `unknownItem` 视为已删除 | H1、H4、L2 |
| `Services/CloudKitRecordAdapter.swift` | 错误映射：`unknownItem → serverRecordChanged`（走重发），`zoneNotFound/userDeletedZone → .other(remoteZoneDeletedReason)` | H4 |
| `Services/CloudKitInfrastructure.swift` | `inspect` 跳过解不开的记录并返回其名单；`recordsInWeekyiiZone()` 改为 `recordZoneChanges(inZoneWith:since:)` 分页，不再依赖 CKQuery / Queryable 索引 | H1、部署风险 |
| `Services/CloudSyncTransport.swift` | `CloudSyncZoneInspection.undecodableRecordNames` | H1 |
| `Services/CloudSyncReconciler.swift` | 解码失败隔离并跳过（报告 `quarantinedRecords`）；隔离键不参与双向；去掉逐键全量快照（性能）；冲突重发时服务器已无该记录则以无系统字段的新记录重发；提交时对已结算的键丢弃收件箱中 ≤ 确认序号 / 重发序号的旧条目（防旧服务器版本回放覆盖本机胜者）；同习惯同日的重复习惯任务收敛 | H1、H3、H4、**N1**、M2 |
| `Services/CloudSyncLocalStore.swift` | `apply` 失败时 `context.rollback()` | M1 |
| `Services/HabitTaskMaterializer.swift` | 习惯任务 / 打卡记录用 `HabitDeterministicID`（SHA256 → UUID v5 风格）生成确定性 ID，两台设备离线物化同一天不再产生两份 | M2 |
| `Services/DataArchiveService.swift` | `importReplacing` 替换前调用 `CloudSyncLocalReplacementGuard.prepareForLocalReplacement`：关闭同步、重置所有账号本机同步状态、发通知 | H2 |
| `App/WeekyiiApp.swift` | 收到上述通知 → `cloudSyncCoordinator.setRequested(false)` | H2 |
| `Services/CloudSyncTypes.swift` | 横幅新增 `.initialDecision` | M6 |
| `App/ContentView.swift` | 首次决策横幅可直接选择；过期横幅“续订”打开会员页；换账号弹窗“使用本机数据”不再是主按钮，云端有数据时改为破坏性 + 二次确认 | M3、M4、M6 |
| 补丁：`SettingsView.swift` | 回滚备份、恢复点恢复前同样调用替换守卫；导入/恢复/回滚确认文案加 iCloud 提示；设置页新增“重置本机同步状态”；过期时“续订会员以恢复 iCloud 同步”；`onAppear` 每次都重新判断是否弹首次决策 | H2、M4、运维 |
| 补丁：`CloudSyncCoordinator.swift` | `resolveInitialEnable` 选择与待决策不匹配时恢复决策状态，而不是卡在 `.syncing` | L1 |
| 补丁：`CloudSyncCoordinatorTests.swift` | 横幅断言改为 `.initialDecision` | — |
| `Tests/CloudSyncETests.swift` | 9 个新测试（§4） | — |
| `docs/icloud-sync-runbook.md` | 按 CKSyncEngine 架构重写 | — |

**N1（第四轮报告之外，云端 Agent 复核时发现）**：冲突重发或部分失败后，旧服务器版本仍留在持久收件箱（确认游标之后），下一轮会被当成“远端新编辑”应用，把本机胜者回退。是否触发取决于 CKSyncEngine 是否回送自己的写入；修复两种情况都安全。

## 3. 高风险 API（最可能编译不过的地方）

| 位置 | 写法 | 若编译失败 |
|---|---|---|
| `CloudKitInfrastructure.recordsInWeekyiiZone()` | `try await database.recordZoneChanges(inZoneWith: zoneID, since: token)`，读取 `.modificationResultsByID`、`.changeToken`、`.moreComing` | 以 SDK 实际签名为准（iOS 17+ 的 `CKDatabase.recordZoneChanges(inZoneWith:since:desiredKeys:resultsLimit:)`）；`modificationResultsByID` 值是 `Result<CKDatabase.RecordZoneChange.Modification, Error>`，记录在 `.record` |
| `CKSyncEngineTransport` 处理 `.fetchedDatabaseChanges` | `event.deletions` 的元素取 `.zoneID.zoneName` | 元素类型为 `CKSyncEngine.Event.FetchedDatabaseChanges.Deletion`，有 `zoneID` 与 `reason` |
| `CKSyncEngineTransport` 删除失败 | 匹配 `CKError.unknownItem` | 用 `(error as? CKError)?.code == .unknownItem` |
| `CloudSyncReconciler` 重发 | `case .delete(_)?, .none:` | 可改为 `default:` |
| `HabitTaskMaterializer.swift` | 顶部 `import CryptoKit`，`nonisolated enum` | 若项目未开 `nonisolated` 类型修饰，去掉 `nonisolated` |
| `SettingsView`（补丁） | `Text(...) + Text(verbatim: "\n") + Text(...)` | Xcode 26 若提示 `+` 弃用，可忽略或改字符串插值 |
| `SettingsView`（补丁） | `RecoveryPointsView` 新增 `@EnvironmentObject settings` | 确认 `NavigationLink` 目的页能拿到 `UserSettings`（Settings 已注入） |

## 4. 新测试（`CloudSyncETests.swift` → `CloudSyncReconcilerTests`）

| 测试 | 意图 |
|---|---|
| `test_undecodableRemoteRecordIsQuarantinedInsteadOfFailingTheCycle` | `payloadVersion = 99` 的远端记录：本轮成功、`quarantinedRecords == 1`、远端记录不被删改、其他记录正常落地、第二轮仍成功 |
| `test_serverRecordChangedWithoutNewerServerVersionResendsWithoutStaleMetadata` | 上传收到 `serverRecordChanged` 但拉不到更新版本（对应 CloudKit `unknownItem`）：以新记录重发成功 |
| `test_conflictResendDoesNotRevertLocalWinnerOnNextCycle` | N1 回归：冲突重发后再跑两轮，本机胜者与远端都保持“local winner” |
| `test_duplicateHabitTasksForSameDayConvergeOnDeterministicID` | 同习惯同日：本机随机 ID 草稿 + 远端确定性 ID 草稿 → 只留确定性 ID，远端也只有它 |
| `test_habitDeterministicIDIsStableAndDistinctPerKind` | ID 稳定、按日不同、任务与打卡不同 |
| `test_discardPendingChangesDropsOnlySettledKeysUpToSequence` | 只丢指定键、且只丢 ≤ 序号的条目 |
| `test_quarantineMatchesByCanonicalRecordName` | 隔离判定、计数、签名、解除 |
| `test_resetSynchronizationStateForAllAccountsClearsEveryAccount` | 多账号元数据全部清空 |
| `test_initialDecisionStatusSurfacesBanner` | 首次决策状态出横幅；未开启同步不出 |

注意：`InMemoryCloudSyncTransport` 会把自己的写入回送到变更日志（等同 CKSyncEngine 回送的情形）。如果第 3 个测试在未修复代码上也能通过，说明内存传输没有复现“旧版本留在收件箱”，可再写一个直接操作 `CloudSyncDurableInbox` 的测试；不强制。

## 5. 新文案 key（需补英文）

| key | 中文 | 建议英文 |
|---|---|---|
| `settings.icloud.replacement_notice` | iCloud 同步会先关闭；重新开启时将让你选择以本机还是 iCloud 的数据为准。 | iCloud sync will be turned off first. When you turn it back on, you'll choose whether this device or iCloud is the source of truth. |
| `settings.icloud.renew` | 续订会员以恢复 iCloud 同步 | Renew membership to resume iCloud sync |
| `settings.icloud.reset_state` | 重置本机同步状态 | Reset Sync State on This Device |
| `settings.icloud.reset_state.subtitle` | 不删除任何数据；关闭同步并清除本机同步记录 | Deletes no data; turns sync off and clears this device's sync records |
| `settings.icloud.reset_state.title` | 重置本机同步状态？ | Reset sync state on this device? |
| `settings.icloud.reset_state.confirm` | 关闭同步并重置 | Turn Off Sync and Reset |
| `settings.icloud.reset_state.message` | 本机和 iCloud 中的数据都不会被删除…… | Nothing on this device or in iCloud is deleted. When you turn sync back on, Weekyii checks iCloud again and asks which data to keep. Use only if sync keeps failing. |
| `settings.icloud.reset_state.done` | 已关闭 iCloud 同步并重置本机同步状态。需要时可重新开启。 | iCloud sync is off and this device's sync state was reset. Turn it back on any time. |
| `settings.icloud.reset_state.failed` | 重置失败： | Reset failed: |

`ContentView.swift` 中新增的横幅按钮文案也用了 `defaultValue`，以 Xcode 抽取结果为准（grep `defaultValue:`）。

## 6. CloudKit Production 部署

完整步骤见 `docs/icloud-sync-runbook.md` §2。要点：

1. Development 中 `WYEntityV1` 必须有 8 个字段：`kind`(String)、`payloadVersion`(Int64)、`payload`(Bytes)、`payloadHash`(String)、`blob`(Asset)、`blobRole`、`blobFileName`、`blobContentType`(String)。缺字段就用 Debug 构建写一个带附件的任务和一个心绪印章。
2. Deploy Schema Changes → Production；Production 中复核。
3. 本轮起不使用 CKQuery，**不需要**添加 Queryable 索引。
4. 归档时确认签名后的 `aps-environment = production`（仓库中为 `development`，由 Distribution profile 改写）。
5. Identifiers 中 App ID 勾选 iCloud/CloudKit（`iCloud.com.fluentdesign.Weekyii`）与 Push Notifications；改过就重新生成 profile。
6. 首个 TestFlight 构建安装后，在 Production Console → Records（Zone `WeekyiiSyncZoneV1`）确认有记录写入，并能看到订阅 `WeekyiiSyncZoneV1-subscription-v1`。

## 7. 手动验收矩阵（两台设备、同一 Apple ID，TestFlight 或 Development 构建）

| # | 场景 | 期望 |
|---|---|---|
| 1 | A、B 离线同时改同一任务标题；A 先联网同步，B 再联网 | 最终一致；**A 的标题不会在下一轮被回退**（N1）；B 的版本按本机优先规则胜出后两端一致 |
| 2 | A 删除任务；B 离线编辑该任务后联网 | B 的编辑被保留并重新出现在 A |
| 3 | 用更高 `payloadVersion` 的构建（或在 Console 手改某条记录 `payloadVersion` 为 99）写入一条记录 | 旧构建不报错、不卡“同步已暂停”，该记录保持不动；升级后自动拉取 |
| 4 | 开着同步导入归档 | 导入后同步被关闭；重新开启弹出“使用本机 / iCloud / 合并 / 取消”；云端数据未被删除 |
| 5 | 恢复点恢复、回滚备份 | 同 4 |
| 6 | 系统设置 → iCloud → 管理存储 → 删除 Weekyii 数据 | 本机数据不丢；下一轮重新进入首次决策（云端为空 → “上传本机”） |
| 7 | 会员过期（沙盒订阅到期） | 首页横幅“续订”可打开会员页；设置页出现续订入口；续订后恢复 |
| 8 | 开启同步后不做选择，杀掉 App 重开 | 首页出现首次决策横幅，可直接完成选择 |
| 9 | 两台设备同一天离线打开 App（物化习惯任务）后联网 | 每个习惯当天只有一个任务 |
| 10 | 换 Apple ID（云端已有数据） | “使用本机数据”为红色并有二次确认 |
| 11 | 设置 → 重置本机同步状态 | 同步关闭、数据不变；重新开启后正常决策并同步 |

## 8. 已知未修复 / 需要你判断

- **M5**：冷启动后台推送（App 被杀时收到推送）不会立即同步，下次前台才同步。是否接 `BGAppRefreshTask` 需要产品决定。
- **H3 余项**：对账前的 `beforeApply` 快照仍会读入附件二进制；彻底解决需要在 `WeekyiiPersistence` 提供“不含 blob 的快照”（文件 61KB，云端未改）。
- **合并路径**（首次决策选“合并”）会重置 Zone，此时被隔离的新版本记录会随之丢失。建议：合并前若 `inspection.undecodableRecordNames` 非空则提示用户先升级。
- **Zone 删除后的失败锁存**：`handleRemoteZoneLoss` 抛出 `.other` 后协调器走 `handleFailure`；请确认它不会把 `automaticRetrySuppressed` 锁住导致无法进入首次决策（场景 6）。如会，在 `handleFailure` 对 `remoteZoneDeletedReason` 特判：不锁存、直接重跑启动流程。
- 第四轮报告中的 L3/L4/L5/L7 未处理（低优先级，见报告）。

## 验收记录

填写方：本地 Agent（macOS + Xcode）。日期：2026-10-31。

### 环境

- Xcode 26.3（17C529）/ iOS 26.2 SDK / Swift 6.2.4
- 模拟器：**iPhone 17 Pro**（本机没有 iPhone 16，§1 里的设备名按实际改了）
- 起点 `ab96ef3`，第一次提交 `66650f1`

### 合并过程

1. **本地有未提交改动，补丁一开始打不上。** 本地 10-29 有一轮魔戒主题改动留在工作区（8 个源文件，其中就含 `SettingsView.swift`），云端 Agent 看不到它。`git apply --3way` 直接报 `SettingsView.swift: does not match index`。
2. 处理方式：先把主题改动落库成独立提交（`2d3c222`），再 rebase 到 `ab96ef3` 之上，然后打补丁。补丁插入点在 `RecoveryPointsView` 之前，本地改的是 `SettingsIcon` 内部，相邻但不重叠。
3. `git apply --3way` 结果：**3 个文件全部 clean，无冲突标记**。
4. 补丁文件已 `git rm`（内容已进代码）。因此本文 §0.1 与 §1 里指向 `docs/handoff/icloud-round5-large-files.patch` 的路径**自此失效**。

### 编译

- `xcodebuild build`（Debug / iPhone 17 Pro）**一次通过，没有任何编译错误**。
- 所以本轮**没有"编译修正"**：提交里不含对云端代码的任何改动。
- §3 列的高风险写法全部一次过：`database.recordZoneChanges(inZoneWith:since:)` + `modificationResultsByID` / `changeToken` / `moreComing`、`nonisolated enum` + `import CryptoKit`、`Text + Text` 拼接、`RecoveryPointsView` 新增的 `@EnvironmentObject settings`。
- **唯一与预期不符的是本地化抽取**：`xcodebuild` 命令行构建只产出 `.stringsdata`，不会合并回 `.xcstrings`（IDE 里构建才会）。15 个 key 是手工写入 catalog 的，格式对齐既有条目，`xcstringstool compile` 通过，并已核对英文确实进了 `en.lproj/Localizable.strings` 产物。

### 测试

| 范围 | 结果 |
|---|---|
| 同步相关 7 个类 | **109 例，0 失败** |
| 全量 `WeekyiiTests` | **538 例，0 失败** |
| UI 测试 | 未跑（见下） |

- **失败的测试：无。**
- 基线实测是 **529**（不是本文写的 528），+ 新增 9 = **538**。§1 的"预期 537"作废，以 `xcodebuild test` 输出为准。
- §4 的 9 例全部通过，名字与意图一一对应。
- UI 测试没跑的理由：本轮 UI 改动只有设置页两个按钮和首页横幅按钮，不涉及列表/拖拽/导航；且 `testPendingWeekDetailShowsDraftCrudEntryPoints` 在 `28149dd` 就已失败，跑起来只会把既有噪声混进结论。

### 遗留与需人确认

1. **N1 回归测试可能"假过"。** `test_conflictResendDoesNotRevertLocalWinnerOnNextCycle` 通过，但**没有做"把缺陷改回去看它失败"的对照**。按 §4 的提示，如果 `InMemoryCloudSyncTransport` 没复现"旧版本留在收件箱"，这例会无条件通过。要确认得临时回退 reconciler 的收件箱丢弃逻辑再跑一次，本轮未做。
2. **§8 的"Zone 删除后的失败锁存"本轮未核查**（任务边界只要求合并/编译/测试）。
3. **§6 Production 部署、§7 双设备验收矩阵本轮未做**，11 项全部待人工执行。
4. 测试数与文档口径不一致的问题建议统一：以后写"以 `xcodebuild test` 输出为准"，不写死数字。

### 是否有改动超出补丁范围

- **源码：没有。** 三个补丁文件之外，未改任何 `.swift`。
- **文案：有，属于任务要求范围。** `Resources/Localizable.xcstrings` +240 行（15 个 key，中英各一）。原计划靠 Xcode 自动抽取，实际是手工写入。
- **仓库结构：有。** 删除了补丁文件本身；另有一个与 iCloud 无关的独立提交 `2d3c222`（本地主题 WIP 落库，为了解开补丁冲突）。
