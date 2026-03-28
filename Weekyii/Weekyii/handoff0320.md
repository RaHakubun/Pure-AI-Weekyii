## 1. 当前任务目标
当前工作主线是 **Weekyii iOS 客户端功能与视觉迭代收口**，核心包含三块：
1) 已完成的「Live Activity / 灵动岛 + 锁屏活动」能力保持可运行并可回归；
2) 主题系统持续精修（最近集中在 `sunset` 和 `lotr`），确保设置页可切换、全局颜色一致、Widget 同步；
3) 下一阶段潜在需求是评估并推进“仅用 Apple 生态（不自建后端）”的数据同步方案（CloudKit/iCloud）。

预期产出：
- 一份可继续开发的干净上下文（代码位置、改动点、风险和下一步）；
- 接手 Agent 能在不依赖历史对话的情况下，直接继续实现/验证。

完成标准（本交接视角）：
- 接手方可明确：现在代码到哪一步、哪些功能已做、哪些尚未收口、先看哪里、先测什么、先改什么。

## 2. 当前进展
### 已完成的主要开发
1. **Live Activity（灵动岛/锁屏活动）已落地**
- 新增共享模型与动作 URL（`weekyii://live/done-focus` / `postpone-focus` / `open-today`）。
- App 端实现 `TodayLiveActivityService` + reconcile 生命周期接入（启动/前后台/分钟 tick/状态推进后刷新）。
- Widget 端实现 Dynamic Island minimal/compact/expanded + Lock Screen Activity UI。
- 已做 availability 守卫（`iOS 16.1+`，禁用时 no-op，不影响主流程）。

2. **主题系统已升级为 Light/Dark 双态并全局联动**
- 设置页有外观模式（自动/浅色/深色）与主题选择。
- `selectedThemeRaw + appearanceModeRaw` 可驱动 App + Widget 同步。

3. **视觉主题迭代（最近）**
- `sunset`：重绘了 Today 背景与首状态卡插画，强化偏左黄金位落日、扁平拟物、减少炫光。
- `lotr`：新增 Today 专属视觉层（寒夜/山体/雨线/微弱召唤光），并重调 `lotr` 色板。
- 用户最新明确要求“魔戒主题不需要绿色”，已将 `lotr` 绿色通道替换为冷灰蓝/铁灰系，并去除插画偏绿夜色。

### 已完成的验证（关键）
- `xcodebuild build -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'` 通过。
- `xcodebuild build -scheme WeekyiiWidget -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'` 通过。
- `xcodebuild test -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:WeekyiiTests` 通过。
- `xcodebuild test -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:WeekyiiUITests` 通过（串行跑时稳定）。
- 注意：`WeekyiiWidget` scheme 当前未配置 test action，`xcodebuild test -scheme WeekyiiWidget ...` 返回 code 66（非代码编译错误）。

## 3. 关键上下文
### 重要背景信息
- 当前分支：`codex/theme-orange`。
- 工作区有大量未提交改动与历史杂项文件；不能盲目 `git add .`。
- 用户偏好高频视觉迭代，尤其是 Today 页面与主题风格表达。

### 用户明确要求（近期有效）
1. 主题视觉要有“叙事感”，不是通用模板。
2. `sunset` 已要求：真实感 -> 扁平拟物、非居中、太阳更红、不要漫反射光。
3. `lotr` 已要求：按歌词重绘，并且 **不要绿色**。
4. iCloud 同步诉求：希望不自建后端，接受 Apple 账号同步路径。

### 已知约束
- iOS 目标目前是 26.2（工程配置），但 Live Activity 代码做了 16.1+ 守卫。
- 项目使用 SwiftData + Observation，若要真的覆盖 iOS 16.1 全功能，需要较大兼容改造（非仅改 deployment target）。
- 用户多次强调避免无关改动、不要误触其他模块。

### 已做出的关键决定
- Live Activity 交互首版走 URL action 路由，暂不做纯后台 AppIntent 执行。
- 主题系统继续沿用语义色 token 机制（`Color+Weekyii`），不走散落硬编码。
- `lotr` 与 `sunset` 的专属视觉挂在 Today 页面（状态区/背景）。

### 重要假设
- 后续接手会继续在 `codex/theme-orange` 上推进（未切回 `theme-orange`）。
- 用户优先看“视觉结果 + 可运行性”，其次才是结构重构。

## 4. 关键发现
1. **灵动岛功能已具备业务闭环**：启动/更新/结束、深链动作、状态推进后的 reconcile 都已接通。
2. **UI 测试失败曾出现过“Lost connection to app”**：主要发生在并行跑 Unit + UI 测试时，串行执行后通过。
3. **主题系统核心入口高度集中**：
- 主题枚举/色板/语义色：`Shared/Extensions/Color+Weekyii.swift`
- 设置与持久化：`Resources/SettingsView.swift` + `Resources/UserSettings.swift`
- 全局应用：`App/WeekyiiApp.swift` + `App/ContentView.swift`
- Widget 同步：`Services/WidgetSnapshotComposer.swift` + `Shared/WidgetSupport/WeekyiiWidgetSupport.swift` + `WeekyiiWidget/*`
4. **`lotr` 为 premium 主题，有回落逻辑**：如果锁定状态未解锁，设置页可见性/可选性要与 `resolvedTheme` 一致，避免“可选但回落”。
5. **iCloud问题结论已对用户说明**：不登录 iCloud 仍可本地使用；iCloud 只是同步增强能力，不应成为使用前置条件。

## 5. 未完成事项（按优先级）
1. **P0：回归验证最新两次主题改动（sunset + lotr no-green）**
- 最近对 `TodayView.swift` 和 `Color+Weekyii.swift` 进行了较大视觉改动，尚未重新跑编译/测试。

2. **P1：确认 lotr 视觉是否满足用户审美**
- 用户可能继续要求进一步“纯黑金/更冷/更克制”。

3. **P1：若用户决定推进 iCloud 同步，需输出可执行实施方案**
- 包括 CloudKit + SwiftData 的最小落地范围、冲突策略、开关与降级行为。

4. **P2：整理提交边界**
- 当前工作区杂项文件较多（`.DS_Store`、docs 等），后续提交必须只含目标文件。

## 6. 建议接手路径
### 应优先查看的文件
1. `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Features/Today/TodayView.swift`
2. `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Shared/Extensions/Color+Weekyii.swift`
3. `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/App/WeekyiiApp.swift`
4. `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Shared/WidgetSupport/WeekyiiWidgetSupport.swift`
5. `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/WeekyiiWidget/WeekyiiWidget.swift`

### 应先验证什么
1. Build 是否通过（Weekyii + Widget）。
2. Today 页面在 `sunset` / `lotr` 的视觉是否正确切换。
3. `lotr` 是否彻底无绿色（包括 accent/task/background 观感）。
4. Live Activity 是否仍可展示并响应 deep link 动作。

### 推荐下一步动作
1. 跑最小回归命令：
- `xcodebuild build -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'`
- `xcodebuild build -scheme WeekyiiWidget -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'`
- `xcodebuild test -scheme Weekyii -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:WeekyiiTests`
2. 若用户继续微调主题，只改 `TodayView.swift` + `Color+Weekyii.swift`，避免扩散。
3. 若用户转向 iCloud 同步，先出方案文档再实施（避免直接侵入模型层）。

## 7. 风险与注意事项
1. **不要并行跑 Unit + UI 测试**（同模拟器会话易出假失败）。
2. **不要提交无关文件**（当前目录有大量历史/临时文件变更）。
3. **Premium 逻辑不要破坏**：`lotr` 的解锁、回落、设置页可选状态必须一致。
4. **主题特化分支集中在 Today**：改动时注意 `sunset` 与 `lotr` 条件分支互不覆盖。
5. **Widget 主题同步链路容易漏**：App 内看起来正确，不代表 Widget 一定更新；需检查 snapshot 写入与 reload 时机。
6. 已验证过“iCloud 不是必须登录才能用 App”；不要把“本地可用”逻辑改成强依赖 iCloud。

---

### 下一位 Agent 的第一步建议
先执行一次 `git status --short` + 三条最小回归命令（Weekyii build、Widget build、WeekyiiTests），确认当前最新视觉改动没有引入编译或核心逻辑回归；随后在模拟器里仅验证 Today 页面的 `sunset` 与 `lotr` 切换效果，并把截图/差异点反馈给用户确认审美方向，再决定是否继续细调或转入 iCloud 同步方案设计。
