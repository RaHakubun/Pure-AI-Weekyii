# Weekyii 1.2 (7) — TestFlight candidate

- Date: 2026-11-05 (Asia/Taipei).
- Branch: `online-chatgpt-develop`；source HEAD: `0b9c7c2`（Merge pull request #5 from `notion-claude/feat-in-app-purchase`）。
- 上一版 TestFlight：1.2 (5)（Release 配置，启动崩溃）与 1.2 (6)（Beta 配置，含同一崩溃；构建号已在 ASC 用掉）。
- 版本变更：App + Widget `MARKETING_VERSION 1.2`（不变）、`CURRENT_PROJECT_VERSION 6 → 7`（Debug / Release / Beta 三套配置）；测试 Bundle 版本不动（1.0 / 5）。
- 构建号依据：1.2 下 build 1–6 均已消耗，7 是下一个未用号。

## Build

- Scheme：`Weekyii Beta`；**未传 `-configuration`**，由 scheme 的 `ArchiveAction`（`Beta`）决定配置，因此编入 `WEEKYII_BETA`。
- 归档命令额外带 `OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'`（本机宏沙箱限制，见 SOP §6）。

## Verification

- Full tests：iPhone 17 Pro 模拟器（iOS 26.2），`xcresult` 汇总 585 个用例（561 单元 + 24 UI），**0 失败 0 跳过**，`** TEST SUCCEEDED **`。
- 归档：`** ARCHIVE SUCCEEDED **`；`codesign --verify --deep --strict` 通过。
- 版本：App 与 Widget 均为 `1.2 (7)`。
- Beta 编译条件：归档日志 `WEEKYII_BETA` 命中 6 次（Weekyii 与 WeekyiiWidget 各 3 处）；二进制 `AppTransaction` 符号 5 个 → `isBetaTesterBuild()` 已编入，测试员在沙箱环境自动获得 VIP。
- entitlements：`aps-environment=production`、`beta-reports-active=true`、`get-task-allow=false`、`iCloud.com.fluentdesign.Weekyii`（CloudKit）、`group.com.fluentdesign.Weekyii`。
- 内嵌 profile：App `Weekyii App Store CloudKit`、Widget `Weekyii Widget App Store`。
- IPA：导出成功并解包复核，版本与签名一致。

## 启动崩溃（1.2 (5)/(6)）的修复证据

崩溃根因是 `SettingsView.body` 实例化具体类型时 Swift 运行时 demangler 递归打穿 1 MB 主线程栈（`EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE`，栈顶全在 `decodeMangledType` 循环）。

合并后的代码把 `settingsHome` 拆成 `settingsHomeUpperSectionsErased()` / `settingsHomeLowerSectionsErased()` 两个 `@inline(never)` 的 `AnyView` 函数。归档产物实测：

| 指标 | 1.2 (5)（崩溃） | 1.2 (7) |
|---|---|---|
| `settingsHome` mangled 长度 | 873 | 390 |
| demangled 长度 | 5246 | 1916 |
| 最大 `<>` 嵌套深度 | 16 | 1 |
| `_ConditionalContent` 出现次数 | 16 | 0 |
| `SettingsView.body.getter` 栈帧 | 1008 B | 992 B |

嵌套深度降到 1、条件内容归零，demangler 不再有可递归的结构。

- 真机启动验证：未做（需账号主体在 TestFlight 安装确认）。模拟器 8 MB 栈不构成判据。

## Distribution

- 归档位置：`~/Library/Developer/Xcode/Archives/2026-11-05/Weekyii-1.2-7-2026.11.05-15.30.xcarchive`
- IPA：`/tmp/weekyii-release-20261105-ipa/Weekyii.ipa`
- Upload receipt：待账号主体在 Xcode Organizer 执行 Distribute App
- App Store Connect build ID：待填
- Export compliance：沿用「不属于上述任意一种算法」（本版无新增加密实现）
- Internal group `Apple haha` / External group `外部体验者`：待分发
- Formal App Review status：不适用

## Known issues

- `WeekyiiUITests/DraftReorderUITests/testWeekTopologyTaskNodeShowsTaskInspectorNotForgotten` 在 iPhone 17 Pro Max 上失败、iPhone 17 Pro 通过（宽屏聚焦某天后任务层落到 220pt 画布外）。既有缺陷，非本版引入；本次全量在 iPhone 17 Pro 上执行。
