# Weekyii iCloud Sync Release Runbook

## 固定配置

- Team ID: `W8UNGRPC5N`
- App Bundle ID: `com.fluentdesign.Weekyii`
- Widget Bundle ID: `com.fluentdesign.Weekyii.widget`
- App Group: `group.com.fluentdesign.Weekyii`
- iCloud Container: `iCloud.com.fluentdesign.Weekyii`
- Database: CloudKit Private Database

主 App 同步 SwiftData 业务实体；Widget 继续从 App Group 快照读取，不直接连接 CloudKit。通知授权、主题和开发者偏好保持设备本地。

## 首次启用顺序

1. 在 Apple Developer → Certificates, Identifiers & Profiles → Identifiers 中创建或确认 `iCloud.com.fluentdesign.Weekyii`。
2. 编辑 `com.fluentdesign.Weekyii` App ID，启用 iCloud（CloudKit），选择上述 Container，并启用 Push Notifications。
3. 重新生成 Development 与 App Store Distribution provisioning profiles。旧的 `Weekyii App Store` profile 不包含新 entitlement，不能继续用于本次归档。
4. 使用当前 Team 正规签名的 Development 构建，在已登录 iCloud 的 iOS Simulator 上加入启动参数 `-initializeCloudKitSchema` 并启动一次。该入口只存在于 Debug 构建，使用独立临时本地库，不接触用户正式数据；成功日志为 `Weekyii: CloudKit development schema initialized.`。
5. 在 CloudKit Console 选择 development 环境，确认 Weekyii 的 Record Types 已由 SwiftData 创建，然后移除启动参数。整个初始化过程不需要向 `Sunday` 或其他真机有线安装。
6. 在 CloudKit Console 将 development Schema 部署到 production。
7. 将 `CURRENT_PROJECT_VERSION` 增加到尚未上传过的值，使用包含新 entitlement 的 App Store profile 归档并上传 TestFlight。
8. 仅通过 TestFlight 覆盖安装到 iPhone 与 iPad，使用同一个 iCloud 账号完成双向、离线和旧数据保留测试。

## 双设备验收

- iPhone 新建任务，iPad 自动出现；反向再测一次。
- 一端修改标题、完成步骤、删除任务，另一端最终一致。
- 含图片/文件附件的任务可在另一端打开。
- 一端断网新增和编辑，联网后能自动补传。
- 两端离线同时为同一天创建任务，联网后双方任务都保留，且最多一个 Focus。
- 从上一 TestFlight 构建覆盖安装，既有本地周、日、任务、项目和附件仍存在；不卸载 App。

## 状态与排障

- “请先在系统设置中登录 iCloud”：设备没有可用 iCloud 账号，本地功能仍可使用。
- “正在同步…”：SwiftData 正在导入或导出 CloudKit 变更。
- “已同步”：最近一次镜像事件成功；这不是跨设备逐字段校验结果。
- “同步遇到问题”：保留本地数据，系统会继续重试；先检查账号、网络、Container entitlement 和 production Schema。

应用启动时会先收敛 CloudKit 可能留下的重复周/日期与竞争的“当前周”状态，再执行一致性校验。来自不同设备的任务会合并保留；可恢复的同步冲突不应阻止应用启动。

不要通过卸载 App、删除本地数据库或重建生产 Container 处理同步问题。先导出 Weekyii 归档与启动备份，再查看设备日志和 CloudKit Console。

## 后续 Schema 变更

每次新增数据字段都创建新的 SwiftData 版本与迁移阶段，先部署 development Schema，完成迁移和双设备测试后再增量部署 production。生产字段不得删除或改类型；重命名使用新增字段与渐进迁移。
