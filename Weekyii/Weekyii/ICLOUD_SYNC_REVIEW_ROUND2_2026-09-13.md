# iCloud 同步修复说明 —— 复审报告（第二轮）

复审对象：`codex/icloud-sync` 的 `74f4e09 fix: address iCloud sync review findings`
被复审文档：`docs/ICLOUD_SYNC_REVIEW_RESPONSE_2026-09-13.md`
复审方式：**只读**。未改动被审仓库（`git status` 干净，HEAD 仍为 `74f4e09`）。
所有"已验证"结论均附命令或实测输出；临时探针均在 `/tmp` 副本中进行，已清理。

---

## 一、结论速览

**这份修复说明是可信的。** 逐条核对后：

- 11 项声明（H1–H5、M1–M6、幂等 upsert、自动化验证）**全部为真**，无夸大。
- 其中 **H5 和"121/121 通过"我独立复现了**，不是只读代码。
- 我额外做了一次"反向验证"（怀疑 M1 的 `duplicate.days = []` 会把已合并的 day 变成孤儿），
  **实测证明该担心不成立** —— M1 是正确的。
- 但修复本身引入了 **1 个新的性能问题**和 **2 个次要问题**，见第三节。

---

## 二、逐条核对结果

| 声明 | 核对方式 | 结果 |
| --- | --- | --- |
| H1 恢复点递归包含 `_EXTERNAL_DATA`，Manifest 用相对路径校验，恢复时还原附件 | 读码 + 读新增测试 | ✅ 真 |
| H2 SHA256 改 1 MiB 分块流式 | 读码（`FileHandle` + `SHA256.update`） | ✅ 真 |
| H2 每 Schema 只建一次 preflight 恢复点 | 读码 | ⚠️ 真，但实现是硬编码字符串（见 N5） |
| H2 数量上限 40 → 8 | 读码（`snapshots.prefix(8)`） | ✅ 真 |
| H2/M6 `Backups` 不参与系统备份 | 读码（`isExcludedFromBackup = true`） | ✅ 真 |
| H3 不再用 `try?` 吞读取错误 | 读码（`try context.fetch`） | ✅ 真 |
| H3 失败页新增重试 + 从恢复点还原 | 读码（`PersistenceFailureView` 新增 `onRetry`/`onRestore`） | ✅ 真 |
| H3 恢复会跳过校验失败的新快照 | 读码（`restoreLatestValidSnapshot` → `first(where: \.isValid)`） | ✅ 真 |
| H4 按固定 `idRaw` 合并重复内置 `TaskTypeDefinition` 并恢复显示属性 | 读码 + 读新增测试 | ✅ 真 |
| 周/日幂等创建，7 类入口均改用 `WeekDataStore` | 全量 grep `modelContext.insert` / `makeWeek(` | ✅ 真 |
| M1 改挂后先清空 duplicate 关系集合再删除 | 读码 + **自建探针实测** | ✅ 真，且无孤儿化 |
| M2 账号状态与同步事件拆分，监听 `CKAccountChanged` | 读码 | ✅ 真 |
| M3 成功 import 1 秒 debounce | 读码 | ✅ 真 |
| M4 移除 `MainActor.assumeIsolated` | 读码（改用 `notifications(named:)` 异步序列） | ✅ 真 |
| M5 设计与 runbook 明确同步边界 | 读 diff | ✅ 真 |
| H5 归档产物 `aps-environment = production` 等 | **独立重建 Release Archive + `codesign -d`** | ✅ 真 |
| Widget 归档不含 CloudKit | 同上，读 appex entitlements | ✅ 真 |
| `ubiquity-kvstore-identifier` 不构成签名不匹配 | 解出本机 profile 的 entitlements | ✅ 真（原判断已修正） |
| `ModelTests + StateMachineTests + SuspendedTaskLifecycleServiceTests` = 121/121 | **实跑** | ✅ 真（79 + 37 + 5 = 121，0 失败） |
| `TaskPostponeServiceTests` trap 属既有问题 | 我在基线 `5ea21a7` 已独立复现过 | ✅ 真 |
| Release Archive 成功 | **实跑 `ARCHIVE SUCCEEDED`** | ✅ 真 |

### H5 独立复现的原始输出（关键部分）

本机存在 profile `d2304475-…`（Name: `Weekyii App Store CloudKit`，Team `W8UNGRPC5N`，
有效期至 2027-09-03）与 `iPhone Distribution: jingyi luo (W8UNGRPC5N)` 证书，因此可复现。

profile 自身授权：

```
com.apple.developer.icloud-container-environment = [Production, Development]
aps-environment                                  = production
com.apple.developer.icloud-container-identifiers = [iCloud.com.fluentdesign.Weekyii]
com.apple.developer.ubiquity-kvstore-identifier  = W8UNGRPC5N.*
```

重建归档后，主 App 实际签名 entitlements：

```xml
application-identifier                 = W8UNGRPC5N.com.fluentdesign.Weekyii
aps-environment                        = production          ← 关键
beta-reports-active                    = true
com.apple.developer.icloud-container-identifiers = [iCloud.com.fluentdesign.Weekyii]
com.apple.developer.icloud-services    = [CloudKit]
com.apple.developer.team-identifier    = W8UNGRPC5N
com.apple.developer.ubiquity-kvstore-identifier = W8UNGRPC5N.com.fluentdesign.Weekyii
com.apple.security.application-groups  = [group.com.fluentdesign.Weekyii]
get-task-allow                         = false
```

**所以原审查 H5-① 的担心（`.entitlements` 里硬编码 `development` 会带到上架包）已被证伪**：
描述文件的值覆盖了它。H5-③（kvstore 无用声明）也确认**不会**造成签名不匹配 —— 描述文件确实授权了它。
保留它是可以接受的；若要清理，属于纯粹的整洁性问题，不紧急。

Widget appex 的 entitlements 只有 `application-identifier`、`beta-reports-active`、
`team-identifier`、App Group、`get-task-allow=false`，**不声明 CloudKit** —— 与说明一致。

---

## 三、修复引入的新问题

### N1（主要）启动路径现在会哈希**所有**快照的**所有**文件

`backupPersistentStoreIfExists`（`WeekyiiPersistence.swift:155-164`）每次冷启动执行：

```swift
let alreadyProtected = BackupRecoveryService.listSnapshots(storeURL: storeURL)
    .contains { $0.isValid && $0.folderName.contains(preflightReason) }
guard !alreadyProtected else { return }
```

而 `listSnapshots`（:364-392）对**每一个**快照都急切计算：

```swift
isValid: verifySnapshot(folder: folder)      // ← 每个快照都做
```

`verifySnapshot`（:394+）又会**逐文件重新读取并 SHA256**。由于 H1 修复后快照已包含
`_EXTERNAL_DATA` 的全部附件，这里哈希的是**完整附件负载**。

也就是说：**每次冷启动 = 读取并哈希（附件总量 × 快照数）**，且发生在
`WeekyiiApp.init()` 的**主线程**上。

实测（本机 M 系列，warm cache，硬件 SHA256）：

```
snapshots on disk  : 8
total bytes to hash: 80.0 MB
run: hashed 80.0 MB in 41 ms
```

**校准**：这不是灾难，但方向错了 —— 原本 H2 抱怨的是"每次启动读 store 两遍"，
现在变成了"每次启动读全部快照（含附件）"。80 MB 约 41 ms；若用户有 100 MB 附件，
则 8 × 100 MB = 800 MB，冷 cache 真机上可能到数百 ms 乃至秒级主线程阻塞。
轻量用户无感，重度附件用户会明显感到启动变慢，且有看门狗风险。

**修法很简单**：这个判断只需要知道"有没有一个名字含 `preflight-v7` 的快照"，
不需要校验全部 8 个。先按 `folderName` 过滤，只对命中的那一个做 `verifySnapshot`：

```swift
let candidate = BackupRecoveryService.listSnapshots(storeURL: storeURL)
    .first { $0.folderName.contains(preflightReason) && $0.isValid }
```

（更彻底的做法：`listSnapshots` 增加 `verify: Bool = false` 参数，
或把校验结果写进 manifest 旁的 `.verified` 标记，避免重复哈希。）

### N2（次要）`canRestore` 写在 SwiftUI `body` 里

`WeekyiiApp.swift` 的 `.failed` 分支：

```swift
PersistenceFailureView(
    message: message,
    canRestore: BackupRecoveryService.listSnapshots(
        storeURL: WeekyiiPersistence.persistentStoreURL()
    ).contains(where: \.isValid),
    ...
)
```

这是在 `body` 求值期间做全量哈希。失败页里有 `@State private var copied`，
用户点"导出诊断信息"就会翻转它 → 视图重算 → **再哈希一遍全部快照**。
建议改为在 `restoreLatestValidSnapshot` 调用时判断，或把结果缓存进 `@State`。

### N3（次要）磁盘占用其实变大了

快照数从 40 降到 8，但**每个快照现在包含全部附件**。对附件总量 50 MB 的用户：
8 × 50 MB ≈ 400 MB（之前是 40 × 仅 store，通常几 MB）。
`isExcludedFromBackup` 解决的是"进设备备份"的体积，不解决设备本地磁盘。
建议给恢复点设总量上限（例如总字节数上限，而不只是个数），
或对 `_EXTERNAL_DATA` 做内容寻址去重。

### N4（验证缺口，低）重复合并测试没有断言"层级仍正确"

`test_dataInvariantRepair_mergesDuplicateCloudWeeksAndDaysWithoutDroppingTasks` 断言了：

- `matchingWeeks.count == 1`
- `matchingDays.count == 1`
- `Set(matchingDays[0].tasks.map(\.title)) == ["来自 iPhone", "来自 iPad"]`

但**没有断言 `matchingDays[0].week` 指向幸存的 canonical 周**。
`FetchDescriptor<DayModel>()` 是按实体取，不经过关系 —— 所以即使 day 被
`duplicate.days = []` 变成孤儿（`week == nil`），这个测试**依然会通过**。

**我实测确认当前行为是正确的**（在 `/tmp` 副本里加了一个探针测试，断言
`day.week != nil` 且 `week.days.contains(day)`，**通过**），
但建议把这两条断言补进正式测试，把行为锁住 —— 毕竟 M1 那行 `duplicate.days = []`
就紧挨着它。

### N5（次要）`preflight-v7` 是硬编码字符串

说明里写"每个 Schema 版本只创建一次"，实现是 `let preflightReason = "preflight-v7"`。
实际语义是"**字面量 `preflight-v7` 只创建一次**"。将来升到 V8 时，
若忘记改这个字符串，就**不会**为新 schema 建 preflight 恢复点。
建议从 `currentSchema.version` 派生（如 `"preflight-v\(major)"`）。

### N6（次要，沿用既有模式）恢复不是原子操作

`restoreSnapshot` 先删除 store、`-wal`、`-shm` 与 support 目录，再从快照逐文件拷回。
中途任何一步失败（磁盘满、权限），用户当前的库已被删、且只拷回一部分。
快照本身完好，重试即可恢复，所以严重度不高；
但"先拷到临时目录再整体替换"会更稳。

---

## 四、仍待发布流程完成的事项（与说明一致，我认可）

说明里"仍需在发布流程完成"的三条我无法在此环境验证，且它们确实无法在本地完成：

1. **CloudKit Development Schema 初始化 → 部署 Production。** 说明提到模拟器账号
   因 iCloud 容量已满返回 quota exceeded。这是真实阻塞，需要换账号或清理空间。
2. **双真机同账号 TestFlight 覆盖安装验证**（新增/编辑/删除/离线恢复/附件同步）。
   这是我在第一轮标为"最高优先级"的那一项 —— **仍未完成**，依然是最大风险点。
   注意：我第一轮指出的"V6→V7 迁移 + CloudKit 镜像"组合，
   在**本轮新增的测试里仍然没有被覆盖**（新增测试都走 `.localOnly` / in-memory）。
   幂等 upsert 降低了重复概率，但没有消除对真实 CloudKit 升级路径的验证需求。
3. 未上传、未推送、未合并 —— 与 `git log` 一致（HEAD `74f4e09`，未推送）。

---

## 五、建议

**可以继续推进，但先修 N1。** 它是这次修复唯一的实质性副作用，改动量很小。

优先级：

1. **N1** —— 让 preflight 检查只校验命中的那一个快照（几行代码）。
2. **N4** —— 补两条层级断言，锁住 M1 的正确行为。
3. **N2 / N5** —— 顺手清理。
4. **N3** —— 加一个恢复点总字节上限。
5. 继续推进"真实双真机 CloudKit 升级验证"——这仍是唯一会真实发生、却尚未被任何测试覆盖的组合。

---

## 六、对第一轮审查的自我更正

本着同样标准，我也要更正自己第一轮的两个判断：

- **H5-①（`aps-environment = development` 会带到上架包）** —— **我错了。**
  描述文件覆盖了它，归档产物实际是 `production`。已在上面给出证据。
- **H5-③（`ubiquity-kvstore-identifier` 可能导致签名不匹配）** —— **我错了**，
  描述文件确实授权了 `W8UNGRPC5N.*`。保留它无害。
- **M1（cascade 删除可能吃掉子对象）** —— 方向对（确实值得加固），
  但我对"`duplicate.days = []` 可能孤儿化"的后续怀疑**经实测不成立**。

第一轮中经本轮复核仍然成立的高优先级项：**H1（已修）、H3（已修）、
以及"真实 CloudKit 升级路径未被测试覆盖"（未修）。**
