# Weekyii iOS 发布与 App Store 上架 SOP

> 适用范围：Weekyii 的 TestFlight 测试构建、正式 App Store 提交、审核后的发布与后续更新。
> 最后校准：2026-10-22；本文件以当前工程和实际走通的发布流程为准。Apple 后台界面会变化，以本文末尾 Apple 官方帮助链接为准。

## 0. 三个阶段不可混淆

| 阶段 | 目的 | 谁能使用 | Apple 审核 |
| --- | --- | --- | --- |
| Archive / Upload | 将签名 IPA 上传到 App Store Connect | 暂无人可安装 | Apple 自动处理构建 |
| TestFlight | 真机测试与回归 | 内部、外部测试员 | 外部测试构建需要 Beta App Review |
| App Store | 面向公开用户销售/下载 | 所选地区用户 | 正式 App Review |

**“Upload succeeded”只说明上传成功，不表示测试员可安装，也不表示正式上架。**每个阶段均需在 App Store Connect 中看到对应状态后才算完成。

## 1. 当前工程固定信息

不要在发布时临时猜测这些值。变更 Capability、App ID 或签名之前，先同步工程、Apple Developer 后台和本表。

| 项目 | 当前值 | 工程来源 |
| --- | --- | --- |
| App 名称 | Weekyii | App Store Connect / App target |
| 主 App Bundle ID | `com.fluentdesign.Weekyii` | `Weekyii.xcodeproj/project.pbxproj` |
| Widget Bundle ID | `com.fluentdesign.Weekyii.widget` | 同上 |
| Apple Developer Team | `W8UNGRPC5N` | 同上 |
| App Group | `group.com.fluentdesign.Weekyii` | `Resources/Weekyii.entitlements`、Widget entitlements |
| CloudKit Container | `iCloud.com.fluentdesign.Weekyii` | 主 App entitlements |
| Release Profile（App） | `Weekyii App Store CloudKit` | Release build setting |
| Release Profile（Widget） | `Weekyii Widget App Store` | Release build setting |
| 生产 APNs | `production` | 必须从归档 entitlement 验证 |
| 发布版本来源 | App + Widget Release build setting | 不以测试 target 的版本为准 |

### 不可破坏的约束

1. 主 App 与 Widget 的 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` 必须一致。
2. 同一个 `MARKETING_VERSION` 下，上传至 App Store Connect 的 `CURRENT_PROJECT_VERSION` 必须单调递增；已上传构建号不可重用。
3. 新营销版本可从构建号 1 开始，例如 `1.1 (5)` 后可发布 `1.2 (1)`。
4. `WeekyiiTests` / `WeekyiiUITests` 的版本属于测试 Bundle，**不应**为发布而修改。
5. 不提交 `Weekyii.xcodeproj/project.xcworkspace/xcuserdata/.../UserInterfaceState.xcuserstate`；它是本机 Xcode UI 状态，不是产品代码。
6. 一旦上传，构建不可覆盖。代码问题只能递增构建号、重新归档并重新上传。

## 2. 发布权限与人工确认边界

### 可由发布执行者完成

- 拉取分支、跑测试、递增版本、提交/推送、归档、上传。
- 填写已确认的 TestFlight 测试说明、出口合规问卷和既有测试组的分发设置。
- 读取 App Store Connect 的构建处理、TestFlight、审核状态。

### 必须由账号主体确认或提供

- 首次接受/更新 Paid Applications Agreement、税务协议、银行/收款资料。
- 法律主体、开发者身份、银行账户、税务表与付款协议。
- 隐私政策 URL、支持 URL、最终公开描述、截图版权与地区销售范围。
- 正式 App Review 的最终“提交审核”动作，以及审核通过后的公开发布策略。
- Apple 要求接受的新法律协议、账号验证、双重认证验证码。

## 3. 每次发布前的输入清单

在开始前建立 release record，例如 `docs/releases/YYYY-MM-DD-testflight-X.Y-Z.md`，记录：

- 目标版本、上一个 TestFlight 构建、本次变更摘要。
- 基线分支：`online-chatgpt-develop`。
- 已知问题、回滚方案与测试员重点场景。
- 是否改变 SwiftData 模型、迁移计划、CloudKit record schema、entitlements、通知权限或 Widget。
- 真机覆盖安装、iCloud 双设备同步是否已经验证；未验证必须明确标注，不能写成“已通过”。

### 数据安全门槛

Weekyii 是本地优先、可经 iCloud/CloudKit 同步的任务产品。以下变更不是普通 UI 改动，必须额外验收：

| 变更类型 | 发布前必须做的事 |
| --- | --- |
| SwiftData `@Model` 字段/关系/唯一性改变 | 核对 schema 与 migration plan；用旧版本真实/fixture 数据覆盖升级；检查任务、步骤、附件、项目、习惯、设置和 MindStamp |
| CloudKit 实体/字段改变 | 开发 schema 验证后部署生产 schema；双设备新增/编辑/删除/离线重连回归 |
| iCloud 容器或 entitlement 改变 | Developer Portal、profile、主 App、Widget 和归档 entitlements 完全一致 |
| `UserDefaults`/设置项改变 | 覆盖升级后验证旧值的默认值与回退行为 |
| Widget / App Group 改变 | 安装后验证 Widget 加载、共享状态与 App 启动 |

首次启用 iCloud、模型迁移或同步逻辑改动，不能仅凭模拟器自动化测试放行；必须用真实设备覆盖安装，且至少用两台同 Apple Account 设备完成同步回归。

## 4. 同步分支与工作区卫生

所有发布从 `online-chatgpt-develop` 最新远端提交开始。不得把其他分支、未确认 stash 或本机 Xcode 状态混入。

```bash
git status --short
git branch --show-current
git fetch origin
git log --oneline --decorate -5 origin/online-chatgpt-develop
git pull --ff-only origin online-chatgpt-develop
git diff --check
```

放行标准：当前分支是 `online-chatgpt-develop`；HEAD 与远端一致；不存在未解释的业务代码或资源改动。仅见 `UserInterfaceState.xcuserstate` 时保留但不暂存；若还有其他改动，先定位归属，不能默认提交。

## 5. 版本号更新与提交

| 场景 | 示例 | 操作 |
| --- | --- | --- |
| 同一版本的修复构建 | `1.2 (1)` → `1.2 (2)` | 只增加主 App + Widget 构建号 |
| 用户可感知功能/较大改变 | `1.2 (n)` → `1.3 (1)` | 更新营销版本，构建号从 1 起 |
| 正式审核被拒后代码修复 | `1.2 (1)` → `1.2 (2)` | 新构建重新选择/提交，旧构建不能覆盖 |

更新 `Weekyii.xcodeproj/project.pbxproj`：

- `Weekyii` target：Debug、Release 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`。
- `WeekyiiWidget` target：Debug、Release 的同两项。
- **不改** `WeekyiiTests`、`WeekyiiUITests` 的版本号。

```bash
rg -n 'CURRENT_PROJECT_VERSION|MARKETING_VERSION' Weekyii.xcodeproj/project.pbxproj
git diff -- Weekyii.xcodeproj/project.pbxproj
git diff --check
git add -- Weekyii.xcodeproj/project.pbxproj docs/releases/YYYY-MM-DD-testflight-X.Y-Z.md
git commit -m 'chore(release): prepare Weekyii X.Y (Z)'
git push origin online-chatgpt-develop
git rev-parse HEAD
git rev-parse origin/online-chatgpt-develop
```

两条 SHA 必须一致。发布记录中写入 SHA、测试结果和上传结果。

## 6. 全量测试与预检

### 全量自动测试（必做）

使用已安装的指定模拟器；若 UDID 变动，以 `xcrun simctl list devices available` 查找替换。

```bash
xcodebuild test \
  -project Weekyii.xcodeproj \
  -scheme Weekyii \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/weekyii-release-YYYYMMDD-test-derived \
  -resultBundlePath /tmp/weekyii-release-YYYYMMDD-full.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  > /tmp/weekyii-release-YYYYMMDD-full.log 2>&1
```

该命令应覆盖 `WeekyiiTests` 与 `WeekyiiUITests`。不要以“部分 target 通过”代替全量结果。

```bash
xcrun xcresulttool get test-results summary \
  --path /tmp/weekyii-release-YYYYMMDD-full.xcresult --format json
rg 'TEST SUCCEEDED|TEST FAILED|Executed .* tests' \
  /tmp/weekyii-release-YYYYMMDD-full.log
```

放行条件：`result: Passed`、`failedTests: 0`、`skippedTests: 0`。失败时停止发布，保留 `.xcresult` 和日志，先定位并修复；不要通过删/跳过测试来“放行”。

### App Store 预检（每次至少人工勾选）

| 类别 | 必查项 |
| --- | --- |
| 产品可用性 | 无已知崩溃；Today / Week / Pending / Past / Settings 可用；无占位内容 |
| 元数据 | 名称、描述、关键词、截图与实际功能一致；支持 URL 与隐私政策可访问 |
| 隐私 | App Store Connect 隐私声明符合真实行为；Privacy Manifest 覆盖 Required Reason API；无未声明 tracking |
| 权限 | 相册、通知等提示文字与功能一致；不请求无关权限 |
| 账号 | 当前无 App 内登录；未来增加账号创建时必须提供账户删除能力 |
| IAP | 上线数字内容解锁或订阅时必须使用 IAP，并在购买页与商店资料提供条款/隐私链接 |
| 签名 | 无 `com.apple.security.temporary-exception.*` entitlement；生产归档含 production APNs 和正确 CloudKit/App Group |
| 地区 | 所有已选地区的文案、隐私、价格、合规条件均满足；中国大陆上架前额外核对当地要求 |

## 7. 归档、签名验证与上传

### 归档

```bash
xcodebuild archive \
  -project Weekyii.xcodeproj \
  -scheme Weekyii \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/weekyii-release-YYYYMMDD-archive-derived \
  -archivePath /tmp/weekyii-release-YYYYMMDD-X.Y-Z.xcarchive \
  > /tmp/weekyii-release-YYYYMMDD-archive.log 2>&1
```

日志必须出现 `** ARCHIVE SUCCEEDED **`。

### 归档验证（必做）

```bash
APP=/tmp/weekyii-release-YYYYMMDD-X.Y-Z.xcarchive/Products/Applications/Weekyii.app
codesign --verify --deep --strict "$APP"
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/PlugIns/WeekyiiWidget.appex/Info.plist"
/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/PlugIns/WeekyiiWidget.appex/Info.plist"
codesign -d --entitlements :- "$APP"
```

检查：主 App 与 Widget 显示同一 `X.Y (Z)`；`application-identifier` 为 Team + 主 Bundle ID；`aps-environment` 是 `production`；CloudKit container 是 `iCloud.com.fluentdesign.Weekyii`；App Group 是 `group.com.fluentdesign.Weekyii`；`get-task-allow` 为 `false`。

### 导出并上传 App Store Connect

导出 plist 是本机临时文件，**不提交到仓库，也不写入密码、私钥或验证码**。其应指定：

- `method`: `app-store-connect`；`destination`: `upload`；`teamID`: `W8UNGRPC5N`。
- `signingStyle`: `manual`；App profile：`Weekyii App Store CloudKit`；Widget profile：`Weekyii Widget App Store`。
- `iCloudContainerEnvironment`: `Production`；`uploadSymbols`: `true`。

```bash
xcodebuild -exportArchive \
  -archivePath /tmp/weekyii-release-YYYYMMDD-X.Y-Z.xcarchive \
  -exportOptionsPlist /tmp/weekyii-release-YYYYMMDD-export.plist \
  -exportPath /tmp/weekyii-release-YYYYMMDD-upload \
  -allowProvisioningUpdates \
  > /tmp/weekyii-release-YYYYMMDD-upload.log 2>&1
```

日志必须同时出现：

```text
Upload succeeded.
** EXPORT SUCCEEDED **
```

若遇到重复 build number：不要重传或覆盖，递增 build number、重新归档、重新上传。

## 8. TestFlight 发布流程

### 8.1 Apple 处理构建

打开 **App Store Connect → Weekyii → TestFlight → iOS → 构建版本上传**。新构建通常经历：

```text
上传成功 → 正在处理 → 缺少出口合规证明/准备提交 → 外部审核中 → 正在测试
```

若有错误/警告，打开构建详情和上传日志处理。处理完成前不能给外部组分发。

### 8.2 出口合规

对当前 Weekyii 的已验证实现：CloudKit、系统网络传输和系统加密由 Apple 平台提供；代码中仅使用 CryptoKit 的哈希/完整性用途，不提供自定义加密产品。此前构建选择：**不属于上述的任意一种算法**。

这不是永久法律判断。每次引入 VPN、端到端加密、加密文件、TLS 以外的网络库或其他加密实现时，必须重新审查并按 Apple 实际问卷如实回答。

### 8.3 测试信息

构建详情 → **测试信息**：

1. 填写本版“测试内容”，只写本次实际改动及明确回归场景。
2. 要求测试员通过 TestFlight 覆盖更新，**不要卸载**，并核对旧任务、项目、附件、习惯与设置。
3. 有 iCloud 或迁移改动时，明确包含双设备同步、离线重连和升级不丢数据。
4. 要求反馈包含设备型号、iOS 版本、构建号、步骤、截图/录屏与崩溃日志。

参考文案见 [testflight-what-to-test.md](testflight-what-to-test.md)。必须按本版删改旧内容与版本号。

### 8.4 内部与外部测试

**内部测试**：将构建加入 `Apple haha`（或目标内部组）；内部测试员需要 App Store Connect 权限，但不需要 Apple Developer Program 资格，通常无需 Beta App Review。

**外部测试**：

1. 构建详情“添加群组”，选择 `外部体验者`。
2. 复核测试内容，勾选“自动通知测试员”。
3. 点击“提交以供审核”。这是 **Beta App Review**，不是正式上架审核。
4. 审核通过后，构建状态为“正在测试”，外部组成员才能安装/更新。

外部测试者只需可用 Apple Account；不要使用 Developer Program 团队邀请链接。邀请必须来自 TestFlight 组或 TestFlight 公共链接。

### 8.5 TestFlight 完成标准

- App Store Connect 构建状态为“正在测试”。
- 构建行包含目标内部/外部组；外部组邀请数符合预期。
- 至少一台真机已通过覆盖更新安装 `X.Y (Z)`，并确认本地数据存在。
- 涉及同步/迁移时，完成第 3 节的真实设备验收。

## 9. 正式 App Store 上架流程

TestFlight 可以继续测试；正式上架不需要上传另一份 IPA。选择已在 TestFlight 处理完成的同一构建即可。

### 9.1 后台必填资料

在 **App Store Connect → Weekyii → 分发** 完成：

| 模块 | 需要完成的内容 |
| --- | --- |
| App 信息 | 名称、分类、内容版权、年龄分级问卷、必要地区声明 |
| App 隐私 | 基于真实数据处理的隐私标签；隐私政策 URL |
| 商店页面 | 副标题、描述、关键词、推广文本（可选）、支持 URL、营销 URL（可选） |
| 截图 | 各必需 iPhone 尺寸；展示真实使用场景，不能仅放 Logo/启动图 |
| 定价与地区 | 免费/付费、地区、可用性、税务与协议状态 |
| 审核信息 | 联系人、电话、邮箱；无登录则说明“无需账号”；非直观功能提供路径 |
| 构建版本 | 选择待发布构建，例如 `1.2 (1)` |

Weekyii 当前没有 App 内登录，不应填写虚构测试账号。将来增加登录时，必须提供稳定可用的审查账号、密码和必要说明。

### 9.2 审核备注建议

按本版实际能力调整：

```text
Weekyii 是周粒度任务与待办管理应用，无需注册或登录即可使用。

核心入口：
1. 今日：创建草稿、启动一天、完成任务、调整每日启动时间。
2. 本周：查看本周日程与项目任务。
3. 扩展：项目、心印和统计模块。
4. 设置：外观、提醒及 iCloud 同步状态。

iCloud 使用设备已登录 Apple Account 的私有数据库自动同步；未登录 iCloud 时，应用仍可正常本地使用。
```

不要在备注中承诺未实现功能，也不要提供真实用户数据。

### 9.3 提交与发布选项

1. 完成必填项后，点击“添加以供审核”。
2. 审核提交页复核构建、元数据、隐私和审核信息。
3. 选择发布方式：首次推荐 **手动发布**；也可自动或定时发布。
4. 最终点击“提交审核”前由账号主体确认；它会发起正式审核并可能触发对外发布。

### 9.4 审核结果处理

| 状态 | 处理 |
| --- | --- |
| 等待审核 / 审核中 | 不改动被审核构建；新开发构建不会自动替换审核构建 |
| 元数据被拒 | 修正资料后重新提交，未必需要新二进制 |
| 二进制被拒 | 记录 Guideline、审查截图与路径；修复后递增 build、上传、选择新构建、重新提交 |
| 审核通过 + 手动发布 | 账号主体点击发布，并确认目标地区商店页可见 |

## 10. 上线后检查与回滚

### 上线后 24 小时

- 在真实 App Store 下载页核对名称、图标、截图、描述、版本、隐私标签与价格。
- 真机从 App Store 覆盖安装旧版，确认数据未丢失。
- 检查 App Store Connect 崩溃、反馈、TestFlight 反馈与诊断。
- iCloud 改动版持续监测跨设备新增/编辑/删除与冲突收敛。

### 回滚原则

App Store 不支持把已发布二进制直接“回退为旧构建”。严重问题的处置是：停止发布/从销售中移除（账号主体决定）；从稳定代码修复并产生更高 build；先经 TestFlight 覆盖更新验证数据安全，再提交 App Review。**不要删除用户本地数据库或 CloudKit 数据来“回滚”。**

## 11. Release record 模板

每次 TestFlight 或正式提交在 `docs/releases/` 新建一份记录：

```markdown
# Weekyii X.Y (Z) — TestFlight / App Store release

- Date / timezone:
- Branch and commit SHA:
- Previous production/TestFlight build:
- Scope:
- SwiftData / migration impact: none | details
- CloudKit / entitlement impact: none | details
- Known issues:

## Verification
- Full tests: <count> passed, 0 failed, 0 skipped
- Real-device update:
- iCloud two-device regression:
- Archive signature / entitlement verification:

## Distribution
- Upload receipt:
- App Store Connect build ID:
- Export compliance result:
- Internal group:
- External group / Beta Review status:
- Formal App Review status (if applicable):
```

## 12. 官方参考

- [上传构建版本](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [TestFlight 概览](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- [提交 App 审核](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)
- [完整审核资料](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)
- [管理 App 隐私](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [设置年龄分级](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
