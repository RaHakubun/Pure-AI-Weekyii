# Weekyii iCloud 同步设计

## 目标

Weekyii 在用户设备已登录 iCloud 时自动同步同一用户的任务数据。首版覆盖 iPhone 与 iPad，保留未来 macOS 客户端复用同一数据层和 CloudKit Container 的能力，不引入 Weekyii 自有账号、服务器或共享协作。

## 方案选择

采用 SwiftData 本地存储与 CloudKit Private Database 镜像。App 继续以本地数据库为读写入口，CloudKit 在后台负责同一 Apple Account 下的设备同步；离线时所有核心操作仍可用，网络恢复后自动补传。

不采用自定义 CloudKit Record 同步，因为它会重复实现变更追踪、离线队列和关系恢复。首版也不提供总开关，避免关闭与重新开启时产生两份数据源以及合并语义。

CloudKit Container 固定为 `iCloud.com.fluentdesign.Weekyii`。业务数据使用 Private Database，任何用户数据都不进入 Public Database。

## 数据边界

同步以下 SwiftData 实体：

- `WeekModel`
- `DayModel`
- `TaskItem`
- `TaskStep`
- `TaskAttachment`
- `ProjectModel`
- `MindStampItem`
- `SuspendedTaskItem`
- `TaskTypeDefinition`

设备本地保留：通知授权、通知排程、主题与界面偏好、开发者设置、演示数据设置。`AppState` 中可由业务数据推导的计数和刷新 revision 不作为云端事实来源。

## Schema 演进

V1–V6 是已发布历史，禁止修改其持久化结构或版本号。新增 V7 作为 CloudKit-ready 基线。V7 的业务实体保持现有名称，从而迁移现有本地数据，同时满足 CloudKit 约束：

- 不使用唯一约束，UUID、`weekId` 和 `dayId` 仍作为稳定业务标识，由应用层检查重复。
- 所有持久化属性具有默认值或为 optional。
- 所有关系可选并具有 inverse；不使用 CloudKit 不支持的 deny 删除规则。
- `TaskStep` 与 `TaskAttachment` 增加可选父引用，以支持普通任务和暂存任务的双向关系。
- V6 → V7 使用显式迁移阶段并通过真实文件存储测试验证。

未来修改只能新增 V8、V9 等版本。生产 CloudKit Schema 中已部署的 Record Type 和字段不删除、不改类型；需要重命名或重构时使用新增字段与渐进迁移。

## 数据流与冲突收敛

View 和 ViewModel 只读写 SwiftData，不直接依赖 CloudKit。`WeekyiiPersistence` 负责构造本地测试容器或生产 CloudKit 容器；`CloudSyncMonitor` 只负责呈现 iCloud 账号和最近同步事件状态。

远端数据进入本地存储后，现有 `AppHealthCoordinator` 执行领域不变量修复。重点约束包括：当前周唯一、单日 Focus 任务不超过一个、任务顺序稳定。冲突采用确定性规则收敛，不能依赖界面恰好最后写入的一台设备。

当两台离线设备同时创建同一 `weekId` / `dayId` 时，修复器会合并重复周与日期，将双方任务迁入同一日期后再规范 Focus 和顺序。随机 UUID 标识的普通任务不做语义去重，以免误删用户分别创建但文本相同的任务。

## 失败策略

- 未登录 iCloud、账号受限或网络不可用：继续使用本地副本，设置页显示明确状态。
- 本地数据库迁移失败：沿用当前 fail-closed 行为，停止写入并保留备份诊断。
- CloudKit 上传失败：不删除本地数据，等待系统重试。
- 首次升级：迁移前继续建立本地 SQLite 快照，并保留手动导出能力。

## 验证门槛

- V1–V6 全历史迁移到 V7。
- V6 中包含所有实体和关系的数据升级后数量与字段值不变。
- V7 Schema 无唯一约束，关系满足 CloudKit 兼容检查。
- iPhone/iPad 真机同账号双向新增、编辑、删除、离线恢复测试。
- 并发修改后领域不变量仍成立。
- Debug 使用 CloudKit development，TestFlight 前将 Schema 部署到 production。
