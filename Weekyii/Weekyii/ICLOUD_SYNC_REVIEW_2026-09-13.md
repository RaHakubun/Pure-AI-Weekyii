# codex/icloud-sync 审查报告

审查对象：`/Users/luobowen/handwrittenfnn/weekyii/.worktrees/icloud-sync`（分支 `codex/icloud-sync`，基点 `5ea21a7`）
审查方式：**只读**。未修改任何代码、未提交、未切换分支。所有结论均有命令输出或文件行号支撑。
审查日期：2026-09-13

---

## 一、事实核对（与你提供的报告逐条对照）

| 你的描述 | 核实结果 |
| --- | --- |
| 7 个 commit、28 个文件、+1630 / −102 | ✅ 完全一致（`git diff --stat 5ea21a7..HEAD`） |
| 当前分支 `codex/icloud-sync` | ✅ |
| 1 处未提交的工程签名修改 | ✅ 仅 `project.pbxproj` 一处，Release 配置的 `PROVISIONING_PROFILE_SPECIFIER`：`Weekyii App Store` → `Weekyii App Store CloudKit` |
| V1–V6 迁移路径保留 | ✅ V1–V6 的 `VersionedSchema` 定义**一行未改**，只新增 V7 并在 `WeekyiiMigrationPlan` 追加 V6→V7 阶段 |
| 未新增注册/登录页、未加 App 内同步开关 | ✅ 设置页只是把原来的占位 Toggle 换成只读状态行 |

**编译**：`xcodebuild build` → `** BUILD SUCCEEDED **`

**测试**（`xcodebuild test -only-testing:WeekyiiTests`）：

- 本分支新增的 8 个 iCloud 相关测试 **全部通过**
- `ModelTests` 72/72、`StateMachineTests` 36/36、`NotificationServiceTests` 4/4、`SuspendedTaskLifecycleServiceTests` 5/5、`WeekCalculatorTests` 4/4

> ⚠️ **一个必须澄清的假象**：`TaskPostponeServiceTests` 会以
> `SwiftData/ModelContext.swift:712 Fatal error: Failed to cast model Weekyii.DayModel ... to DayModel`
> 崩溃，导致整个测试进程反复重启、`** TEST FAILED **`。
> 我用基点 `5ea21a7`（`git archive` 导出到 /tmp 单独构建）复现了**完全相同**的崩溃（同样 18 次 fatal）。
> **因此这是既有环境/工具链问题（Xcode 26.3 + iOS 26 模拟器 + SwiftData），不是本分支引入的回归。**
> 但它会污染"测试全绿"这一验收结论 —— 建议在真机或另一 Xcode 版本上确认后再当作基线。

---

## 二、架构判断：方案方向是对的

以下几点是**正确的关键决策**，不建议推翻：

1. **用 SwiftData + CloudKit Private Database 镜像，而不是手写 CloudKit Record 同步。**
   手写方案要重新实现变更追踪、离线队列、关系恢复三件事，这是同步系统里最容易出错的部分。你的设计文档对这一点的论证是对的。
2. **不引入 Weekyii 自有账号。** 依赖 Apple Account + private DB，数据边界干净，没有后端成本，也没有"账号体系与 Apple Account 不一致"的经典问题。
3. **不做同步总开关。** 避免"关闭再打开产生两份数据源"以及随之而来的合并语义，这个取舍正确。
4. **只同步业务实体，设备本地保留通知/主题/开发者设置。** 边界划分清晰。
5. **冲突收敛用确定性规则，而不是"最后写入的设备赢"。** 方向正确。

**但方案里有一个根本张力，它是后面所有高优先级问题的源头：**

> CloudKit 无法强制业务唯一键，而你的 `weekId` / `dayId` 是**由日期确定性推导**出来的
> （`today.weekId`、`today.dayId`）。这意味着两台设备在同一周/同一天各自创建记录时，
> **必然**生成相同的 key 并各自插入。这不是罕见竞态，而是**新设备首次同步的常规路径**。

你选择了"启动时 / 导入后修复"来收敛。这个选择本身没错，但它带来两个后果，需要在设计上正视：

- **"重复"是预期状态，不是异常状态。** 于是 `DataInvariantRepairService` 的合并逻辑是**承重生产代码**，而不是兜底网。它的正确性标准应当按"主路径"要求，而不是按"防御性代码"要求。目前的测试强度还不到这个标准（见第五节）。
- **没有墓碑（tombstone）机制。** 合并是"删掉劣者、把子对象改挂到优者"。删除会同步出去，但**一台离线设备手里的劣者记录会在下次联网时被重新上传**，于是再合并一轮。更麻烦的是：如果那台离线设备在被删记录的子对象上做过编辑，这些编辑会随记录一起消失。

**建议**：把 `weekId`/`dayId` 的创建从"无条件插入"改成**按 key 的幂等 upsert**（先 fetch 同 key、存在则复用），让重复变成**罕见**；把 `DataInvariantRepairService` 降回真正的兜底网。这比继续加固合并逻辑更省事，也更安全。

---

## 三、高优先级问题（建议在 TestFlight 之前处理）

### H1. 备份快照不包含 `_SUPPORT/_EXTERNAL_DATA`，附件与图片会丢

`WeekyiiPersistence.swift:302-306`（`BackupRecoveryService.createSnapshot`）只复制三个文件：

```swift
let candidates = [
    storeURL,
    URL(fileURLWithPath: storeURL.path + "-wal"),
    URL(fileURLWithPath: storeURL.path + "-shm"),
]
```

但 `TaskAttachment.data` 和 `MindStampItem.imageBlob` 都标了 `@Attribute(.externalStorage)`，
**实际二进制落在 `<store>_SUPPORT/_EXTERNAL_DATA/` 目录里，不在 .store 文件内**。

后果：`manifest.json` 的 SHA256 校验会**通过**（它只校验自己复制过的那几个文件），
于是快照显示 `verified=yes`，但恢复后附件全部悬挂、MindStamp 图片全丢。
**这是一个会给出虚假信心的安全网** —— 比没有备份更危险。

**已实测确认**（用纯 Core Data 复现 SwiftData `.externalStorage` 的底层行为
`allowsExternalBinaryDataStorage = true`，插入 4.77 MB 二进制后枚举落盘结构）：

```
payload inserted: 4.77 MB

=== on-disk layout ===
  Weekyii.store-shm                                        [0.03 MB]
  Weekyii.store-wal                                        [0.01 MB]
  .Weekyii_SUPPORT/
    _EXTERNAL_DATA/
      5C24757F-6B77-47D5-A436-B5A1B840FD45                 [4.77 MB]   <-- 真正的数据在这里
  Weekyii.store                                            [0.02 MB]   <-- 备份只复制这个
```

**4.77 MB 的附件，落进 `.store` 的只有 0.02 MB —— 99.6% 的数据在 `_EXTERNAL_DATA` 里。**

并且已确认：全项目 `grep -rn "_SUPPORT|EXTERNAL_DATA|isExcludedFromBackup"` **零命中**
（只有 10 处 `@Attribute(.externalStorage)` 声明）。
也就是说这份数据**没有任何代码碰过它** —— 不被备份、不被哈希、不被枚举。

结论从"推断"升级为"确证"：`createSnapshot` 产出的快照，
其 `manifest.json` 会诚实地报告"我校验通过的那几个文件都完好"，
但用户恢复后会失去**全部**附件与 MindStamp 图片。

### H2. 备份在启动路径上同步执行，且把整个 store 读进内存做哈希

`WeekyiiApp.init()` → `bootstrapPersistentContainer()` → `backupPersistentStoreIfExists()`，
即**每次启动**都在**主线程**上：

- `makeFileEntry`（`WeekyiiPersistence.swift:195-204`）用 `Data(contentsOf:)` **把整个文件读进内存**算 SHA256；
- `verifySnapshot`（:366-380）**再读一遍、再算一遍**。

也就是说每次冷启动要完整读两遍 store 并做两次 SHA256。store 越大越慢，且内存峰值 = 2× store 体积。
在低内存设备或大 store 上，这是**启动卡顿 / 看门狗杀掉**的风险。
另外 `pruneBackups` 保留上限是 **40 份**（:233 `snapshots.prefix(40)`），
每份都是完整拷贝 → 磁盘占用可达 store 的 40 倍，而且这个目录位于 Application Support，
**会进入设备备份**。

建议：改为后台队列 + 流式哈希（`FileHandle` 分块）+ 只在 schema 变更或导入前做快照，而不是每次启动。

### H3. fail-closed 但没有恢复入口；而且校验本身会静默失败

- `validateContainerConsistency`（:186-193）用 `(try? context.fetch(...)) ?? []`。
  如果 fetch 抛错（store 损坏），`weeks` 变成空数组，`presentWeeks.count > 1` 不成立，
  **校验直接通过**，App 带着一个读不出来的 store 继续跑。它要防的失败模式恰好被绕过了。
- 校验真的失败时，App 进入 `PersistenceFailureView`，只给一段文字 + 诊断导出。
  **没有重试、没有"从快照恢复"、没有重置入口。**
- 更讽刺的是：`BackupRecoveryService.restoreSnapshot(named:to:)`（:382-408）**写好了，但全项目没有任何调用点**
  （`grep -rn "restoreSnapshot"` 只命中定义处）。

结论：**你建好了安全网，但没接上。** 用户遇到 fail-closed 时唯一的出路是手动去 Application Support 里掏文件。
建议至少加一个"从最近快照恢复"按钮，并修掉 `try?` 的静默吞错。

### H4. `TaskTypeDefinition` 的确定性 key 没有去重（同一类 bug，漏了一个实体）

`TaskTypeDefinition.idRaw` 是**确定性**的（内置类型用固定字符串，`TaskType.regular.rawValue` 等），
不是随机 UUID。两台设备首次启动都会各自 seed 一遍：
`seedBuiltInTypesIfNeeded`（`TaskTypeDefinition.swift:100-105`）只检查**本地** `existingIds`，
所以两边都会插入，CloudKit 合并后 → **标签选择器里出现重复的内置任务类型**。

而 `mergeDuplicateWeeksAndDays()` **只处理 `WeekModel` 和 `DayModel`**，
对 `TaskTypeDefinition`、`ProjectModel`、`MindStampItem`、`SuspendedTaskItem` 都没有去重。

你的设计文档把"业务键由应用层收敛"写成了通用原则（`SWIFTDATA_MIGRATION_RULES.md` 第 5 条），
但实现只覆盖了两个实体。**这是设计意图与实现范围不一致**，建议要么补齐，要么在文档里明确列出"仅 Week/Day 收敛"。

### H5. 签名与 Entitlements：目前最大的"上线即失败"风险面

`Weekyii.entitlements` 现状：

```xml
<key>aps-environment</key>
<string>development</string>          <!-- ① 硬编码 development -->
<key>com.apple.developer.icloud-container-identifiers</key> ... iCloud.com.fluentdesign.Weekyii
<key>com.apple.developer.icloud-services</key> ... CloudKit
<key>com.apple.developer.ubiquity-kvstore-identifier</key>  <!-- ② 代码里根本没用 -->
<string>$(TeamIdentifierPrefix)com.fluentdesign.Weekyii</string>
<key>com.apple.security.application-groups</key> ... group.com.fluentdesign.Weekyii
```

1. **`aps-environment` 硬编码 `development`。** App Store / TestFlight 构建必须解析成 `production`。
   Xcode 通常会用描述文件里的值覆盖，但这里硬编码的值是**静默推送失败的经典来源**。
   而 CloudKit 的自动同步**依赖静默推送** —— 一旦 APNs 环境不对，表现是"同步很慢 / 只有切到前台才同步"，
   而不是一个明确的签名错误，极难排查。**必须在真实 TestFlight 包上验证。**
2. **缺少 `com.apple.developer.icloud-container-environment`。** 开发构建默认走 Development 环境，
   上架构建必须解析到 Production。正常由描述文件注入，但和 ① 叠加时需要显式确认。
3. **`ubiquity-kvstore-identifier` 是无用声明。** 全项目 `grep -rn "NSUbiquitousKeyValueStore"` → **无任何命中**。
   多余的 entitlement；如果 App ID / 描述文件没带这一项，就是签名不匹配的隐患。建议删掉。
4. **provisioning 变更尚未提交。** 也就是说**已提交的代码树产不出你想要的 Release 包**。
   仓库状态与构建状态不一致，容易在归档时踩坑。

补充：`Info.plist` 加 `UIBackgroundModes: remote-notification` 是正确的、必需的。
`WeekyiiWidget.entitlements` 只有 App Group —— 这也是对的，因为 widget 读的是 App Group 里的快照，不碰 store。

---

## 四、中优先级问题

### M1. 删除重复记录 + `cascade` 规则的数据丢失风险

`mergeDuplicateWeeksAndDays()` 里：

```swift
for day in duplicate.days { day.week = canonical; ... }
modelContext.delete(duplicate)          // WeekModel.days 是 .cascade
```

`WeekModel.days` 是 `deleteRule: .cascade`。删 `duplicate` 时会级联删除它当时的 days。
代码先 `day.week = canonical` 把 days 摘出去，**顺序是对的**，测试也验证了任务不丢。
但这里没有中间 `save()`，重挂父子关系和删除落在同一个事务里；而且 `days` 是
`dayRecords ?? []` 的**计算属性包装**，不是直接的存储属性。
这种组合一旦在真实 CloudKit store 上出现任何时序差异，级联删除就会连任务一起吃掉。

建议：重挂之后显式 `save()` 一次，再删劣者；或者把级联规则改成更保守的 `nullify` + 显式搬运子对象。

### M2. 同步状态把"账号状态"和"最近事件结果"揉进了一个 enum

`CloudSyncState` 同时表达两件事，导致两个问题：

- `refreshAccountStatus()` 只在状态为 `.checking` / 不可用 / 失败时才写 `.available`。
  于是**状态停在 `.synced` 时用户登出了 iCloud，设置页仍然显示"已同步"** —— 乐观且过期。
- `consume()` 对**任何**成功事件都写 `.synced`，对**任何**失败事件都写 `.failed`。
  CloudKit 事件很密集，一次瞬时导出失败就会让 UI 跳成"同步遇到问题"，尽管账号和数据都正常。
  用户会看到状态在 synced / failed 之间闪烁。

建议：拆成 `accountStatus` 和 `lastEventResult` 两个独立状态，显示态由二者推导。

### M3. `importRevision` → `force: true` 的 reconcile 触发过频

`WeekyiiApp.swift:556-561`：每个 CloudKit **导入事件**都触发
`reconcile(trigger: .manualResync, force: true)`，即全量领域修复 + 重排通知 + 刷新 Live Activity。
`AppHealthCoordinator.isReconciling` 只防重入、不防频率。
首次大同步（上千条记录分批导入）时会反复做重活。建议做节流 / 合并（debounce）。

### M4. `MainActor.assumeIsolated` 用在 NotificationCenter 回调里

`CloudSyncMonitor.swift:127-131`：

```swift
) { [weak self] notification in
    MainActor.assumeIsolated { self?.consume(notification) }
}
```

配 `queue: .main` 通常没问题，但 `assumeIsolated` 在当前执行器不是 MainActor 时**会 trap（崩溃）**。
同步事件回调崩溃属于高严重度、低概率。更稳的写法是 `Task { @MainActor in ... }`。

### M5. "数据同步、配置不同步"的不一致

`TaskTypeDefinition`（用户自建标签）走 SwiftData → **会同步**；
但 `UserSettings` 是纯 `UserDefaults` → **完全不同步**（killing time、主题、执行模式、默认项目时长、通知偏好）。
于是第二台设备上：任务和标签都在，但**看的时候是另一套 kill time 和主题**。
`SettingsRecord.defaultTaskTypeIdRaw` 还形成了一个跨边界的指针（设置指向一个同步过来的标签 id）。

设计文档把它列为"设备本地保留"，是自觉的取舍。但请在文档/产品说明里明确写出来，
否则用户会当成 bug 反馈。另：`UserSettings.iCloudSyncEnabled` 已删除，全项目无残留引用 ✅。

### M6. 快照保留 40 份 + 位于 Application Support

见 H2 末尾。磁盘与设备备份体积问题，建议同时把 `Backups/` 目录标记为
`isExcludedFromBackup = true`。

---

## 五、测试与验证缺口（这是我最担心的一节）

现有测试质量不差 —— 但**它们验证的组合，和用户升级时真正会走的组合不是同一个**：

1. **迁移测试没有启用 CloudKit。**
   `test_publishedV6FixtureMigratesToV7` 里 `makeModelContainer(storeURL:)` 走的是
   `storeMode` 默认值 `.localOnly`，配置里是 `cloudKitDatabase: .none`。
   而**生产路径是 `cloudKitDatabase: .private(...)`**。
   **"V6 → V7 迁移 + CloudKit 镜像"这个唯一会真实发生的组合，从未被测试覆盖。**
2. **用的是合成 fixture，不是真实发布过的 store。**
   测试用 `WeekyiiSchemaV6` 嵌套类现造一个 V6 store。
   它能验证映射逻辑，但验证不了最容易炸的东西：真实 TestFlight 构建产出的 store
   （不同的 `Z_METADATA` 哈希、WAL 状态、store 元数据）。而你的设计文档第 60 行自己写的门槛是
   "V6 → V7 使用显式迁移阶段并通过**真实文件存储测试**验证"。
3. **`originalName` + 私有存储属性 + 计算属性 这套写法，恰恰是"合成 fixture 能过、真实 store 会挂"的典型。**
   `days` → `dayRecords`（`originalName: "days"`）等改名靠的是 `@Relationship(originalName:)` 保持持久化名不变。
   技术手段是对的，但**必须有真机 / 真实 store 的升级测试**才敢下结论。
4. **重复合并测试同样是 `.localOnly`**，没覆盖 CloudKit 合并后的真实场景。
5. **缺三类测试**：重复 `TaskTypeDefinition` 的收敛、备份快照的完整性（尤其 external storage）、fail-closed 的恢复路径。

**建议的最小验证集**：用一台装过当前 TestFlight 版本（V6）的真机，
升级到本分支构建，在**登录 iCloud** 的情况下确认：数据完整 → 首同步无重复周/日 → 附件可打开 → 设置页状态正确。

---

## 六、低优先级 / 记录备查

- **`WeekyiiSchemaV2` / `V3` 复用 V4 的模型类**（`WeekyiiPersistence.swift:577-591`、`648-662`）：
  V2 声明 `versionIdentifier 2.0.0`，但 `models` 指向 `WeekyiiSchemaV4.*`；V3 还混入了自己的 `SuspendedTaskItem`。
  这是**既有历史遗留**（本分支未改 V1–V6），以前无所谓；但现在迁移是承重结构，这种不自洽的定义可能误导迁移规划器。建议后续清理或在文档里注明。
- **周级计数用 `max()` 合并**：`canonical.completedTasksCount = max(...)` 等。
  经核实 `updateMetrics(for:)`（`StateMachine.swift:351-355`）会在 `reconcile` 时按合并后的 days **重算**这三个字段，
  所以只是"启动修复后到首次 reconcile 之间"的短暂不一致，**会自动收敛，属低危**。
  但 `DayModel.expiredCount` 的 `max()` **不会**被重算（只在 `expire(day:)` 时写入），语义上值得再想一下。
- **`CloudSyncMonitor` 无法从 `.synced` 回落**，见 M2。
- **验收清单未闭环**：`release-checklist.md` 新增的 "iCloud Sync Gates" 里，
  "Development schema 创建成功 / 双机同账号 smoke / 部署到 production" 都还是未勾选项 ——
  与"尚未完成"部分一致，符合实际。

---

## 七、建议的处理顺序

| 顺序 | 事项 | 理由 |
| --- | --- | --- |
| 1 | 真机验证 V6→V7 迁移（登录 iCloud） | 唯一会真实发生、却完全没测的组合；失败即用户数据受损 |
| 2 | 在真实 TestFlight 包上确认 APNs / CloudKit 环境 | 签名问题会伪装成"同步很慢"，越晚发现越贵 |
| 3 | 修 H1（快照漏 external storage）+ H3（接上恢复入口） | 现在的安全网是"假的安全"，比没有更危险 |
| 4 | H4 补齐 `TaskTypeDefinition` 去重，或收窄文档口径 | 设计意图与实现范围不一致 |
| 5 | 把 week/day 创建改成幂等 upsert，弱化对合并的依赖 | 从根上减少重复，比加固合并更省事 |
| 6 | H2（备份移出主线程 + 流式哈希）、M2、M3、M4 | 性能 / 体验 / 稳定性 |
| 7 | 清理 entitlements（删无用 kvstore）、提交 provisioning 变更 | 让仓库状态与构建状态一致 |

---

## 八、一句话总结

**方案选型是对的，架构骨架立得住；主要问题不在"选错了路"，而在三处收尾没做完 ——**

1. **验证没做到位**：唯一真实会发生的组合（V6 迁移 + CloudKit）没有测；
2. **安全网是假的**：备份漏了 external storage 的二进制，且恢复入口根本没接；
3. **收敛范围不完整**：确定性 key 的去重只覆盖了 Week/Day，标签会重复。

加上签名侧几个"上线才会暴露"的隐患，**目前不建议直接上传 TestFlight**，先把第七节的 1–3 项做掉。

---

## 附录：本次审查的可复现命令

```bash
# 1) 变更规模核对
cd /Users/luobowen/handwrittenfnn/weekyii/.worktrees/icloud-sync
git log --oneline 5ea21a7..HEAD
git diff --stat 5ea21a7..HEAD
git diff -- Weekyii/Weekyii/Weekyii.xcodeproj/project.pbxproj   # 唯一未提交改动

# 2) 编译（derivedDataPath 必须可写；沙箱内跑会因 swift-plugin-server 失败）
cd Weekyii/Weekyii
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/wkdd CODE_SIGNING_ALLOWED=NO build

# 3) 测试（注意 TaskPostponeServiceTests 的既有崩溃会污染结论）
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/wkdd -only-testing:WeekyiiTests CODE_SIGNING_ALLOWED=NO test

# 4) 证明既有崩溃不是本分支引入（基点对照）
mkdir -p /tmp/wkbase && git archive 5ea21a7 | tar -x -C /tmp/wkbase
# 然后对 /tmp/wkbase/Weekyii/Weekyii 跑同一条 test 命令，会看到完全相同的 18 次 fatal

# 5) 确认没有任何代码处理 external storage
grep -rn "_SUPPORT\|EXTERNAL_DATA\|isExcludedFromBackup" Weekyii/Weekyii/
```

### 环境注意事项（重要）

- **在受限沙箱内跑 xcodebuild 会得到假失败**：沙箱阻止 `swift-plugin-server`，
  会喷出大量 `External macro implementation type 'SwiftDataMacros.PersistentModelMacro'
  could not be found ... produced malformed response`。**这不是代码错误**，脱离沙箱即消失。
- `-derivedDataPath` 要指向可写目录，默认的 `~/Library/Developer/Xcode/DerivedData` 会被拦截。
- 本机环境：macOS 15.7.3 / Xcode 26.3 / Swift 6.2.4 / iOS 26 模拟器。
