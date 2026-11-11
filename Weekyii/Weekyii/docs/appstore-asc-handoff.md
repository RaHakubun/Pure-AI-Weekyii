# Weekyii App Store 上架交接（仅 iPhone）

> 交接对象：能操控本机浏览器的 Agent（Cursor）。  
> 生成时间：2026-11-06。代码仓库：`/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii`  
> 分支：`online-chatgpt-develop`



---

## 0. 边界（先读这段）

| 可以做                                 | 不要做                                  |
| ----------------------------------- | ------------------------------------ |
| 在浏览器操作 App Store Connect            | **不要点「提交审核」**（账号主体人工确认）              |
| 在 iOS 模拟器安装 App、造数据、截图              | **不要改任何 `.swift` / `.pbxproj` 文件**   |
| 截图存到 `/tmp/weekyii-shots-appstore/` | **不要 `git add` / `commit` / `push`** |
| 读取本文档提到的路径                          | 不要删除 TestFlight 已有构建或测试组             |

ASC 登录、Apple ID 密码、双重验证由账号主体完成。如果会话失效，停下来找人，不要尝试绕过。

---

## 1. 当前状态

| 项         | 值                                                              |
| --------- | -------------------------------------------------------------- |
| Bundle ID | `com.fluentdesign.Weekyii`                                     |
| 当前版本      | `1.2`，build `8`（已在 TestFlight）                                 |
| 上架目标      | `1.2 (9)`                                                      |
| 设备族       | **仅 iPhone**（2026-11-06 决定，代码已改）                               |
| 最低系统      | iOS 18.0                                                       |
| 内购        | 4 个：月 ¥12 / 季 ¥28 / 年 ¥68（含 14 天试用）/ 终身 ¥198                   |
| 隐私政策      | <https://weekyii-privacy-h1jjp4ia8f0.qoder.zone> （实测 HTTP 200） |
| 支持 URL    | **缺失，阻塞项**                                                     |

---

## 2. 已完成（Pace，Cursor 不需要重做）

1. **App 图标补齐**：`Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` 原先 14 个 slot 只有 4 个配了图片，缺 iPhone 60×60@3x（180px）。已从 1024 母图生成 40/58/60/80/87/180 六张并补齐全部 slot。验证：`Assets.car` 内 AppIcon 条目 7 → 19，180×180 已存在。
2. **仅 iPhone**：App target 的 Debug / Release / Beta 三个配置 `TARGETED_DEVICE_FAMILY` 由 `"1,2"` 改为 `1`。Tests / UITests 未动。  
   验证：`xcodebuild build` 通过，产物 `Info.plist` 的 `UIDeviceFamily` 为 `[1]`。
3. **版本号**：`CURRENT_PROJECT_VERSION = 8`。

⚠️ 因为图标和设备族都改了，**1.2 (8) 不能用于正式上架**，必须用重新打包的 1.2 (9)。

---

## 3. 任务 A：App Store Connect 浏览器操作

入口：<https://appstoreconnect.apple.com/apps> → 选择 **Weekyii**

逐项做完打勾。字段值可直接复制。

### A1. App 信息

| 字段          | 填什么                                                             |
| ----------- | --------------------------------------------------------------- |
| 名称          | `Weekyii`（已存在，不要改）                                              |
| 副标题（≤30 字符） | `以周为单位的计划与待办`                                                   |
| 主类别         | 效率                                                              |
| 次类别         | 生活                                                              |
| 内容版权        | 选择「不包含第三方内容」                                                    |
| 年龄分级        | 点「编辑」→ 重填问卷（Apple 已改用 4+/9+/13+/16+/18+）→ 所有项目选「无」→ 结果应为 **4+** |

> 截图里显示 `Weekyii UNRATED`，说明这一项还是空的。

### A2. 定价与销售范围

- 价格：**免费**
- 销售范围：所有地区（若要包含中国大陆，见第 5 节备案号）
- App 分发方式：App Store

### A3. App 隐私

- 是否收集数据：**否，我们不收集数据**
- 隐私政策 URL：`https://weekyii-privacy-h1jjp4ia8f0.qoder.zone`
- 追踪：不使用

> 依据：App 无第三方 SDK、无广告、无账号体系；iCloud 走用户私有数据库，开发者读不到，按 Apple 定义不属于「收集」。

### A4. 版本信息（1.2 准备提交）

**描述**（直接粘贴）：

```
Weekyii 是一款以「周」为单位的计划与待办应用。

不是又一个待办清单，而是把一周当成一个整体来安排：今天要做什么、本周还剩什么、下周准备什么，都在同一张周历上。

【今日】
每天开始前先写下草稿，想清楚了再启动这一天。启动后草稿变成正式任务，完成、延后、放弃都有记录。

【本周】
一周七个格子，任务按天铺开。拖动就能改期，不需要进详情页。

【未来】
还没到的那几周先放着，到时间自动进入本周。不让未来的事干扰当下，这是 Weekyii 的设计前提。

【扩展】
项目、心印、统计。项目按周查看任务分布，心印记录那些不值得单独立项但需要留痕的事。

【Widget】
桌面小组件显示今天剩下的任务，不打开 App 也能看到进度。

【iCloud 同步】
使用你设备上已登录的 Apple 账户私有数据库同步，开发者看不到你的数据。未登录 iCloud 时完全本地可用。

【VIP】
部分主题、灵动执行模式与 iCloud 跨设备同步为 VIP 功能。订阅可随时在系统设置中取消。
```

**关键词**（≤100 字符）：

```
周计划,待办,任务管理,时间管理,日程,周视图,效率,专注,计划,GTD,周历,习惯
```

**支持 URL**：见第 5 节，未解决前此项无法保存。

**截图**：只上传 **iPhone 6.9 英寸**（1320×2868），3–10 张，用任务 B 的产物。

**构建版本**：选择 `1.2 (9)`（需要先由 Pace 打包上传）。

**出口合规**：选「不属于上述任意一种算法」（只使用系统 HTTPS / CryptoKit，无自研加密）。

### A5. App 内购买项目

路径：左侧「功能」→「App 内购买项目」。

确认以下 4 个 ID 都存在，状态为「准备提交」：

| 商品 ID                                    | 类型     | 价格                  |
| ---------------------------------------- | ------ | ------------------- |
| `com.fluentdesign.Weekyii.vip.monthly`   | 自动续期订阅 | ¥12 / 月             |
| `com.fluentdesign.Weekyii.vip.quarterly` | 自动续期订阅 | ¥28 / 季             |
| `com.fluentdesign.Weekyii.vip.yearly`    | 自动续期订阅 | ¥68 / 年（含 14 天免费试用） |
| `com.fluentdesign.Weekyii.vip.lifetime`  | 非消耗型   | ¥198 一次性            |

**首次提交必须把 4 个内购和 App 放进同一个审核提交**，否则 App 过审后用户买不了。

年订阅的「介绍性优惠」要确认：14 天免费试用、所有地区、新订阅者。

### A6. App 审核信息

**联系信息**：姓名、电话、邮箱（用账号主体的真实信息）。

**备注**（直接粘贴）：

```
Weekyii 是周粒度的计划与待办应用，无需注册或登录即可使用全部核心功能。

主要入口（底部 5 个标签）：
1. 过去：已完成的历史日期
2. 今日：创建草稿、启动一天、完成任务
3. 未来：未来几周的任务与待启动卡片
4. 扩展：项目、心印、统计
5. 设置：外观主题、提醒、iCloud 同步状态

付费内容（VIP）的入口与验证路径：
- 入口 A：设置 → 主题 → 任一带锁主题 → 打开 Weekyii VIP 页
- 入口 B：设置 → 执行模式 → 灵动模式
- VIP 页有 4 档商品（月/季/年/终身），沙箱环境可直接完成购买流程，不会真实扣款。
- 年订阅含 14 天免费试用，试用规则由 StoreKit 提供。
- 页面底部有「恢复购买」、服务条款（Apple 标准 EULA）和隐私政策链接。

iCloud 同步使用设备已登录 Apple 账户的私有数据库（CloudKit private database），开发者无法读取用户数据。未登录 iCloud 时应用完全本地可用。

App 不收集任何用户数据，无第三方 SDK，无广告，无追踪。
```

---

## 4. 任务 B：模拟器截图

### B1. 设备与环境

唯一设备：**iPhone 17 Pro Max**，UDID `3EDDD4C9-B8A9-4DAE-995C-D7B7FD3A9FF0`，原生分辨率 **1320×2868**（正好是 App Store 6.9 英寸要求的尺寸）。

```bash
UDID=3EDDD4C9-B8A9-4DAE-995C-D7B7FD3A9FF0
xcrun simctl boot $UDID || true
open -a Simulator
# 强制中文，否则截图是英文界面
xcrun simctl spawn $UDID defaults write -g AppleLanguages -array zh-Hans
xcrun simctl spawn $UDID defaults write -g AppleLocale -string zh_CN
```

### B2. 安装 App

构建产物路径（Pace 已生成）：

```
/tmp/weekyii-iphoneonly/Build/Products/Debug-iphoneos/Weekyii.app
```

```bash
xcrun simctl install $UDID /tmp/weekyii-iphoneonly/Build/Products/Debug-iphoneos/Weekyii.app
```

如果该路径不存在（`/tmp` 被清理），重新构建一次：

```bash
cd /Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii
xcodebuild build -project Weekyii.xcodeproj -scheme Weekyii \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/weekyii-iphoneonly \
  CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'
```

`OTHER_SWIFT_FLAGS` 不能省，否则所有 Swift 宏展开失败，报上千条假错误。

### B3. 状态栏统一

```bash
xcrun simctl status_bar $UDID override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4
```

### B4. 造数据（关键）

首次安装是空数据，直接截图会很难看。启动后手工造：

```bash
xcrun simctl launch $UDID com.fluentdesign.Weekyii
```

1. **今日**：新建 4–5 条任务，完成其中 1–2 条（要让「已完成区」有内容）
2. **未来**：在下一周加 2–3 条任务，让周视图和待启动卡片都有内容
3. **扩展**：新建 2–3 个项目，各带 1–2 条任务

不要传 `-uiTesting` 启动参数，那会切换成测试种子数据。

### B5. 截图清单

```bash
mkdir -p /tmp/weekyii-shots-appstore
xcrun simctl io $UDID screenshot /tmp/weekyii-shots-appstore/01-today.png
```

| 文件                | 页面            | 导航                |
| ----------------- | ------------- | ----------------- |
| `01-today.png`    | 今日            | 底部第 2 个标签         |
| `02-future.png`   | 未来（周视图）       | 底部第 3 个标签         |
| `03-projects.png` | 扩展 → 项目列表     | 底部第 4 个标签         |
| `04-theme.png`    | 设置 → 主题列表     | 底部第 5 个标签 → 主题    |
| `05-vip.png`      | Weekyii VIP 页 | 设置 → 主题 → 点任一带锁主题 |
| `06-widget.png`   | 桌面 Widget（可选） | 回到主屏              |

### B6. 验收

```bash
for f in /tmp/weekyii-shots-appstore/*.png; do
  echo -n "$f  "; sips -g pixelWidth -g pixelHeight "$f" | grep pixel | tr '\n' ' '; echo
done
```

每张都必须是 **1320 × 2868**。

逐张目检，确认没有：TestFlight / 沙箱 / Debug 字样、空白占位、红点角标、低电量图标。

---

## 5. 阻塞项（需要人决定，Cursor 不要自己拍板）

| # | 事项               | 现状          | 影响                         |
| - | ---------------- | ----------- | -------------------------- |
| 1 | **支持 URL**       | 完全没有，ASC 必填 | A4 无法保存，上架流程卡死             |
| 2 | **中国大陆 ICP 备案号** | 未提供         | 没有备案号，ASC 提交大陆区会被拒；只能先排除大陆 |
| 3 | **1.2 (9) 上传**   | 未打包         | A4 选不到构建版本                 |
| 4 | 截图内容             | 未产出         | A4 无法保存                    |

支持 URL 的解决方式（推荐）：在 `privacy-site/` 里加一个 `support.html`，写邮箱 `clbwc@outlook.com` 和常见问题，重新部署到现有域名，得到类似 `https://weekyii-privacy-h1jjp4ia8f0.qoder.zone/support.html` 的链接。这件事由 Pace 做，Cursor 不要动。

---

## 6. 分工总览

| 角色       | 负责                                       |
| -------- | ---------------------------------------- |
| Pace     | 代码改动、打包 1.2 (9)、归档、Release 配置验证、支持页      |
| Cursor   | 第 3 节 ASC 填写、第 4 节模拟器截图                  |
| 账号主体（用户） | ASC 登录、Organizer 上传 IPA、点「提交审核」、备案号、联系信息 |

---

## 附录：1.2 (9) 打包命令（参考，Pace 执行）

```bash
cd /Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii
xcodebuild archive -project Weekyii.xcodeproj -scheme "Weekyii" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/weekyii-release-20261106-archive-derived \
  -archivePath /tmp/weekyii-release-20261106-1.2-9.xcarchive \
  OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'
```

不要传 `-configuration`：`Weekyii` scheme 的 ArchiveAction 已经是 Release。传了 `-configuration Release` 会覆盖 scheme，编出没有 `WEEKYII_BETA` 的包（对正式版无害，但会打乱 Beta 流程）。

归档后必须验证：

```bash
APP=/tmp/weekyii-release-20261106-1.2-9.xcarchive/Products/Applications/Weekyii.app
/usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily' "$APP/Info.plist"   # 应为 [1]
nm -u "$APP/Weekyii" | grep -c AppTransaction                          # 应为 0（Release 无 Beta 后门）
xcrun --sdk iphoneos assetutil --info "$APP/Assets.car" | grep -c '"Name" : "AppIcon"'  # 应 ≥ 15
```
