# Weekyii iCloud 同步发布与运维手册（CKSyncEngine 架构）

> 2026-10-31 重写。旧版描述的是 SwiftData 自动镜像（`NSPersistentCloudKitContainer`），已不适用：
> 当前 SwiftData 一律 `cloudKitDatabase: .none`，同步由 `CloudSyncCoordinator` + `CloudSyncReconciler` + `CKSyncEngineTransport` 自行完成。

## 1. 固定配置

| 项 | 值 |
|---|---|
| Team ID | `W8UNGRPC5N` |
| App Bundle ID | `com.fluentdesign.Weekyii`（Widget：`com.fluentdesign.Weekyii.widget`，不连 CloudKit） |
| App Group | `group.com.fluentdesign.Weekyii` |
| iCloud Container | `iCloud.com.fluentdesign.Weekyii` |
| 数据库 | Private Database |
| 自定义 Zone | `WeekyiiSyncZoneV1` |
| Record Type | `WYEntityV1`（所有业务实体共用一种记录类型） |
| Zone 订阅 | `WeekyiiSyncZoneV1-subscription-v1`（CKSyncEngine 也会自行管理推送） |
| 后台模式 | `remote-notification`（Info.plist） |
| 会员门槛 | iCloud 同步是 VIP 功能；过期后状态为 `.locked`，本地数据不受影响 |

### `WYEntityV1` 字段（Production 必须与此完全一致）

| 字段 | CloudKit 类型 | 说明 |
|---|---|---|
| `kind` | String | 实体种类（week/day/task/suspendedTask/attachment/project/mindStamp/taskType/habit/habitDayRecord） |
| `payloadVersion` | Int(64) | 每种实体的载荷版本；本机不认识的版本会被“隔离”而不是报错 |
| `payload` | Bytes | JSON 载荷 |
| `payloadHash` | String | 载荷哈希，用于判断是否变化 |
| `blob` | Asset | 附件 / 心绪印章二进制（可空） |
| `blobRole` | String | 二进制用途（可空） |
| `blobFileName` | String | 原文件名（可空） |
| `blobContentType` | String | MIME（可空） |

记录名 `recordName` 由 `CKRecordNameCodec.recordName(for:)` 从 `kind + businessId` 推导。当前代码**不使用 CKQuery**（第五轮起 `recordsInWeekyiiZone()` 改用 `recordZoneChanges`），所以 Production **不需要**任何 Queryable / Sortable 索引；`recordName` 的 Queryable 索引有无都不影响。

## 2. CloudKit Console：Development → Production 部署

1. 打开 <https://icloud.developer.apple.com> → CloudKit Database → 选择 `iCloud.com.fluentdesign.Weekyii`。
2. 切到 **Development** 环境 → Schema → Record Types，确认存在 `WYEntityV1` 且字段与上表一致。
   - 若字段缺失：用 Debug 构建（已登录 iCloud 的模拟器或真机）开启同步，新建一个**带图片附件**的任务和一个心绪印章，让每个字段至少被写入一次（Development 环境会按首次写入自动建字段）。
   - 若某字段类型错误（例如 `payloadVersion` 被建成 String）：在 Development 里 Reset Environment 后重新写入；**Production 字段一旦部署不能改类型**。
3. Development 的 Zones 中应能看到 `WeekyiiSyncZoneV1`（Zone 不需要部署，由客户端在 Production 首次运行时创建）。
4. 点击 **Deploy Schema Changes…**，核对差异只包含 `WYEntityV1` 及其 8 个字段（以及可能的系统索引），确认部署。
5. 切到 **Production** → Schema 再次确认字段与类型。
6. Entitlements：仓库里 `aps-environment` 写的是 `development`；App Store / TestFlight 归档时 Xcode 会根据 Distribution provisioning profile 改写为 `production`。归档后在 Organizer → Distribute 之前，或 `codesign -d --entitlements :- Weekyii.app` 检查 `aps-environment = production`、`com.apple.developer.icloud-container-environment` 为 Production（若有该键）。
7. 在 Apple Developer → Identifiers 确认 `com.fluentdesign.Weekyii` 勾选了 iCloud（CloudKit，Container 为上面的值）与 Push Notifications；改动过 capability 时重新生成 Development 与 App Store profiles。

> 部署之后的新增字段同样要先在 Development 写入、测试，再增量部署。不要删除或改类型已部署的字段；载荷结构变化通过提高 `payloadVersion` 实现，旧版本客户端会隔离新记录而非崩溃或删除。

## 3. 架构速览（排障用）

- `CloudSyncCoordinator`（@MainActor）：开关、会员与账号判定、首次启用决策（上传本机 / 使用本机 / 使用 iCloud / 合并 / 取消）、账号切换决策、重试与失败锁存。
- `CloudSyncReconciler`：每轮从传输层取增量 → 与每实体基线（`entityBaselines`）三方比较 → 生成目标快照写入 SwiftData → 上传差异 → 处理 `serverRecordChanged`（读最新服务器版本后至多重发一次，本机优先）→ 原子提交元数据。
- `CKSyncEngineTransport`：包装 `CKSyncEngine`；收到的服务器变更先写入**持久收件箱**（`pendingRemoteChanges`，在元数据文件里），对账成功后按序号确认。
- 设备本地同步状态：`Application Support/Weekyii/CloudSyncState/<账号哈希>/metadata.json`。删除它只会让下次同步重新做一次全量比对，不会删除业务数据。
- 第五轮新增：
  - **隔离（quarantine）**：本机解不开的记录（新版本 App 写入、损坏）记入 `quarantinedRecords`，双向都不处理，也不会被删除；升级 App（解码器签名变化）后自动解除并重新全量拉取。
  - **Zone 丢失**：用户在“设置 → Apple ID → iCloud → 管理存储”删除 Weekyii 数据，或 Zone 不存在时，本机同步状态被重置，下一轮重新进入首次启用决策，不会把“云端已空”当成“全部删除”。
  - **替换本地数据前自动关闭同步**：归档导入、恢复点恢复、回滚备份前，先关闭 iCloud 同步并重置所有账号的本机同步状态；重新开启时会重新询问以哪份数据为准。

## 4. 状态与排障

| 界面状态 | 含义 | 处理 |
|---|---|---|
| 未登录 iCloud / 账号不可用 | 系统无可用账号或受限 | 系统设置登录；本地功能不受影响 |
| 首次启用待选择（横幅“选择”） | 开启同步后需决定数据来源 | 点横幅或设置页按钮完成选择 |
| 账号已变更 | 换了 Apple ID | 选择使用新账号云端数据或本机数据（本机覆盖云端前有二次确认） |
| 会员已过期（横幅“续订”） | `.locked` | 续订后自动恢复 |
| 空间不足 | iCloud 存储满 | 清理 iCloud 空间后自动重试 |
| 同步已暂停 | 连续失败后锁存 | 设置页“立即同步”；仍失败再看日志 |

排障顺序：

1. 先在设置页导出 Weekyii 归档（不要卸载 App、不要删数据库、不要在 Console 重置 Production）。
2. 看设置页“上次失败”文案与设备日志（Console.app 过滤 `Weekyii` / `CloudKit` / `CKSyncEngine`）。
3. 若长期异常：设置页 → iCloud → **重置本机同步状态**（不删除任何数据；会关闭同步，重新开启时重新比对并询问）。
4. 仍异常：CloudKit Console → Production → Records（Zone 选 `WeekyiiSyncZoneV1`），按 recordName 查看对应记录的 `payloadVersion` 与 `payloadHash`。

## 5. 双设备验收（每次发布前）

见 `docs/handoff/ICLOUD_ROUND5_HANDOFF.md` 的“手动验收矩阵”。基础项：

- iPhone 新建 / 修改 / 删除任务，iPad 最终一致；反向再测。
- 含图片/文件附件的任务在另一端能打开。
- 一端离线编辑，联网后自动补传。
- 两端离线同时编辑同一任务：联网后两端一致，且本机先联网的一端不被旧版本回退。
- 从上一 TestFlight 构建覆盖安装，本地数据完整。
