# Weekyii 1.2 (5) — TestFlight candidate

- Date: 2026-11-03 (Asia/Taipei).
- Branch: `notion-claude/feat-in-app-purchase`; source HEAD: `b379c08`（「feat(theme): 新增指环王付费主题 —— 至尊戒·黑金」）。
- 上一版 TestFlight：1.2 (4)（2026-10-25 01:24 上传，含 `a051142` 启动崩溃修复）。
- 版本变更：App + Widget `CURRENT_PROJECT_VERSION 4 → 5`（Debug / Release / Beta 三套配置），`MARKETING_VERSION` 保持 1.2；测试 Bundle 版本不动（1.0 / 5）。
- 构建号依据：1.2 已用掉 build 1–4（1: 10-22；2: 10-24 22:55；3: 10-24 22:55；4: 10-25 01:24），本版取下一个未用过的 5。曾考虑换营销版本 1.3，按账号主体决定仍留在 1.2。

## Scope（相对 1.2 (4)）

- 主题：魔戒重做为「西界红皮书」v3（道具感图标、羊皮纸/皮面材质、蜡封、丝带书签、卡片四面墨框、任务行账本线、扩展页书签瓦片）；新增「猫猫」v2（午睡橘猫）与「指环王」（至尊戒·黑金）两个 VIP 主题；蓝图主题退役，旧选择归琥珀。
- 设置：主题区重分类、双语补齐、设置页主题底色修正。
- iCloud 同步：第五轮（传输层逐条隔离、Zone 丢失不锁存、导入前暂停同步、习惯任务确定性 ID、`apply` 回滚、N1 收件箱确认）+ 第六轮（合并路径不再删除本版本读不懂的记录、换账号路径收口、解码签名 `decoderSignature`）。
- 同步实现细节：Zone 枚举由 `CKQuery` 改为 zone-changes 拉取，不再依赖生产 schema 里的 `recordName` 可查询索引。
- 通知：新增 `NotificationPresentationDelegate`，前台通知呈现。
- 其他：KillTimeSlider / TaskRowView / WeekCard / StatusBadge 视觉与交互修正。

## Data safety

- SwiftData / migration impact: **none**（`Models/`、`WeekyiiPersistence.swift` 自 1.2 (4) 基线 `a051142` 起无改动）。
- CloudKit impact: record type `WYEntityV1`、zone `WeekyiiSyncZoneV1`、payload version 均未变，**不需要部署生产 schema**；查询方式改为 zone-changes 后反而移除了对 `recordName` 索引的依赖。
- Entitlement / App Group / CloudKit container：未变。
- 加密实现：仅 CryptoKit 的 SHA256（确定性 ID、附件完整性），无自定义加密；出口合规沿用「不属于上述任意一种算法」，本轮已复核新增的 `import CryptoKit` 仍属哈希用途。

## Verification

- Full tests（iPhone 17 Pro / iOS 26.2）：**554 单元 + 23 UI 全过，0 失败 0 跳过**，`TEST SUCCEEDED`；`/tmp/weekyii-release-20261103-full-pro.xcresult`。
- 同一套用例在 iPhone 17 Pro Max 上跑：23 UI 中 1 例失败（`testWeekTopologyTaskNodeShowsTaskInspectorNotForgotten`，2 条断言），单跑可稳定复现；换 iPhone 17 Pro 即通过。
  - 定性：**既有缺陷，非本版引入**。`Features/Week/WeekTopologyView.swift` 自 2026-10-21 `acce859` 起未改动，`Spacing+Weekyii` / `Typography+Weekyii` 自 1.2 (4) 基线 `a051142` 起未改动，本版没有触碰这段布局。
  - 现象：宽屏上聚焦某一天后，任务层落在 220pt 画布的可见区域之外，任务卡不进入无障碍树；窄屏（iPhone 17 Pro）可正常显示。
  - 处置：记录为已知问题，不阻断本次 TestFlight；修复属于产品改动，需单独立项（`focus()` 的 `taskClearEffectiveScale` 与 220pt 画布高度在宽屏下的关系）。
- Archive signature / entitlement verification: 通过（详见下方 Distribution）
- Real-device in-place upgrade: 未做（需账号主体真机覆盖安装 1.2 (4) → 1.3 (1)）
- iCloud two-device regression: 未做（需两台同 Apple Account 设备）

## Known issues / 前置条件

- ASC 必须已存在 4 个内购商品（`vip.monthly` / `.quarterly` / `.yearly` 含 14 天试用 / `.lifetime` ¥198）且付费协议已签，否则 VIP 页与沙盒购买异常。本机无法读取 ASC，需账号主体确认。
- 1.2 (4) 的启动崩溃修复只在模拟器 + 反汇编层面验证过；iOS 27 真机启动仍未由我复核。

## Distribution

- Archive: `/tmp/weekyii-release-20261103-1.2-5.xcarchive`（`** ARCHIVE SUCCEEDED **`，日志 `/tmp/weekyii-release-20261103-archive.log`）。
- Archive signature / entitlement verification: 通过。App 与 Widget 均 `1.2 (5)`；`application-identifier = W8UNGRPC5N.com.fluentdesign.Weekyii`、`aps-environment = production`、CloudKit container、App Group 正确、`get-task-allow = false`、`beta-reports-active = true`。
- IPA: `/tmp/weekyii-release-20261103-ipa/Weekyii.ipa`（导出成功，`** EXPORT SUCCEEDED **`，IPA 内 App/Widget 均 `1.2 (5)`，签名校验通过）。
- **上传被阻断**：`xcodebuild -exportArchive`（destination = upload）报 `Failed to Use Accounts`。原因已定位：Xcode 本机已无已登录的 Apple ID —— `~/Library/Preferences/com.apple.dt.Xcode.plist` 的 `DVTDeveloperAccountManagerAppleIDLists → IDE.Identifiers.Prod` 是空数组，钥匙串里也没有 `Xcode-Username` 项。归档与导出都用本地手动签名 profile，所以只有上传这一步需要账号。
- 解除方式（任选其一，需账号主体操作）：① 在 Xcode → Settings → Accounts 重新登录 Apple ID（含双重认证），之后重跑导出上传命令；② 提供 App Store Connect API Key（`.p8` + Key ID + Issuer ID），改用 `xcrun altool --upload-app` 上传；③ 直接把上面的 `Weekyii.ipa` 拖进 Xcode Organizer 或 Transporter 上传。
- App Store Connect build ID: 未取得（本机无法读取 ASC）
- Export compliance result: 待填（沿用「不属于上述任意一种算法」）
- Internal group: 待填（`Apple haha`）
- External group / Beta Review status: 待填（`外部体验者`）
- Formal App Review status: 不适用
