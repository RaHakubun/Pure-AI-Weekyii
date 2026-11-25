# 任务：新增「猫猫」付费主题（线条画 · 可爱慵懒）

> 这份文件是给编码 Agent 的完整任务书。所有路径、行号、类型名都已在当前 HEAD（`17105cf`）核对过。
> **不要重新调研架构**，直接按下面的清单执行；有疑问先读对应文件，不要凭猜测改。

---

## 0. 目标与硬边界

**要做**：在 Weekyii 里新增第 15 个主题 `cat`（中文「猫猫」，英文 `Catnap`），作为 **VIP 付费主题**。
视觉语言是**手绘猫线条画**：单色描边、圆头端帽、无填充、24×24 网格，像随手画在本子上的猫。
气质是**可爱慵懒**——趴着、蜷着、打哈欠、伸懒腰，不是机灵的卡通猫，也不是写实插画。

**硬边界（违反即返工）**：

1. **只换皮，不动布局**。不改任何页面的结构、间距、层级、交互。参考 `docs/handoff/LOTR_THEME_V2_2026-11-01.md` 的自我约束。
2. **不用图片资源**。全部用 SwiftUI `Path` / `Shape` 画，不加 PNG/SVG/PDF 到 `Assets.xcassets`。
3. **其它 14 个主题必须零变化**。特别是 `ThemeSkin.classic` 的任何断言、`WeekTheme.lotr` 的任何值。
4. **不改 `ThemeVisualStyle` 枚举**。`cat` 的 `visualStyle` 返回 `.classic`（该枚举只服务经典主题的圆角/阴影体系，猫猫靠 `ThemeSkin` 令牌）。
5. **不改 `isPremiumTheme`**。它只驱动魔戒的专属渐变边框（`View+Modifiers.swift:209-251`），猫猫不需要。
6. 不提交、不推送。改完停在工作区，交报告。

---

## 1. 现有架构速览（照这个接，别自创）

主题 = **调色板**（`WeekThemePalettePair.forTheme`）+ **皮肤令牌**（`ThemeSkin`）+ **印象画**（`ThemeStatusArtwork`）+ **可选的手绘图标集**（`ThemeGlyphSet`）。

组件读令牌、不 switch 主题。`nil` 令牌 = 「按经典方式画」。所以新增主题的正确做法是**填令牌**，不是去改组件。

`skin.card != nil` 是分水岭：非 nil 时 `weekyiiCard()` 走皮肤路径（`View+Modifiers.swift:200-205`），nil 时走原经典路径。

---

## 2. 逐文件改动清单

### 2.1 `Weekyii/Weekyii/Shared/Extensions/Color+Weekyii.swift`（主要战场，2199 行）

**(a) `WeekTheme` 枚举（`:6-24`）** — 在 `case terminal` 之后、`case blueprint` 之前加：

```swift
case cat
```

放在 `blueprint` 之前，`allCases` 顺序就是选择器顺序。

**(b) `displayName`（`:31-49`）** — 加：

```swift
case .cat: return String(localized: "theme.cat.name", defaultValue: "猫猫")
```

**(c) `visualStyle`（`:58-73`）** — `cat` 归到 `.classic` 那一行的 case 列表里。

**(d) `skin`（`:718-731`）** — 加 `case .cat: return .cat`。

**(e) `WeekThemePalettePair.forTheme`（`:1116` 起的 switch）** — 加 `case .cat:`，返回 20 个字段的浅/深两套配色。
建议起点（可微调，但**必须**满足对比度：`textPrimary` 对 `backgroundPrimary` ≥ 7:1，`textSecondary` ≥ 4.5:1）：

| 角色 | 浅色 | 深色 |
|---|---|---|
| primary（奶茶棕） | `#8A6A55` | `#D3B49B` |
| primaryLight | `#A8866E` | `#E4CBBA` |
| primaryDark | `#5E463A` | `#8A6A55` |
| accentOrange（三文鱼粉） | `#D98E7B` | `#E8A795` |
| accentGreen（薄荷） | `#7E9A7B` | `#A6BFA2` |
| accentPink（樱粉） | `#D98BA6` | `#E8A9BF` |
| backgroundPrimary（奶油纸） | `#F7F1E8` | `#16130F` |
| backgroundSecondary（卡片） | `#FFFBF4` | `#211C17` |
| backgroundTertiary | `#EFE6D9` | `#2C2620` |
| textPrimary（墨棕） | `#2E2620` | `#F0E7DA` |
| textSecondary | `#63564B` | `#C2B3A3` |
| textTertiary | `#95836F` | `#93816F` |
| taskRegular / Bg | `#4A6B7C` / `#DDE7EC` | `#93B6C9` / `#1B2A33` |
| taskDDL / Bg | `#B5644E` / `#F3DED6` | `#E29279` / `#35211B` |
| taskLeisure / Bg | `#7E6BA8` / `#E8E2F3` | `#B3A2D6` / `#2A2438` |

**(f) `extension ThemeSkin` 末尾（`:1068` 的 `}` 之前）** — 新增 `static let cat: ThemeSkin = { ... }()`。
参考 `.lotr`（`:746-846`）的写法与注释密度：每个非 nil 令牌都要有一行说明「为什么」。

必填令牌与猫猫的落点：

| 令牌 | 取值 | 画什么 |
|---|---|---|
| `typography` | `.classic` | 系统衬线标题，别换字体（猫靠画，不靠字体卖萌） |
| `radii` | `nil` | 保留 8/12/16/24 |
| `card.surface` | 圆角 10、1pt 边、`edges: .all`、`fill` 用卡片纸色 | 卡片是一张纸，边线是铅笔线 |
| `card.ornament` | `ThemeHexPair`（比边线淡一档） | **第二道内衬线**。若想改成「爪印小点阵」，需在 `ThemeSurfaceSkin` 新增一个 `pawMarks: ThemeHexPair?` 令牌并在 `WeekCard.swift` 的内衬绘制处加分支；不想加令牌就保留内衬线 |
| `row.surface` | 圆角 8、0.75pt 边 | 任务行是一张便签 |
| `row.barWidth` / `barCornerRadius` | 3 / 1.5 | 任务类型色条，圆头像猫尾巴 |
| `feature.surface` | 圆角 12、1pt 边、`fill` 用更暖的奶油色 | 专注面板是猫窝 |
| `feature.inscription` | `ThemeHexPair` | **一条蜷着的尾巴曲线**横贯封面顶部（照魔戒精灵文的做法，纯装饰、不是文字） |
| `badge.kind` | 新增 `.catEars`（见 2.3）或退回 `.stamp` | 状态徽章长一对小耳朵 |
| `section.rule` / `ruleWidth` | 1 / 1 | 分区标题下的细线 |
| `section.ruleEndMark` | `ThemeHexPair` | **线末端一枚小爪印**（照魔戒的金环，`WeekCard.swift:449` 已有绘制点） |
| `section.count` | `.plain` | 计数不加修饰 |
| `onPrimary` / `onSuccess` | 深色文字 | 保证填充上的对比度 |
| `backdrop` | 新增 `.pawTrail(ThemeHexPair)`（见 2.2） | 页面上散落极淡的爪印 |
| `softShadows` | `true` | 猫是软的，保留柔和阴影（与魔戒相反） |
| `glyphs` | `.cat` | 见 2.2 |
| `icon` | 圆角 7、无填充、`border` 淡一档 | 设置行图标改成描边小方框 |

**(g) `ThemeGlyphSet`（`:634-637`）** — 加：

```swift
/// Hand-drawn cat line art (猫猫), see `CatGlyph`.
case cat
```

**(h) `ThemeBackdrop`（`:639-650`）** — 加：

```swift
/// Sparse paw prints scattered across the page (猫猫).
case pawTrail(ThemeHexPair)
```

绘制点：`Shared/Extensions/View+Modifiers.swift` 里 backdrop 的 switch（搜 `case .vellum`），照 vellum 的写法加分支——用 `Canvas` 或 `Path` 按固定种子撒 20～30 个爪印，透明度极低（浅色 ≤ 6%，深色 ≤ 5%），**不能影响文字可读性**。

**(i) `ThemeBadgeKind`（`:563-577`）** — 加：

```swift
/// A rounded tag with two cat ears on top (猫猫).
case catEars
```

绘制点：`Shared/Components/StatusBadge.swift:54` 附近（`case .waxSeal:` 旁边）。耳朵用两条 `Path` 三角形/圆弧，颜色取状态色，尺寸不超过徽章高度的 30%。

---

### 2.2 新建 `Weekyii/Weekyii/Shared/Components/CatGlyph.swift`

照 `Shared/Components/LotrGlyph.swift`（现有 400 行）的结构写，**不要抄内容，抄结构**：

```swift
enum CatGlyph: String, CaseIterable {
    case loaf        // 趴着的猫（正面，两只前爪收在身下）
    case curl        // 蜷成一团睡觉
    case stretch     // 伸懒腰（前低后高）
    case yawn        // 打哈欠（张嘴，眼睛闭成 ^ ^）
    case paw         // 单只爪印
    case tailCurl    // 卷尾巴
    case yarnBall    // 毛线球
    case fishBone    // 鱼骨
    case cushion     // 猫窝坐垫
    case saucer      // 牛奶碟
    case box         // 纸箱
    case whisker     // 三根胡须

    /// 调用点传进来的 SF Symbol 名 → 本套图标
    init?(systemName: String) { ... }

    /// 内置任务类型（regular / ddl / leisure）
    init?(builtInType kind: TaskType, iconName: String) { ... }

    /// 日状态徽章里的图形
    init(status: DayStatus) { ... }
}

/// 24×24 网格，1.5pt 描边，圆头端帽，跟随前景色。
struct CatGlyphView: View { ... }
```

映射建议（照 `LotrGlyph.init?(systemName:)` 的写法，`default: return nil`）：

| SF Symbol | CatGlyph | 理由 |
|---|---|---|
| `target` / `sun.max` | `.loaf` | 今日/专注 = 趴着 |
| `clock` / `hourglass` | `.saucer` | 时间是喝奶的工夫 |
| `clock.arrow.circlepath` | `.curl` | 过去 = 睡着的一团 |
| `calendar` | `.cushion` | 周/月 = 猫窝 |
| `square.grid.2x2` | `.box` | 扩展 = 纸箱（猫最爱） |
| `gearshape` | `.whisker` | 设置 = 胡须 |
| `checkmark.circle` | `.stretch` | 完成 = 伸个懒腰 |
| `flame` | `.yawn` | 截止 = 打哈欠（不制造压力） |
| `leaf` | `.yarnBall` | 休闲 = 玩毛线 |
| `snowflake` | `.curl` | 冻结 = 睡着 |

`init?(builtInType:iconName:)`：`regular → .paw`、`ddl → .fishBone`、`leisure → .yarnBall`。
`init(status:)`：`empty → .curl`、`draft → .yawn`、`execute → .loaf`、`completed → .stretch`、`expired → .curl`。

**线条画规格（所有 glyph 必须一致）**：

- 画布 24×24，内容留 2pt 内边距（有效区 20×20）
- 描边 `lineWidth: 1.5`，`lineCap: .round`，`lineJoin: .round`
- 只用 `stroke`，**不用 `fill`**（眼睛除外：两个 1.2pt 的实心点，或闭眼画成两段 `^` 弧）
- 颜色一律 `foregroundStyle`，**不写死 hex**，这样徽章/图标/正文里都能用
- 单条路径尽量少拐点，笔画要有手绘的轻微不规整（坐标允许 ±0.3 的偏差，别用完美几何）

---

### 2.3 `Weekyii/Weekyii/Shared/Components/StatusBadge.swift`

在 `case .waxSeal:`（`:54`）旁边加 `case .catEars:` 分支。徽章本体保持现有圆角矩形/胶囊，只在顶边画两只耳朵（两条 `Path`，尖朝上，与徽章同色描边、同色填充或纯描边），**不要改变徽章尺寸**，否则会挤动状态栏布局。

---

### 2.4 `Weekyii/Weekyii/Features/Today/ThemeStatusArtwork.swift`

三处改动：

**(a) 顶部 `body` 的 switch（`:19-31`）** — 加：

```swift
case .cat:
    CatStatusIllustration(renderingMode: renderingMode)
```

**(b) `NarrativeThemeStatusIllustration.scene`（`:97-119`）** — 那个 `case .sunset, .lotr, .brutal, ...: Color.clear` 列表里加 `.cat`（否则编译报 switch 不穷尽）。

**(c) 文件内新增 `private struct CatStatusIllustration`** — 照 `LotrStatusIllustration`（同文件内）的两态写法：

- `renderingMode == .animated && !reduceMotion` 时用 `TimelineView(.animation(minimumInterval: 1.0 / 15.0))`，否则固定 `time: 0`
- 画面内容：**一只趴在窗台上的猫**，窗框是细线，窗外用淡色块表示天色；猫随呼吸微微起伏（`sin(time * 0.6)` 缩放 0.98～1.02），尾巴每 4 秒轻摆一次
- 只用线条与极淡色块，不写实、不加纹理图片
- 必须 `.accessibilityHidden(true)`（外层已有，新增 view 内部不要再加）

---

### 2.5 `Weekyii/Weekyii/Features/Today/TodayView.swift`

**(a) `todaySceneBackground`（`:1339-1352`）** — 在 `else if userSettings.selectedTheme == .lotr { ... }` 之后加：

```swift
} else if userSettings.selectedTheme == .cat {
    CatNapBackground(animationsActive: animationsActive)
        .transition(.opacity)
```

**(b) 文件底部新增 `private struct CatNapBackground`** — 照 `LotrRainNightBackground`（`:2003`）的签名与动画开关写法。画面：页面下缘一条极淡的地毯线，一只猫的剪影蜷在右下角，缓慢呼吸；`animationsActive == false` 时完全静止。

---

### 2.6 `Weekyii/Weekyii/Resources/SettingsView.swift`

**(a) `markArtwork`（`:2609-2627`）** — 加 `case .cat: catMark`（在 `case .terminal` 之后、`case .blueprint` 之前）。

**(b) 新增 `private var catMark: some View`** — 30×30 空间，照 `lotrMark` / `paperMark` 的写法（`:2629` 起的注释说明了约定：固定 hex 是刻意的，取主题标志色，保证明暗两种模式下都读得出来）。画面建议：奶油底 + 一只趴着的猫线条 + 右下角一个爪印。

**(c) 不用改主题列表**。`ForEach(WeekTheme.freeThemes)`（`:591`）和 `ForEach(WeekTheme.vipThemes)`（`:601`）会自动带上 `cat`——只要 2.7 做对。

---

### 2.7 `Weekyii/Weekyii/Services/PurchaseService.swift`

`requiresVIP`（`:52-59`）的 case 列表加 `.cat`：

```swift
case .lotr, .cat, .brutal, .neon, .paper, .terminal:
    return true
```

这是**唯一的付费闸门**。`vipThemes` / `freeThemes`（`:61-62`）会自动过滤，`resolvedTheme`（`Color+Weekyii.swift:211`）会自动在未解锁时回退到 `.amber`。

---

### 2.8 `Weekyii/Weekyii/Resources/Localizable.xcstrings`

加 1 个 key，`en` 与 `zh-Hans` 都要 `"state" : "translated"`：

| key | zh-Hans | en |
|---|---|---|
| `theme.cat.name` | 猫猫 | Catnap |

格式照现有 `theme.lotr.name` 条目。**不要用 xcodebuild 自动生成**——命令行构建不会把 `.stringsdata` 合并回 catalog，必须手写。

---

### 2.9 测试 `Weekyii/Weekyii/Tests/ModelTests.swift`

**必须改的既有断言（不改就红）**：

| 位置 | 现状 | 改成 |
|---|---|---|
| `:2651 test_vipThemesAreTheFiveDedicatedThemes` | `Set(vipThemes) == [.lotr, .brutal, .neon, .paper, .terminal]` | 改名 `test_vipThemesAreTheSixDedicatedThemes`，集合加 `.cat` |
| `:4155` `for theme in WeekTheme.allCases where theme != .lotr` | 断言 `gildedFill` / `inscription` 为 nil | 猫猫也有 `inscription`，改成 `where ![.lotr, .cat].contains(theme)` |
| `:4169` 同上循环 | 断言 `glyphs == nil`、`themesBuiltInTypes != true` | 同上排除 `.cat`；`themesBuiltInTypes` 猫猫设为 `true`（要用自己的任务类型图标） |
| `:329` `Array(allCases.prefix(7))` / `suffix(7)` | 15 个 case 后第二批只剩 7 个以外的 1 个 | 改成 `prefix(8)` / `suffix(7)`，或按 `isSelectable` 分组 |

**必须新增的用例**：

1. `test_themeSkin_catDrawsLineArtComponents`
   断言：`skin != .classic`、`card != nil`、`row != nil`、`feature?.inscription != nil`、`section?.ruleEndMark != nil`、`badge?.kind == .catEars`、`softShadows == true`、`glyphs == .cat`、`icon != nil`、`backdrop` 是 `.pawTrail`。
   并断言**其它主题没被污染**：`for theme in allCases where ![.lotr, .cat].contains(theme)` 时 `glyphs == nil`、`badge?.kind != .catEars`。

2. `test_catThemeRequiresUnlock`
   断言 `resolvedTheme(rawValue: "cat", premiumThemeUnlocked: false) == .amber`、`true` 时 `== .cat`，且 `WeekTheme.vipThemes.contains(.cat)`。

3. `test_catGlyphCoversEveryCallSite`
   逐条断言 `init?(systemName:)` 的映射、`init?(builtInType:iconName:)`、`init(status:)`，并断言未映射的 symbol 返回 `nil`（照 `:4161-4167` 魔戒那几条的写法）。

4. `test_catGlyphsAreDistinctLineArt`
   断言 12 个 glyph 的 `rawValue` 唯一、`allCases.count == 12`——防止有人复制粘贴时漏改。

---

## 3. 验证要求（按这个顺序，别跳）

```bash
cd /Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii

# 1) 编译（必须带这个 flag，否则所有宏展开失败，会报上千条假错误）
xcodebuild build -project Weekyii.xcodeproj -scheme Weekyii \
  -destination 'platform=iOS Simulator,id=78AEA02E-5B71-4BDB-87F8-EA0F844EB8CC' \
  OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'

# 2) 全量单元测试（当前基线 548 例，加完应该 552 左右，0 失败）
xcodebuild test -project Weekyii.xcodeproj -scheme Weekyii \
  -destination 'platform=iOS Simulator,id=78AEA02E-5B71-4BDB-87F8-EA0F844EB8CC' \
  -only-testing:WeekyiiTests \
  OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'
```

**变异验证（必须做，报告里写结果）**：

- 把 `requiresVIP` 里的 `.cat` 删掉 → `test_catThemeRequiresUnlock` 与 `test_lockedVIPThemeFallsBackToAmberAndKeepsChoice` 必须失败
- 把 `skin` switch 里的 `case .cat: return .cat` 改成 `return .classic` → `test_themeSkin_catDrawsLineArtComponents` 必须失败
- 改完立刻还原，`grep -rn "MUTATION" Weekyii/` 必须零命中

**截图核对**（`xcrun simctl io booted screenshot`，浅色 + 深色各一套）：

1. 今日页：印象画、页面底色、状态徽章、分区标题末端爪印
2. 设置 → 外观与主题：VIP 分区里能看到「猫猫」、mark 图标正常、未解锁时点了会回退琥珀
3. 过去页 / 未来页：卡片边线与内衬正常，没有串色
4. 专注面板：封面尾巴曲线、按钮可读

---

## 4. 交付物

1. 代码改动（按第 2 节的顺序）
2. `Weekyii/Weekyii/docs/handoff/CAT_THEME_<日期>.md`：照 `docs/handoff/LOTR_THEME_V2_2026-11-01.md` 的格式写——配色表、新增令牌、每个组件改了什么、测试结果、变异验证结果
3. 报告里明确写：**哪些是有意的取舍**（例如「没有为爪印底纹加新令牌，复用了内衬线」）、**哪些没做**（例如「小组件未做猫猫专属版式」）

---

## 5. 常见坑（都踩过）

- **`xcodebuild` 不带 `-Xfrontend -disable-sandbox` 会报上千条宏错误**，那不是代码问题，别去改代码。
- **`WeekTheme` 加 case 会连锁触发 6 处 switch 不穷尽**：`displayName`、`visualStyle`、`skin`、`palettePair.forTheme`、`ThemeStatusArtwork.body`、`NarrativeThemeStatusIllustration.scene`。编译错误会全部列出来，按报错改即可。
- **`settings.theme.vip.footer.locked` 文案写的是「到期后会切回琥珀主题」**，对猫猫同样成立，不用改。
- **`WeekyiiWidget/` 不引用 `WeekTheme`**，小组件通过快照拿 hex，所以不用动 Widget target。但发版前要确认 `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` 在 App 与 Widget 两处一致。
- **`ModelTests:4155/4169` 的 `where theme != .lotr` 循环是最容易被忽略的红灯**，加完主题先跑测试再看这两个。
