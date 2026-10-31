# 魔戒主题 · 视觉重构交接（2026-10-29）

给下一位做视觉重构的 Agent。本文只陈述**当前代码事实**，不给方案。

---

## 0. 先读这三条

1. **旧文档 `docs/lotr_theme_brief_2026-10-26.md` 已整体失效。** 它描述的圆角 18、金色边框、`ornament` 内圈金线、`badge: .ember`、`backdrop: .none` 全部不存在了。以本文为准，别照旧 brief 改。
2. **当前有 8 个文件未提交**，就是本轮改的成果，基线是 `0803e76`（分支 `notion-claude/feat-in-app-purchase`，已与远端同步）：
   `Color+Weekyii.swift` / `View+Modifiers.swift` / `WeekCard.swift` / `LiveModuleTile.swift` / `PastView.swift` / `TodayView.swift` / `SettingsView.swift` / `Tests/ModelTests.swift`。
   `git diff` 就是全部现状差异。
3. **路径约定**：本文行号相对仓库根，git 路径写作 `Weekyii/Weekyii/...`。代码目录 = `/Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii`。

---

## 1. 现状一句话

魔戒现在是一套「纸 + 墨 + 绿 + 旧金」的中土手抄本皮肤：浅色是**羊皮纸页**，深色是**刚铎蓝灰石室**；卡片是 **6pt 直角纸页 + 1pt 风化石灰线**，按调用方强调色**染纸**；主色是**森林深绿**，旧金只留在红皮封面、VIP 徽记和悬置箱上。

历史脉络（三轮，都记在 `.workbuddy-ai/memory/2026-10-29.md`）：

| 轮次 | 做了什么 | 结果 |
|---|---|---|
| 红皮书 v1（`28149dd` / `2eb84b6`） | 羊皮纸底 + 金边卡片 + 墨线账本行 + 蜡封 + 手绘 glyph | 被用户判「黄不拉几」 |
| 换色板（本轮） | 主色金→森林绿、边框金→石灰、卡片白纸、深色转蓝灰 | 被用户判「还是单调」 |
| 染纸（本轮） | 卡片按 accent 染纸 + 设置页印章上色 + 过去页分色 | 当前状态 |

---

## 2. 代码地图（改这里就够）

### 2.1 令牌层

| 文件:行 | 内容 |
|---|---|
| `Shared/Extensions/Color+Weekyii.swift:6` | `enum WeekTheme`（`.lotr` 是第 16 行） |
| `…:399` | `ThemeHexPair`（AARRGGBB，`.color` 解析） |
| `…:426` | **`ThemeSurfaceSkin`**：卡片/行/特征面共用的面皮肤（圆角、边、填充、阴影、材质、tooling、`tintsWithAccent`） |
| `…:472` | `ThemeRowSkin`（任务行：`barWidth`、`themesBuiltInTypes`） |
| `…:524` | `ThemeFeatureSkin`（红皮书封面：ink/label/action/primaryAction） |
| `…:553` | `ThemeBadgeSkin`（`.waxSeal`） |
| `…:564` | **`ThemeIconSkin`**（设置页印章：圆角、发丝边、填充） |
| `…:584` | `ThemeSectionSkin`（章节标题：`rubric` 首字朱红、`tracking`、`rule`） |
| `…:611` | `ThemeBackdrop`（`.vellum(fibre:vignette:topLight:)`） |
| `…:657` | **`struct ThemeSkin`**：所有令牌的总装 |
| `…:714–802` | **`.lotr` skin 全部参数（改这里影响全局）** |
| `…:1498–1551` | **魔戒 light / dark 调色板** |
| `…:1851` | `Color.weekyiiGilt`（旧金：读 `skin.feature.surface.tooling`，没 tooling 的主题退回主色） |
| `…:2007` | **`Color.weekPaperDye`**（染纸用的提亮：HSB brightness +0.30、saturation ×1.25） |

### 2.2 渲染层

| 文件:行 | 内容 |
|---|---|
| `Shared/Extensions/View+Modifiers.swift:7–134` | **`ThemedSurfaceModifier`**：填充 / 边框 / 边线规则 / tooling / 皮革材质 / 阴影。`tint`+`tintOpacity` 就是染纸层 |
| `…:193` | `WeekyiiCardModifier`（`.weekyiiCard()`） |
| `…:262–281` | **`WeekPageSurfaceModifier`**（`.weekPageSurface(tint:)`） |
| `…:312` | `ThemeBackdropOverlay`（vellum 纤维 + 暗角 + 顶部烛光） |
| `…:425–443` | `themedSurface(_:fallbackFill:tint:tintOpacity:)` / `weekPageSurface(tint:)` 的入口 |
| `…:458–490` | `themedGroupedList()` / `themedListRows()`（设置页 Form 去系统灰） |
| `Shared/Components/WeekCard.swift:26–58` | **卡片主分支**：`useGradient` → feature；否则 `skin.card` + `cardTint`（`accentColor.weekPaperDye`，浅 0.22 / 深 0.18）+ 书签丝带 |
| `Features/Extensions/LiveModuleTile.swift:70–90` | 扩展页模块瓦片：`skin.card` + `currentTint.weekPaperDye` |
| `Shared/Components/TaskRowView.swift:36–41` | 任务行：`skin.row` → `.themedSurface(row.surface)`（透明填充 + 只压脚线） |
| `Shared/Components/LotrGlyph.swift:10` | `enum LotrGlyph`（14 个手绘道具） |
| `…:41–60` | SF Symbol → glyph 映射表（改这里决定哪些图标被替换） |
| `…:299` | `LotrGlyphView`（按 frame 缩放，24pt 网格，`lineWidth 1.6`） |
| `…:338` | `ThemedSymbol`（有对应 glyph 就画手绘，否则回落 SF Symbol） |
| `…:360` | `LotrTabIcon`（把 glyph 渲成 UIImage 给 tabItem） |

### 2.3 页面级特化

| 文件:行 | 内容 |
|---|---|
| `Features/Today/ThemeStatusArtwork.swift:24–25` | 魔戒状态插图入口 |
| `…:1442–1667` | **`LotrStatusIllustration`**：金环 + 火山 + 熔岩 + glint 脉动（15fps `TimelineView`） |
| `Features/Today/TodayView.swift:165` | `.background(todaySceneBackground)`，**在 NavigationStack 内部，已生效** |
| `…:1340–1350` | `todaySceneBackground`：魔戒 → `LotrRainNightBackground` |
| `…:1989–~2100` | **`LotrRainNightBackground`**：深色冷黑渐变 + 山脊 + 冷雨 + 金信标；浅色是 `backgroundPrimary` + `inkMap`（墨线山脉/道路/罗盘，0.38 不透明度） |
| `…:433–460` | 魔戒专属：状态标题、羽毛笔 glyph |
| `…:1656–1773` | `isLotr` 开关：关掉阴影/描边/白色高光 |
| `Resources/SettingsView.swift:2449` | `SettingsSectionHeader`（首字朱红 + 疏排，`textCase(nil)`） |
| `…:2466–2480` | `SettingsNavigationRow`（`themedTint` 参数） |
| `…:3294–3343` | `SettingsIcon`：有 `skin.icon` 时画印章（`.fill` 后缀剥成线稿），否则彩色方块 |
| `Features/Extensions/ExtensionsHubView.swift:1925–1950` | `HubModuleLabel.bookLabel`：模块标题的首字朱红 |
| `App/ContentView.swift:129–130` | tab 图标换手绘 glyph |
| `Shared/Components/WeekLogo.swift:24–40` | 字标：魔戒走 `#F4DFA6→#C9A45C→#8A6630` 金渐变 |
| `Shared/Components/StatusBadge.swift:72` | 蜡封徽章里的状态 glyph |
| `Shared/Components/TaskCard.swift:99–101` | 任务卡图标换手绘 glyph |

### 2.4 传播面（改一个地方会波及多少）

- `skin.card` → `WeekCard`（**约 70 个调用点**，全仓）、`.weekPageSurface()`（过去页所有统计卡）、`LiveModuleTile`（扩展页 4 块瓦片）。**改 card 就是改全 App。**
- `skin.row` → 只有 `TaskRowView`，但 `TaskRowView` 被 `PastView` / `PastDayDetailView` / `ProjectDetailView` / 今日草稿区共用。
- `skin.feature` → 只有 `WeekCard(useGradient: true)`，即今日页焦点卡、项目详情头图。
- `skin.section` → `WeekSectionHeader`（今日页冻结/完成区、扩展页模块标题、设置页分组标题）。

---

## 3. 当前令牌全表（实际值，非设计意图）

### 3.1 `ThemeSkin.lotr`（`Color+Weekyii.swift:714–802`）

| 项 | 值 |
|---|---|
| `typography` | `.classic` → 标题 **serif**，正文 **system sans** |
| `radii` | `nil` → 沿用 8 / 12 / 16 / 24 |
| **`card`** | 圆角 **6**，边 **1pt** `#7C8280` / `#6B7270`（风化石灰），填充 **`#F8F5EC` / `#222724`**，`edges .all`，`ribbonAccent true`，**`tintsWithAccent true`**，无阴影、无 ornament |
| **`row`** | 圆角 0，边 **0.5pt** `#5C7C8280` / `#666B7270`，填充 **透明**，`edges .bottomRule`，色条宽 3 / 圆角 1.5，`themesBuiltInTypes true` |
| **`feature`** | 圆角 8，边 0.5pt `#592A0D06`，阴影 r7 y3 `#4D280C04` / `#8C000000`，**皮革** `#6E2418→#3E120C`（深 `#5E1E14→#2E0D08`），**tooling 旧金 `#B59A62`**，ink `#F2EAD6`，secondaryInk `#D2C0A0`，label 疏排 `#C4A874`，action 胶囊 `#EADFC2`/边 `#8CC4A874`，primaryAction `#C4A874` 底 + `#1B1F1D` 字，`glows false` |
| `badge` | **`.waxSeal`**（蜡封） |
| **`section`** | `count .serif`，rule 石灰 1pt 不渐隐，`showsIcon true`，iconInk/countInk = 墨 `#222724`/`#E8E4D6`，**rubric 首字 `#8A4A38` / `#D29279`**，`tracking 2` |
| `onPrimary` | `#F8F5EC` / `#14171A` |
| **`backdrop`** | **`.vellum`**：fibre `#175C625E` / `#1ABFC8C0`，vignette `#2E4A4C48` / `#59000000`，topLight 透明 / `#1FE0A050`（深色顶部那点暖光就是"烛光"） |
| `softShadows` | **false**（全主题关软阴影） |
| `glyphs` | `.lotr` |
| **`icon`** | 印章：圆角 3，边 0.75pt `#807C8280` / `#8C6B7270`，**无填充**（glyph 颜色由行传入的 `themedTint` 决定） |

### 3.2 调色板（`Color+Weekyii.swift:1498–1546`）

| 角色 | light | dark | 用途 |
|---|---|---|---|
| `primary` | **`#263B30`** 森林深绿 | **`#8FAF9A`** | tab 选中、按钮、空态图标、进度 |
| `primaryLight` | `#3E5A48` | `#AFC9B6` | 渐变、Live Activity keyline |
| `primaryDark` | `#16241D` | `#2C4437` | 按下态 |
| `accentOrange` | **`#9A5A47`** 铁锈 | `#D08F78` | 警示、执行中、截止 |
| `accentGreen` | **`#5E7550`** 苔绿 | `#9CB886` | 完成 |
| `accentPink` | `#8A6F62` | `#B08D7C` | 休闲 |
| `backgroundPrimary` | **`#EDE8DB`** 羊皮纸 | **`#15181A`** 刚铎蓝灰 | 页面底 |
| `backgroundSecondary` | **`#F8F5EC`** 白纸 | **`#222724`** 煤木黑 | 卡片/行底（设置页 List 也用它） |
| `backgroundTertiary` | `#DAD5C6` | `#2C3133` | 凹槽、分隔 |
| `textPrimary` | `#222724` 煤墨 | `#E8E4D6` | 正文 |
| `textSecondary` | `#5C625E` | `#A6ADA9` | 次要 |
| `textTertiary` | `#7C827E` | `#7B827E` | 最弱 |
| `taskRegular` | `#3D5A73` 刚铎蓝灰 | `#8FB4CE` | 普通任务 |
| `taskDDL` | `#9A5A47` | `#D08F78` | 截止任务 |
| `taskLeisure` | `#62764F` | `#A3BE86` | 休闲任务 |

`themedTypeColorHex`（`Color+Weekyii.swift:182`）会把**未被用户改过的**内置任务类型色替换成上面三个，改色要同步改它。

---

## 4. 主题专属资产（重构时优先保留，别推翻）

1. **14 个手绘 glyph**（`LotrGlyph.swift`）——金环、红皮书、地图、水晶瓶、胸针、刺针、末日火山、烟斗、卡兰拉斯、烽火、白树、沙漏、羽毛笔、封蜡信。24×24 网格、圆头线帽，比 SF Symbols 有辨识度。
2. **状态插图**（`ThemeStatusArtwork.swift:1442+`）——金环 + 火山 + 熔岩流 + glint 脉动，全 App 唯一在讲故事的插图。
3. **雨夜/墨线地图背景**（`TodayView.swift:1989+`）——深色冷黑 + 山脊 + 冷雨；浅色墨线山脉 + 虚线道路 + 罗盘。
4. **蜡封徽章**（`badge: .waxSeal`）+ **书签丝带**（`ribbonAccent`）。
5. **首字朱红**（`section.rubric`）——设置页、扩展页模块标题、今日页分区都在用。
6. **字标金渐变**（`WeekLogo.swift:27–34`）。

---

## 5. 已知的坑（会浪费你时间的部分）

### 5.1 构建必须带这个 flag

```bash
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build \
  OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'
```

不带会看到 **1000+ 条 `external macro implementation type ... malformed response`** 和一串「requires that X conform to PersistentModel/Equatable」。那是 `swift-plugin-server` 无法嵌套 `sandbox_apply`，**不是代码错误**，别去改代码。

模拟器是 **iPhone 17 Pro**（本机没有 iPhone 16 Pro）。

### 5.2 测试断言（改令牌要同步改）

`Tests/ModelTests.swift`：

| 行 | 断言 |
|---|---|
| `4132` | `test_themeSkin_lotrDrawsForgedComponents`：校验 `card.edges == .all`、`card.shadow == nil`、`card.ribbonAccent`、`row.edges == .bottomRule`、`feature.surface.material` 是 leather、`feature.surface.tooling != nil`、`badge.kind == .waxSeal`、`section.count == .serif`、`backdrop` 是 `.vellum`、`softShadows == false`、`glyphs == .lotr`、`onPrimary != nil`。**改这些字段必须同步改断言。** |
| `4207` | `test_lotrThemedTypeColor_...`：leisure 类型色写死 `#A3BE86` / `#62764F` |
| `4792` | widget 快照：`darkBackgroundHex "#222724"`、`darkTextPrimaryHex "#E8E4D6"` |
| `4832` | Live Activity 快照：`islandTextPrimaryHex "#E8E4D6"`、`islandKeylineHex "#AFC9B6"`、`darkLockPalette.backgroundHex "#222724"` |

### 5.3 设置页不吃 `skin.card`

`SettingsView` 是 `List(.insetGrouped)`，分组卡是系统画的圆角块，`themedListRows()` 只换了 `listRowBackground`（`Color.backgroundSecondary`）。所以设置页的卡片**圆角比今日页大一圈、也没有石灰边框**。想统一必须动 `List` 样式或逐行补边。

### 5.4 月份条不是卡片

过去页顶部「2026年10月」那条是自绘的白色胶囊，不走 `WeekCard`，所以不染纸、没有石灰边。

### 5.5 主题切换靠重建

`ContentView` 里每个 tab 挂 `.id(visualIdentity)`（`theme-appearance` 组合），切主题会重建整棵子树。所以**不要在视图里缓存 `ThemeSkin.active`**，组件一律读 `@Environment(\.themeSkin)`，否则切换不刷新。

`WeekThemeRuntime.palettePair` 有静态缓存（`cachedPalettePair`），`Color.xxx` 语义色走它。

### 5.6 只改了 `.lotr`

`.classic` 的十个主题（amber/ocean/forest/rose/lavender/graphite/sunset/mint/midnight）`skin` 全部为 `nil`，走 `WeekCard.classicBody` 原路径。**动 `WeekCard` / `ThemedSurfaceModifier` 的默认分支会波及它们**，务必给默认值。

---

## 6. 未做 / 待决策

1. **设置页分组卡没走 `WeekCard`**（见 5.3）——要"整页统一成纸页面板"就得改 `List` 样式，风险最大的一处。
2. **月份条没进皮肤**（见 5.4）。
3. **染纸的强度是拍出来的**：浅 0.22 / 深 0.18，`weekPaperDye` 的 `+0.30 / ×1.25` 也是。没有对比度依据，只有截图目测。要做严谨版本，得按 WCAG 校验「卡片底 vs `textPrimary`」不低于 4.5:1。
4. **金色收缩清单没有落成规则**：现在金出现在封面 tooling、`label`、`primaryAction`、字标、VIP/悬置箱图标印章。没有机制保证「以后不加新的金」。
5. **`ornament`（版框内线）已废弃**，`ThemeSurfaceSkin.ornament` 字段还在、`ornamentLayer` 还在画，只是 `.lotr` 不传值。要么删字段，要么重新设计再用。
6. **`ThemeSkin.radii` 仍是 `nil`**（8/12/16/24），和 6pt 的卡片圆角不同族；同心圆角问题没解。

---

## 7. 怎么验证

### 7.1 快速验证（视觉改动够用）

```bash
# 单元测试（529 个，约 8 秒）
xcodebuild -project Weekyii.xcodeproj -scheme Weekyii \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
  -only-testing:WeekyiiTests OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'
```

**不要无脑跑全量 UI**（23 个用例 ≈ 5–6 分钟，用户明确要求按改动大小挑）。纯配色/间距改动跑单测 + 截图即可。

### 7.2 截图 harness（临时用，拍完删）

往 `WeekyiiUITests/DraftReorderUITests.swift` 末尾追加，跑完 `git checkout -- WeekyiiUITests/DraftReorderUITests.swift` 还原：

```swift
final class TempThemeShotTests: XCTestCase {
    private func shoot(appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "1", "-uiTestingSeedDraft", "1",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-appearanceMode", appearance
        ]
        app.launch()
        let tabs = app.tabBars.buttons
        XCTAssertTrue(tabs.element(boundBy: 0).waitForExistence(timeout: 20))
        let dir = URL(fileURLWithPath: "/tmp/lotr_\(appearance)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (i, name) in ["past", "today", "pending", "extensions", "settings"].enumerated() {
            tabs.element(boundBy: i).tap()
            sleep(3)
            try app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
        }
        app.terminate()
    }
    func test_light() throws { try shoot(appearance: "light") }
    func test_dark() throws { try shoot(appearance: "dark") }
}
```

```bash
xcodebuild ... test -only-testing:WeekyiiUITests/TempThemeShotTests
```

启动参数：`-uiTesting`（内存库）、`-uiTestingSeedDraft`（草稿种子）、`-appearanceMode light|dark`。

### 7.3 采样核对

`xcrun simctl io <dev> screenshot` 后采样页面左边距像素，应等于 `backgroundPrimary`（浅 `#EDE8DB` / 深 `#15181A`）。**卡片会被 accent 染色，同一页不同卡底色不同是正常的**，别以为串色。

### 7.4 验收清单

- 浅色、深色各一套
- 覆盖：今日 / 过去 / 未来 / 扩展 / 设置 + 至少一个详情页
- 装饰性元素对比度 ≥ 3:1，低于要写清为什么允许
- 正文对比度 ≥ 4.5:1

---

## 8. 参考材料

- `docs/reference/README.md` + `docs/reference/open-claude-ui/`（已 `--depth 1` 克隆，MIT，未跟踪）：Claude 桌面端设计系统，183 令牌 / 30 组件。**对 iOS 有用的是**：Surface 0–3 四级微对比、发丝边、同心圆角、`--cds-ease-*` 贝塞尔。**别照搬**：它的 Web 桌面端布局。
- 用户 2026-10-29 给过一份《魔戒》视觉转 UI 的设计参考（森林深绿 / 羊皮纸 / 古旧金 / 风化石灰 / 刚铎蓝灰 / 苔藓绿 / 铁锈红 / 煤木黑 + 六条材质与排版规则）。当前色板就是从它落下来的，四条原则：**自然胜过炫技、历史胜过装饰、秩序胜过堆砌、金必须稀缺**。
