# iCloud 同步审查修复说明（2026-09-13）

复审基线：`codex/icloud-sync` 的 `c8b3c30` 及其未提交 Release provisioning 修改。

## 已处理

- H1：恢复点现在递归包含 `.Weekyii_SUPPORT/_EXTERNAL_DATA`（并兼容 `<store>_SUPPORT` 命名），Manifest 使用相对路径记录和校验所有外部二进制文件；恢复时同步还原附件与 MindStamp 图片。
- H2/M6：SHA256 改为 1 MiB 分块流式计算；V7 启动前恢复点每个 Schema 版本只创建一次，不再每次冷启动复制；导入前恢复点仍保留；数量上限从 40 降到 8；`Backups` 标记为不参与系统设备备份。
- H3：一致性检查不再用 `try?` 吞掉读取错误；失败页新增“重试打开数据库”和“从最近有效恢复点还原”；恢复会跳过校验失败的新快照。
- H4：修复器按固定 `idRaw` 合并重复的内置 `TaskTypeDefinition`，并恢复内置显示属性。
- 周/日幂等创建：新增 `WeekDataStore`，按 `weekId` / `dayId` fetch-or-insert。Today、Week、Pending、项目扩展、延期、暂存任务分配和演示数据入口均使用该入口。两台完全离线同时创建仍由启动/导入后的修复器收敛。
- M1：把子对象改挂到 canonical 周/日后，先显式清空 duplicate 的关系集合，再删除 cascade 父对象，降低级联误删风险。
- M2：`CloudSyncMonitor` 将账号状态与最近同步事件拆开；显示态始终优先反映当前账号可用性，并监听 `CKAccountChanged`。
- M3：成功的 CloudKit import 采用 1 秒 debounce 后才增加 `importRevision`，一批导入只触发一次领域修复。
- M4：移除 `MainActor.assumeIsolated`，改用 NotificationCenter 异步通知序列并在 MainActor Task 中消费。
- M5：设计与 runbook 已明确：业务实体和用户任务类型同步；通知、kill time、执行模式、主题、默认项目时长等 `UserSettings` 保持设备本地。

## H5 产物核对

使用 Release + generic iOS destination 成功生成本地 Archive。归档主 App 的实际 codesign entitlements：

- `aps-environment = production`
- `com.apple.developer.icloud-container-identifiers = iCloud.com.fluentdesign.Weekyii`
- `com.apple.developer.icloud-services = CloudKit`
- `com.apple.security.application-groups = group.com.fluentdesign.Weekyii`
- `get-task-allow = false`

嵌入的 `Weekyii App Store CloudKit` profile 同时授权 Production/Development CloudKit 环境。Widget 归档产物只包含自己的 application/team 标识、App Group、beta entitlement，不直接声明 CloudKit。`ubiquity-kvstore-identifier` 保留：它由 Xcode iCloud capability 生成且被当前 distribution profile 授权，不构成签名不匹配。

## 自动化验证

- 新增外部存储快照与完整恢复测试。
- 新增备份目录排除系统备份测试。
- 新增每 Schema 仅一次 preflight 快照测试。
- 新增跳过损坏快照、恢复最近有效快照测试。
- 新增 Cloud 状态优先级与 import debounce 测试。
- 新增周/日幂等 upsert 测试。
- 新增内置任务类型冲突收敛测试。
- `ModelTests + StateMachineTests + SuspendedTaskLifecycleServiceTests`：121/121 通过。
- `TaskPostponeServiceTests` 的 SwiftData model cast trap 仍存在；原审查已在基线 `5ea21a7` 独立复现，因此不归因于本次修改。
- Release Archive：成功。

## 仍需在发布流程完成

- 在 CloudKit Development 环境成功初始化 Schema，并部署到 Production；此前模拟器账号因 iCloud 容量已满返回 quota exceeded。
- 上传后由另一个具有可用 iCloud 空间的 Apple Account 通过 TestFlight 覆盖安装，验证双设备新增、编辑、删除、离线恢复及附件同步。
- 本轮没有上传、没有推送、没有合并到 `online-chatgpt-develop`。

## 第二轮复审整改

- N1：冷启动判断 V7 preflight 恢复点是否存在时，不再调用会急切校验全部快照的 `listSnapshots`。新增按恢复点名称先筛选、再只校验候选目录的查询入口，避免启动时读取并哈希无关快照及其附件。
- 新增回归测试，注入校验器并断言只有名称匹配 `preflight-v7` 的目录会进入完整性校验。
- N2–N6 未纳入本次最小整改；其中 N2、N3、N5、N6 可作为后续增强，N4 已由复审方实测确认当前关系层级正确。
