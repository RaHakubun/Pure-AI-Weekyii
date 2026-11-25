# Weekyii 1.2 (8) — Release 配置 / 付费墙生效

- Date: 2026-11-05 22:17 (Asia/Taipei)。
- Branch: `online-chatgpt-develop`，HEAD `0b9c7c2`（与 `origin/online-chatgpt-develop` 一致）。
- 上一版：1.2 (7)（`Weekyii Beta` scheme / Beta 配置，已在 ASC 且正在被使用）。
- 版本变更：`MARKETING_VERSION 1.2` 不变，`CURRENT_PROJECT_VERSION 7 → 8`（Debug / Release / Beta 三套配置，App 与 Widget 共 6 处）；测试 Bundle 保持 1.0 / 5。

## 与 1.2 (7) 的关键差异

1.2 (7) 是 **Beta 配置**，`WEEKYII_BETA` 被编入二进制。`PurchaseService.isBetaTesterBuild()`（`Services/PurchaseService.swift:155-162`）在沙箱环境下直接返回 VIP，因此 TestFlight 测试员看不到付费墙。

1.2 (8) 用 **`Weekyii` scheme**（`ArchiveAction buildConfiguration = "Release"`）归档，**付费墙真正生效**，同时这也是唯一可以提交 App Store 的形态（App Review 同样跑在沙箱，Beta 后门会让审核员一进去就是 VIP）。

## Build

- Scheme：`Weekyii`；**未传 `-configuration`**，由 scheme 的 ArchiveAction（`Release`）决定。
- 命令带 `OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'`（本机宏沙箱限制）。
- `** ARCHIVE SUCCEEDED **`，耗时 1m53s。

## Verification

- Full tests：iPhone 17 Pro 模拟器（iOS 26.2），585 个用例，**582 通过 / 3 失败 / 0 跳过**。
  - 3 个失败全部在 `WeekyiiUITests/DraftReorderUITests`（`testDraftAddAndEditBothOpenTaskEditorSheet`、`testDraftShowsFloatingStartButton`、`testDragHandleReordersDraftTasks`），均为整轮 UI 套件的前三个用例，表现为草稿区被判为“已冻结 / 已启动”。
  - 单跑这 3 个用例 **全部通过**（`/tmp/weekyii-retest-draft.log`）。属整轮冷启动下的既有 flaky，非本版引入；同一代码 15:27 的 1.2 (7) 全量运行 585 全过。
- 归档签名：`codesign --verify --deep --strict` 通过。
- 版本：App 与 Widget 均为 `1.2 (8)`。
- 付费墙配置：归档日志 `WEEKYII_BETA` 命中 **0**；二进制 `AppTransaction` 符号 **0**（Beta 版是 6 / 5）→ `isBetaTesterBuild()` 恒为 false。
- entitlements：`aps-environment=production`、`beta-reports-active=true`、`get-task-allow=false`、`iCloud.com.fluentdesign.Weekyii`（CloudKit）、`group.com.fluentdesign.Weekyii`、`application-identifier=W8UNGRPC5N.com.fluentdesign.Weekyii`。
- 启动崩溃回归（1.2 (5) 的 demangler 栈溢出）：Release 归档产物 `settingsHome` 最大 `<>` 嵌套深度 **1**、`_ConditionalContent` **0**，与 1.2 (7) 的 Beta 产物一致。
- IPA：`/tmp/weekyii-release-20261105b-ipa/Weekyii.ipa`，解包复核版本 `1.2 (8)`、签名通过、`AppTransaction` 0。

## Distribution

- 归档：`~/Library/Developer/Xcode/Archives/2026-11-05/Weekyii-1.2-8-2026.11.05-22.16.xcarchive`
- Upload receipt：待账号主体在 Xcode Organizer 执行 Distribute App
- App Store Connect build ID：待填
- Export compliance：沿用「不属于上述任意一种算法」（本版无新增加密实现）
- Internal group `Apple haha` / External group `外部体验者`：待分发
- Formal App Review status：不适用（本构建先上 TestFlight 验证付费墙与真机启动）

## Known issues

- `WeekyiiUITests/DraftReorderUITests` 前三个用例在整轮冷启动时 flaky（见上）；单跑通过。
- `testWeekTopologyTaskNodeShowsTaskInspectorNotForgotten` 在 iPhone 17 Pro Max 稳定失败、Pro 通过（宽屏聚焦后任务卡落在 220pt 画布外）。既有缺陷，本版未改 `WeekTopologyView.swift`；本次全量在 iPhone 17 Pro 上执行。
- 真机启动验证：待账号主体装 TestFlight 1.2 (8) 确认。
