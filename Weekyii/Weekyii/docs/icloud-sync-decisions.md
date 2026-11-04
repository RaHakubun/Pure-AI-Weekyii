# iCloud 同步：设计约束与已定决策

> 2026-11-01。这份文档记录两类东西：**不能再破的约束**，和**已经拍板、不要反复重开的决策**。
> 事实以代码为准；这里只写代码里看不出来的理由。

## 1. 约束：同一个 Zone 必须容忍未知 `payloadVersion` 至少一个大版本

`CloudRecordCodec` 为每种 kind 固定了 `payloadVersion`（当前全为 1），解码时强制相等。这意味着**新版本 App 写入的记录，旧版本一定解不开**。所以：

- **不允许**把「解不开一条记录」升级成「整轮同步失败」。一旦这么做，任何一次 v2 上线都会让所有未升级设备停摆，且用户无法自救。
- 隔离（quarantine）的语义是固定的：**不覆盖、不删除、跳过、记账**。记录留在服务器上，等能解开它的构建来处理。
- 隔离发生在两个入口，两者都必须保持这个语义：
  - `CloudKitInfrastructureManager.inspect()` —— 全量检查（首次启用决策、换账号）
  - `CKSyncEngineTransport.handleEvent(.fetchedRecordZoneChanges)` —— 增量拉取
- **任何会删除或半应用 Zone 的路径，必须先证明 Zone 完全可读**。唯一判定点是 `CloudSyncCoordinator.isZoneFullyReadable(_:)`（即 `undecodableRecordNames.isEmpty`）。当前覆盖 5 处：`initialDecision(for:)`、`prepareAccountResolutionContext`、换账号的 `.useLocal` / `.useCloud` / `.merge`。
  - 理由：`resetCustomZone()` 删整个 Zone；`businessSnapshot(from: inspection.records)` 静默忽略解不开的记录。两者都会销毁新版本写入的数据。
- 新增 v2 的发布顺序：**先让能隔离的版本（当前这个）上线并被使用 → 再发 v2**。反向顺序会让旧设备停在“需要更新版本”，虽然不丢数据，但用户看到的是同步被挡住。
- 隔离记录对用户不可见是刻意的：它不是用户能处理的东西，提示只会制造焦虑。诊断串里有 `initial-decision-remote-newer-data`，排障时用 Console 日志看。

### 什么时候该重新评估

- 引入 `WeekyiiSyncZoneV2`（zone 级迁移）时：混版本共存规则要重写。
- 隔离记录数量在真实用户上持续增长时：说明 v2 发布顺序错了，或者某个 kind 的版本判定写错了。

## 2. 决策：不做后台同步（原 M5）

**结论：不补 `BGAppRefreshTask`。**

现状事实：`appDelegate.attach(coordinator:)` 在 `ContentView.task` 里调用，所以后台冷启动唤醒时 router 没有 handler，`CloudRemoteNotificationRouter.receive` 记一笔 `pendingBeforeAttachment` 并立刻回调 `.noData`；等用户真正打开 App 才补跑一次 cycle。

用户可感知的后果：**App 没打开时，另一台设备的修改不会反映到 Widget / 通知 / Live Activity 上**。打开 App 后立即同步（`scenePhase == .active` 会触发 `handle(.sceneActive)`）。

不补的理由：

1. `BGAppRefreshTask` 不是实时的。iOS 决定何时跑，可能几分钟也可能几小时，低电量模式会推迟。它解决不了“Widget 立刻变新”。
2. 它是一条**只能在真机上验证**的路径，而现在真机验证一项都还没开始。加一条不可测的路径只会让上线更难。
3. 打开 App 就同步这条主路径已经覆盖了绝大多数使用场景。

### 什么时候该重新评估

- 真机验证确认静默推送在后台能唤起 App（`didReceiveRemoteNotification` 有执行窗口）时 —— 那就不需要 BGTask，只需要把 handler 提前到 `AppDelegate` 里 attach。
- 用户反馈“Widget 长期是旧的”成为主要投诉时。

## 3. 决策：不提示旧版同步用户（原 L4）

**结论：不提示。** 旧版 `cloudSyncEnabled = true` 的用户升级后同步静默变关闭，只写迁移标记，不迁移值、也不弹窗。

理由：

1. 默认关闭是第五轮就定下的决策（同步是 VIP 功能，且需要用户显式选择数据来源）。迁移成“开启”会把用户直接推进首次启用决策，而那个决策是破坏性的。
2. 老用户重新开启的路径很短（设置页一个开关），代价远小于“升级后被弹窗要求选择以哪份数据为准”。

### 什么时候该重新评估

- 如果数据显示有相当比例的旧用户从未重新开启同步，说明这不是“路径短”，而是“没人知道”。

## 4. 记录：并发冲突只保留本机版本

`CloudSyncReconciler` 在双端同时修改同一实体时保留本机版本，远端那次编辑被丢弃。`CloudSyncReconciliationReport.conflicts` 记录数量，现在会通过 `CloudSyncDiagnosticsSnapshot.lastConflictCount` 显示在设置页（“上次同步的冲突 N 处（已保留本机版本）”）。

**这是有损的**，但换成“保留远端”同样有损，且更难解释。真正的解法是逐字段合并或保留冲突副本，属于后续版本的事。
