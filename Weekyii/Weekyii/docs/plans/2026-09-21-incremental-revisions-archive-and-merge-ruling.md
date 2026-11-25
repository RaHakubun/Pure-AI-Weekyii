# Weekyii Local-First iCloud 主计划

# 增量修订 1 / 2 / 3 原文归档与最终合并裁决

> **归档说明（Codex 补记，2026-09-21）**
>
> 本文件是增量修订 1 / 2 / 3 的**原文归档**。此前这三份增量的正文只存在于对话中，
> 仓库与 `.workbuddy-ai/memory` 里都只有 Codex 自己写的**核对摘要**（且增量 2 连摘要都没有），
> 导致主计划的「增量是否已并入」无法核实。本文件落仓后，该核对有了可审计的原文来源。
>
> 适用文件：
>
> `docs/plans/2026-09-21-local-first-paid-icloud-sync-execution-plan.md`
>
> 这不是新的第四份增量。
>
> 本文件的用途是：
>
> 1. 补回 Codex 当前缺失的增量修订 1 / 2 / 3 原始条款；
> 2. 明确哪些条款后来已经被产品事实或 Review 覆盖；
> 3. 给出主计划的唯一合并优先级。
>
> 覆盖清单见主计划文首「增量修订覆盖清单（已闭合）」与文末附录。

---

# 一、合并优先级

发生冲突时严格按：

1. 当前 Repo 真实代码
2. 后续独立 Review 已明确裁决
3. 增量修订 3
4. 增量修订 2
5. 增量修订 1
6. 原始 2026-09-21 主计划

不要按：

“哪个文档写得更长”

或：

“哪个更像最终稿”

判断。

---

# 二、增量修订 1 原文

## A. 修正 §47：`CloudSyncMonitor.swift` 不允许孤立删除

当前 Repo 中 `CloudSyncMonitor` 仍是一个具有完整编译依赖图的类型，不能在 Phase I 单独删除文件。

当前直接源码依赖至少包括：

* `App/WeekyiiApp.swift`
* `App/ContentView.swift`
* `Resources/SettingsView.swift`
* `Features/Today/TodayView.swift`
* `Tests/ModelTests.swift`

此外：

* `Weekyii.xcodeproj/project.pbxproj`

仍然含：

* `PBXFileReference`
* `PBXBuildFile`
* Group children entry
* Sources build phase membership

所以 §47 改为以下原子清理步骤。

### Phase I-0：CloudSyncMonitor retirement

必须按顺序执行：

1. 确认 `WeekyiiApp.swift` 已完全迁移到 `CloudSyncCoordinator`：

   * 删除 `CloudSyncMonitor` state/property；
   * 删除 `start()`；
   * 删除 `refreshAccountStatus()`；
   * 删除 `importRevision`；
   * 删除 launch account/status/userRecordID resolution；
   * 删除 `markContainerLoaded()`；
   * 删除旧 identityConfirmed 生命周期。

2. 确认 `ContentView.swift`：

   * 不再读取 `CloudSyncMonitor`；
   * 不再调用 `syncedWritesAllowed(...)`；
   * 新状态 UI 只使用 `CloudSyncCoordinator.status`。

3. 确认 `TodayView.swift`：

   * 删除 `@Environment(CloudSyncMonitor.self)`；
   * 删除 `syncedWritesAllowed(...)`；
   * Today 业务不再接收任何 Cloud 权限。

4. 确认 `SettingsView.swift` 已全部迁移到新 Coordinator。

   当前必须显式替换/删除的旧接口包括：

   * `cloudSyncMonitor.state`
   * `cloudSyncMonitor.lastFailureDetail`
   * `cloudSyncMonitor.settlement(...)`
   * `cloudSyncMonitor.identityConfirmed`
   * `cloudSyncMonitor.currentUserRecordID`

5. 重写 `ModelTests.swift` 中所有 `CloudSyncMonitor` 测试。

   特别包括 2026-09-20 新增的诊断行为：

   * `inFlightSetupEventIdentifiers`
   * `lastFailureDetail`

   这些测试不是简单删除。

   若对应产品需求在新架构仍成立：

   * “保留最近失败原因”
   * “多个并发操作不能让 UI 错误显示成功”

   则应迁移为：

   `CloudSyncCoordinator / CKSyncEngineTransport`

   的新测试。

   旧 `NSPersistentCloudKitContainer.Event` 实现细节测试删除。

6. 全仓确认：

   `CloudSyncMonitor`

   只剩：

   `Services/CloudSyncMonitor.swift`

   和 Xcode project reference。

7. 删除：

   `Services/CloudSyncMonitor.swift`

8. 同批修改：

   `Weekyii.xcodeproj/project.pbxproj`

   删除四处登记：

   * PBXBuildFile
   * PBXFileReference
   * Group children entry
   * Sources build phase entry

9. Build。

10. 全仓：

`grep CloudSyncMonitor`

只能命中历史 docs，不得命中 active source / active tests / pbxproj。

### 重要

`CloudSyncMonitor.swift` 的删除必须发生在：

Phase F/H 已完成替代实现以后。

不得提前在 Phase B 删除整个类型，因为当前 Settings/UI/account diagnostics 仍依赖它。

Phase B 只负责解除它对业务写权限和 persistence 生命周期的控制。

---

## B. §2.12 确认成立，不再标为待验证

当前 `SettingsView.prepareStoreTransfer()`：

开启同步时构造：

`targetMode = .cloudDetached`

随后：

`persistentStoreURL(for: .cloudDetached)`

得到本机：

`Weekyii.store`

再通过：

`makeModelContainer(... .cloudDetached)`

以 `.none` 打开这个本地文件并调用：

`storeIsEmpty(...)`

因此当前代码判断的是：

> 本机磁盘上旧 Weekyii.store 当前是否有数据

并不是：

> 当前 Apple ID 的 CloudKit Private Database 是否存在 Weekyii 数据。

所以主计划 §2.12 改为：

**已由当前源码确认的现存缺陷。**

新的 explicit CloudKit 架构必须真正 fetch 当前账号的：

`WeekyiiSyncZoneV1`

后才能判断：

* remote empty
* remote non-empty

不得复用本机 store emptiness 作为远端真相。

---

## C. §2.13 确认成立，不再标为待验证

当前 Repo 无实际 StoreKit 源码实现。

`premiumThemeUnlocked` 当前：

* 是 `UserSettings` 中普通 `@Published Bool`
* 存入 `UserDefaults`
* 同步给 Widget shared defaults
* 被 `WeekyiiDataArchiveService.SettingsRecord` 导出
* archive import 时重新写回

因此：

`premiumThemeUnlocked`

明确不是可信购买 entitlement。

主计划原有结论保持：

**不得复用它控制 iCloud。**

必须继续新增独立：

`CloudSyncEntitlementProviding`

未来由 StoreKit 2 verified transactions 提供生产 entitlement。

---

## D. 修正 Phase A：Archive DTO ≠ Sync Snapshot DTO

原计划 Phase A：

> 把 DataArchiveService 当前 Record DTO 提取出来作为 WeekyiiBusinessSnapshot。

需要收窄。

当前 archive v1 是为：

**整包导出 / 整包恢复**

设计。

它并不等于新的 incremental sync aggregate。

当前：

### TaskRecord

包含：

* Task
* `steps`
* `attachments`

且 AttachmentRecord 内直接包含：

`Data?`

### SuspendedTaskRecord

同样包含：

* task
* steps
* attachments + Data

但新同步设计要求：

* Task 是一个 Cloud aggregate
* TaskAttachment 是独立 aggregate
* attachment binary 使用 CKAsset

如果直接复用 archive DTO：

同一附件会同时存在：

1. Task JSON payload
2. Attachment CKRecord / CKAsset

这是禁止的。

### Phase A 新定义

需要两层。

#### Archive compatibility DTO

保持 archive v1 JSON layout。

当前：

`TaskRecord.attachments`

继续存在。

不能改变旧 archive format v1。

#### Normalized Business Snapshot

新增供：

* merge
* hash
* Cloud sync
* legacy store consolidation

使用的 normalized representation。

至少包括：

* weeks
* days
* tasks
* attachments
* projects
* mindStamps
* suspendedTasks
* taskTypes
* habits
* habitDayRecords

TaskSnapshot：

* Task scalar data
* steps
* attachment IDs
* 不含 attachment binary

SuspendedTaskSnapshot：

同样不含附件二进制。

AttachmentSnapshot：

独立包含：

* id
* owner
* fileName
* fileType
* createdAt
* blob/data

MindStamp：

也必须明确区分 metadata/hash 与 image binary。

CloudRecordCodec 上传时：

imageBlob 使用 CKAsset。

---

## E. DataArchive adapter

`WeekyiiDataArchiveService`

继续使用旧 archive DTO。

新增明确 adapter：

```
ArchivePayload
    ↕
WeekyiiBusinessSnapshot
```

导出旧 archive：

Normalized attachments

重新 nest 回：

TaskRecord / SuspendedTaskRecord。

读取旧 archive：

nested attachments

normalize 成独立 AttachmentSnapshot。

要求：

* 老归档兼容
* 新同步结构独立
* formatVersion 仍为 1

---

## F. Snapshot identity 必须在 Phase A 锁定

Phase A 必须建立：

`SyncEntityKey`

或等价 identity abstraction。

最低映射：

* week → `weekId`
* day → `dayId`
* task → UUID
* attachment → UUID
* project → UUID
* mindStamp → UUID
* suspendedTask → UUID
* taskType → `idRaw`
* habit → UUID
* habitDayRecord → UUID

TaskStep：

没有独立 SyncEntityKey。

属于父 Task/SuspendedTask aggregate。

---

## G. Phase A merge 必须按 normalized aggregate 做

不能对 archive JSON 整包 merge。

Merge 针对：

`SyncEntityKey`

规则：

* 不同 ID → union
* 相同 ID → local wins

关系必须在 merge 后重建。

尤其：

* Day → Week
* Task → Day
* Task → Project
* Task → Habit
* Attachment → Task / SuspendedTask
* HabitDayRecord → Habit

不能只拼 Codable 数组。

---

## H. Phase E 增加 apply 顺序约束

显式 sync 有实体依赖关系。

Codex 不得随机顺序向 SwiftData apply remote records。

### Upsert 推荐顺序

1. TaskTypeDefinition
2. Week
3. Day
4. Project
5. Habit
6. SuspendedTask
7. Task
8. HabitDayRecord
9. Attachment
10. MindStamp

可以两遍：

第一遍：

create/update entities。

第二遍：

resolve relationships。

### Delete

删除不能机械反转 upsert 顺序。

必须先形成一致：

`ReconciliationPlan`

再集中 apply。

保证：

parent delete 不会让 child 随后被重新插入。

---

## I. Phase E 增加“同步时用户继续编辑”的二次校验

硬要求：

1. 生成 sync baseline snapshot/hash。

2. 网络 fetch。

3. 得到 remote changes。

4. 真正 apply 每个 remote entity 前重新读取 current local hash。

5. 如果：

   `currentLocalHash != hashAtSyncStart`

   则该 entity 在等待网络时被本机用户修改。

6. 转为：

   local-changed

7. 按 local-first 处理。

禁止：

抓一次 snapshot → 等网络 → 无条件覆盖 ModelContext。

---

## J. Phase C 增加旧 `cloudSyncEnabled` 升级语义

旧安装可能：

`cloudSyncEnabled == true`

来自旧 SwiftData mirroring。

不能直接迁移：

`cloudSyncRequested == true`

否则升级后未经重新确认就进入新 custom-zone sync。

### 新安装

`cloudSyncRequested = false`

### 老安装

如果只存在旧：

`cloudSyncEnabled`

则：

`cloudSyncRequested = false`

并写一次 migration marker，例如：

`weekyii.cloudSyncPreferenceMigratedV2`

Settings 可显示一次非阻断提示：

> iCloud 同步方式已更新。如需继续多设备同步，请重新开启 iCloud 同步。

不得自动创建：

`WeekyiiSyncZoneV1`

直到用户主动开启。

---

## K. V8 与 legacy CD_* 是两个问题

V8 是否冻结：

取决于 V8 是否已经进入需要向后兼容的已发布安装。

但是本计划已经决定：

sync metadata 不进 SwiftData schema。

所以本轮没有主动改 V8 的必要。

legacy CloudKit `CD_*` 是否需要 bridge：

取决于：

是否存在真实用户的重要数据只在旧 automatic CloudKit mirroring 中。

这是另一件事。

---

## L. Phase I 原始硬停点

原增量 1 当时要求：

在执行：

* legacy CloudKit cleanup
* 永久放弃 CD_* 读取能力
* 删除 migration bridge 可能依赖的代码

之前必须确认产品历史。

若没有答案：

```
PRODUCT_DECISION_REQUIRED
```

### 当前状态

**这一条已经被后续产品事实覆盖，不得作为现行停点。**

用户后来已经明确：

> 旧 automatic CloudKit mirroring 只有内部 TestFlight / 开发测试，没有真实外部用户依赖。

所以 Phase I 不再等待这个 PRODUCT_DECISION。

---

## M. 其余原则不变

* 唯一 canonical `Weekyii.store`
* production SwiftData `.none`
* custom CloudKit zone
* local-first
* entitlement 独立
* sync opt-in
* bounded app retry
* manual Sync Now
* account switch pause
* quota 不阻断 local
* KVS 退出
* Habit watermark 修复
* Phase 顺序

---

## N. Phase A 原始执行边界

当时要求：

1. normalized `WeekyiiBusinessSnapshot`
2. SyncEntityKey
3. Attachment 与 Task/SuspendedTask 解耦
4. TaskStep 内嵌
5. archive v1 layout 不变
6. Archive ↔ Snapshot adapter
7. deterministic merge
8. relationship reconstruction
9. canonical encoding/hash
10. tests
11. 不改 persistence / CloudKit runtime
12. 不删 CloudSyncMonitor

这 12 条应保留为 Phase A 的历史验收边界。

---

# 三、增量修订 2 原文

## O. SwiftData Schema 与 Cloud Sync Protocol 完全解耦

`WeekyiiSchemaV8 / V9 / V10...`

和：

`WeekyiiSyncZoneV1`

不是同一套版本系统。

禁止建立：

```
SwiftData V9
    =>
WeekyiiSyncZoneV2
```

这种机械映射。

### SwiftData schema version

只负责：

* 本机 SwiftData 数据结构
* SwiftData migration

例如：

`WeekyiiSchemaV8 → WeekyiiSchemaV9`

---

### Cloud zone version

`WeekyiiSyncZoneV1`

表示：

> 第一代 Weekyii 显式 Cloud Sync Protocol 的 CloudKit 数据域。

只要同步身份规则和整体协议仍可向后兼容：

继续使用同一个 zone。

---

### Aggregate payload version

每一种同步 aggregate 单独维护 payload version。

例如：

```
task payloadVersion = 2
project payloadVersion = 1
habit payloadVersion = 3
```

`WYEntityV1` 至少包含：

```
kind
payloadVersion
payload
payloadHash
```

不要只用一个全局 SwiftData schemaVersion 解释所有 Cloud payload。

---

### 普通模型字段升级

如果 SwiftData 新增需要同步的字段：

1. 正常建立新的 SwiftData VersionedSchema / migration。
2. 更新对应 BusinessSnapshot DTO。
3. 对应 aggregate `payloadVersion += 1`。
4. decoder 兼容旧 payload。
5. Cloud zone 不变。
6. CKRecord type 不变。

---

### 本地专用字段

如果字段不需要跨设备：

只修改 SwiftData。

不得因为本地字段变化修改 Cloud payload。

---

### 大型同步语义变化

只有出现以下情况才考虑：

`WeekyiiSyncZoneV2`

* record identity 规则整体改变；
* 现有 payload 无法安全向后读取；
* aggregate 边界发生全局重构；
* 旧、新同步协议无法安全共存；
* 原地 migration 风险明显高于新 zone migration。

即使出现这些情况：

也必须先写 migration plan。

不能因为 SwiftData 开 V9/V10 就新建 zone。

---

## P. Legacy automatic CloudKit 产品裁决

已经确认：

> 旧 SwiftData automatic CloudKit mirroring 仅用于内部 TestFlight / 开发测试，没有真实外部用户依赖旧 `CD_*` 云端数据。

因此：

* 不建设生产级 `CD_* → WeekyiiSyncZoneV1` migration bridge；
* 不把旧 CD_* records 当作正式数据来源；
* 不为兼容内部测试数据延续 automatic mirroring；
* 保留旧 CloudKit 数据即可，本次不主动删除；
* 新架构上线后，以当前设备 canonical `Weekyii.store` 为旧测试安装的数据来源。

Phase I 不再因 legacy CD_* migration bridge 等待产品裁决。

---

# 四、增量修订 3 原文

## Q. 修正 Phase I-0 的 Xcode project 清理数量

当前 `CloudSyncMonitor.swift` 在 pbxproj 有 4 个登记点：

1. PBXBuildFile
2. PBXFileReference
3. Group children entry
4. Sources build phase entry

删除时必须四处同批清理。

---

## R. 更正 Attachment UUID churn 的影响范围

以下说法：

> 每次 postpone 都会重建 attachment UUID

不准确。

`TaskPostponeService.execute(...)`

真正后移已有 Task 时直接修改：

`task.day`

没有调用 attachment copy。

普通 postpone：

Task UUID 与 Attachment UUID 保持。

实际 churn 主要发生于：

* `TaskMutationService.replaceTaskResources`
* Task update
* SuspendedTask update
* 只改 steps 却连带 replace attachments
* 只改 attachments 却连带 replace steps
* SuspendedTaskItem → TaskItem
* PendingViewModel 相应 copy 路径
* 其它 resource copy/edit 路径

---

## S. Attachment 身份正式裁决

`TaskAttachment.id: UUID`

作为：

**附件唯一逻辑身份。**

不得把：

`SHA256(data)`

作为 SyncEntityKey。

最终：

```
SyncEntityKey(
    kind: .attachment,
    id: attachment.id.uuidString
)
```

SHA-256：

只表示内容身份。

---

## T. AttachmentSnapshot 结构

Normalized snapshot 至少包含：

```
id
owner
fileName
fileType
createdAt
blobSHA256 / data
```

owner：

* task(UUID)
* suspendedTask(UUID)

Cloud metadata 包含业务元信息和 blob hash。

二进制走：

CKAsset。

---

## U. Blob hash 仅用于变化检测和上传优化

附件有：

### Metadata hash

由：

* id
* owner
* fileName
* fileType
* createdAt
* blobSHA256

计算。

### Blob hash

只对 data：

SHA-256。

只改 fileName：

metadata 变，blob 不变。

替换内容：

blob 变。

相同内容的两个独立附件：

blob hash 可相同。

UUID 必须不同。

不得业务合并。

---

## V. Phase A 增加 A0：Resource Identity Stabilization

执行顺序改为：

```
Phase A0
Resource Identity Stabilization

↓

Phase A1
Normalized BusinessSnapshot

↓

Phase A2
Merge / canonical hash
```

再进入 Phase B。

A0 不涉及 CloudKit。

---

## W. TaskAttachment 稳定身份

修改至少：

* Models/TaskAttachment.swift
* Services/TaskPostponeService.swift
* Features/Pending/PendingViewModel.swift
* Features/Extensions/ExtensionsViewModel.swift

检查所有：

`TaskAttachment(...)`

copy path。

### initializer

允许传：

* id
* createdAt

不增加 persisted property。

不需要 V9。

---

## X. 正常编辑不要 delete-all + recreate attachments

正常 Task update 应：

按 attachment UUID reconcile。

1. existingByID
2. incoming existing ID → 更新原 row
3. incoming new ID → 插入
4. missing ID → delete
5. 重建 relationship

这样：

改 title 不重建附件。

改 step 不触碰附件。

---

## Y. SuspendedTask → Task 是 resource move

`assignTask(...)`

语义是：

> 同一个 suspended task 被正式分配到某天。

附件应保留 UUID。

优先：

re-parent 原 SwiftData TaskAttachment row。

在删除 SuspendedTask 前：

* detach suspended relation
* attach new Task
* 再删旧 parent

如果 SwiftData relationship 不可靠才允许 replacement-row fallback，但也必须保留 logical UUID。

### 当前实现裁决

后续 A0 已经成功实现：

**同 row re-parent。**

因此主计划直接描述最终方案即可，无需保留 fallback 为默认路径。

---

## Z. 真正 duplicate 时必须新 UUID

如果未来“复制任务”产生独立附件：

必须：

`UUID()`

不能因为 bytes 一样就沿用旧 ID。

API 应区分：

* move/re-parent preserving identity
* duplicate with new identity

禁止含糊的 copy 语义。

---

## AA. TaskStep hash churn

当前旧代码多处：

`normalizedStepCopies(from:)`

重建：

`TaskStep(...)`

但没有保存：

`createdAt`

导致每次重建 timestamp 漂移。

受影响至少：

* TaskPostponeService.swift
* PendingViewModel.swift
* TodayViewModel.swift
* DayDetailView.swift

而 DataArchiveService.makeStep 已正确保留 createdAt。

---

## AB. Phase A0 稳定 TaskStep

TaskStep 暂无 UUID。

继续作为：

父 Task / SuspendedTask aggregate 的内嵌数据。

但复制现有 step 必须保留：

`createdAt`

新增 Step 才产生新 Date。

不要求本轮新增 UUID / V9。

---

## AC. 避免无意义重建 Step

最低要求：

1. normalized copy 保留 createdAt。
2. 只改 attachment 时不重建 steps。
3. 只改 title/description/type，steps 未变化时避免无意义重建。
4. 必要时使用 value equality 判断是否 replace。

以后如果需要：

* Step 独立多端冲突
* 单条 Step identity
* 多端同时修改同 Step

再考虑给 TaskStep 增加 UUID + 新 SwiftData schema。

---

## AD. Task aggregate hash

Task canonical hash 包含：

* Task scalar fields
* ordered Steps
* attachment ID list

不直接包含：

attachment binary Data。

附件内容变化：

Attachment aggregate hash 改。

Task 只有 membership/order 改变时改。

---

## AE. SuspendedTask 同一规则

SuspendedTask hash：

* scalar fields
* ordered Steps
* attachment IDs

owner：

`suspendedTask(X) → task(Y)`

应表现为：

Attachment owner update。

不是：

old attachment delete + unrelated new attachment insert。

---

## AF. SnapshotRepository 唯一性校验

一个 snapshot 内：

每个 SyncEntityKey 只能有一个 entity。

遇到：

* duplicate Task UUID
* duplicate Attachment UUID
* duplicate Habit UUID
* duplicate dayId
* duplicate weekId
* duplicate taskType idRaw

不得 dictionary 静默覆盖。

必须产出明确 diagnostic/error。

### 后续 Review 补充

最终同步入口应使用：

`requireCleanSnapshot(...)`

诊断非空时拒绝生成 syncable snapshot。

`load(...)`

可以继续提供 best-effort diagnostic snapshot。

---

## AG. Phase A 最终内容

### A0

Resource Identity Stabilization：

* attachment UUID stability
* attachment createdAt stability
* Suspended → Task identity
* Step createdAt stability
* 不跨类型无意义重建
* tests

### A1

Normalized BusinessSnapshot：

* archive DTO 与 normalized DTO 分离
* AttachmentSnapshot 独立
* Task/SuspendedTask 只持 attachment IDs
* TaskStep 内嵌
* SyncEntityKey
* identity uniqueness validation

### A2

Merge / Hash：

* canonical encoding
* entity hash
* blob hash
* deterministic local-wins merge
* relationship reconstruction
* Archive ↔ Normalized adapter
* archive v1 compatibility

完成后停止。

---

## AH. Phase A0 测试要求

至少覆盖：

### Attachment

* 编辑 title → UUID 不变
* 编辑 steps → attachment UUID 不变
* 编辑 filename → UUID 不变
* 替换内容 → UUID 不变、blob hash 改变
* 删除 → UUID 消失
* 新增 → 新 UUID
* Suspended → normal Task → UUID 不变
* 普通 postpone → Task/Attachment UUID 均不变

### Step

* 只改 Task title → createdAt 不变
* 只改 attachment → Step createdAt 不变
* reorder → createdAt 尽可能保留
* new Step → 新 createdAt

### Snapshot

同内容两个附件：

* blob hash 相同
* UUID 不同
* SyncEntityKey 不同
* merge 后两个都存在

---

## AI. Legacy automatic CloudKit 最终裁决

产品已确认：

旧 automatic mirroring：

仅内部 TestFlight / 开发测试。

因此：

* 不开发正式 migration bridge
* 不主动删除旧 CD_* 数据
* 本机 Weekyii.store 作为升级数据来源
* 新显式同步只认 WeekyiiSyncZoneV1
* Phase I 可清理旧 automatic mirroring 代码

---

## AJ. 最终身份原则

统一：

### Business identity

UUID / dayId / weekId / idRaw。

### Content identity

SHA-256。

### Persistence identity

SwiftData row/object。

Cloud Sync：

`SyncEntityKey`

使用 Business identity。

CKAsset 是否重传：

使用 Content identity。

绝不能拿 SHA-256 代替 UUID。

---

# 五、增量 3 之后已经完成的独立 Review 覆盖项

这些不是增量修订 4，但必须写入最终主计划，因为它们已经通过独立 Review 裁决。

## 1. Merge 不使用 hash 决胜

保留：

`mergePreferringLocal`

SHA-256 只判断内容是否不同。

不决定权威。

未来 Phase E 通过：

baseline + resolved winner upload + confirmed baseline advancement

实现静止状态下最终收敛。

---

## 2. MindStamp binary

MindStamp 的 imageBlob 与 Attachment binary 同样是 blob。

metadata hash 使用：

* image byte count
* image SHA-256

CloudKit：

image → CKAsset。

不得直接进入普通 Cloud record JSON payload。

---

## 3. Whole snapshot encode 不等于 Cloud payload encode

`WeekyiiSnapshotCodec.encode(...)`

允许完整本地 snapshot 包含 raw Data，用于：

* archive
* local serialization
* test

但是 Phase D：

不得直接把这个编码结果作为 CKRecord payload。

必须使用：

`CloudRecordCodec`

将：

metadata → payload

blob → CKAsset。

---

## 4. SyncEntityKey.description 不等于 CKRecordName

`SyncEntityKey.description`

只是：

Weekyii logical key serialization。

Phase D 必须有单独：

`CKRecordNameCodec`

或等价编码器。

不要把当前可读字符串格式与 CloudKit physical record ID 永久绑死。

---

## 5. Habit watermark 前移

`generatedThroughDayId`

目前仍存在 normalized HabitSnapshot。

但：

不得进入新的 Cloud protocol。

Habit watermark/idempotency 修复从原 Phase I 尾部前移。

硬要求：

**在 Phase D CloudRecordCodec 真正启用之前完成。**

最迟 Phase D encoder 必须明确 omit：

`generatedThroughDayId`

直到 Habit 修复完成。

---

## 6. KVS

当前代码仍在真实使用：

`NSUbiquitousKeyValueStore`

这不是 Phase A 未完成。

正式归属：

**Phase B local-first persistence cleanup。**

Phase B 删除：

* KVS read
* KVS write
* synchronize
* external-change observer
* kvstore entitlement

Kill Time defaults 回到设备本地 UserDefaults。

---

# 六、关于主计划当前“增量未核实”标记的处理

现在 Codex 已经拿到原文。

因此下一轮可以：

1. 逐条把本文件内容与现有 09-21 主计划核对；
2. 缺失条款补入；
3. 已被后续覆盖的旧条款不要重新激活；
4. 相同语义已经完整存在的条款，可以保留现有更清晰的措辞，不要求逐字复制；
5. 但是必须能建立一份 coverage checklist：

   Revision 1 A-N
   Revision 2 O-P
   Revision 3 Q-AJ
   Post-review amendments

每项标：

* PRESENT
* MERGED_EQUIVALENT
* SUPERSEDED_BY <条款>
* MISSING

最终不得再有：

UNKNOWN。

---

# 七、此次只做计划文档闭合

这轮不要重新修改 A0-A2 业务代码。

除非文档核对发现：

当前代码与已经通过 Review 的最终条款实际矛盾。

否则：

A0-A2 继续视为：

CODE_APPROVED。

完成计划合并后：

Phase A 正式 CLOSED。

下一阶段：

Phase B。
