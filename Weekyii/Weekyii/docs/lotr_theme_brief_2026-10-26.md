# 魔戒主题设计 brief

- **基线**：`f4e0554`（分支 `notion-claude/feat-in-app-purchase`，已推送）
- **用途**：交给下一位决策者判断「要不要改、改到哪一层」。本文只陈述事实、量化问题、给出目标，不给最终方案。
- **路径约定**：下文 `路径:行号` 均相对仓库根，git 路径写作 `Weekyii/Weekyii/...`

---

## 1. 现状一句话

魔戒是唯一有**自绘 glyph 集 + 专属状态插图**的主题，也是四个个性化主题里**唯一没有任何背景材质**的那个；它靠「给每个卡片描一圈金边 + 内圈细线」来撑起质感。2026-10-26 已去掉四角括号，只留内圈细线。

---

## 2. 代码地图（改这里就够）

| 文件 | 作用 |
|---|---|
| `Weekyii/Weekyii/Shared/Extensions/Color+Weekyii.swift:648-705` | `.lotr` skin 全部参数（一个字典，改这里影响全局） |
| `Weekyii/Weekyii/Shared/Extensions/Color+Weekyii.swift:1400-1447` | 魔戒 light / dark 调色板 |
| `Weekyii/Weekyii/Shared/Extensions/View+Modifiers.swift:22-95` | `ThemedSurfaceModifier`：填充、边框、内圈细线、底层阴影怎么画 |
| `Weekyii/Weekyii/Shared/Extensions/View+Modifiers.swift:240-294` | `ThemeBackdropOverlay`：背景材质（目前只有 paper / terminal / blueprint 用） |
| `Weekyii/Weekyii/Shared/Components/LotrGlyph.swift` | 14 个手绘 glyph（金环、沙漏、黎明、地图、符文石、盾、霜星、铁砧、秘银、精灵叶、火焰、卷轴、蜡烛、日出） |
| `Weekyii/Weekyii/Features/Today/ThemeStatusArtwork.swift:1442+` | 状态卡插图：金环 + 火山 + 熔岩流，带 glint 脉动动画 |
| `Weekyii/Weekyii/Shared/Components/StatusBadge.swift:54-67` | `.ember` 徽章：火焰 glyph + 同色胶囊 + 描边 + 光晕 |

**传播面**：`skin.card` 被 `.weekyiiCard()`、`.weekPageSurface()` 和 `WeekCard`（`Shared/Components/WeekCard.swift:28-31`，非 gradient 分支）消费，约 70 个 `WeekCard` 调用点全部受影响。`skin.row` 只影响任务行，`skin.feature` 只影响渐变特征卡。

---

## 3. 当前参数全表（实际值，非设计意图）

### 卡片 `card`
| 项 | 值 |
|---|---|
| 圆角 | 18 |
| 边框 | 1pt，`#B89A62` / `#6A5530` |
| 填充 | 无（回落到 `backgroundSecondary`） |
| 阴影 | radius 12，y 4，`#1F3A2A22` / `#40000000` |
| 内圈细线 `ornament` | 内缩 3.5pt，0.75pt，`#A8874C` @0.22 / `#D1AD66` @0.22 |

### 任务行 `row`
圆角 12，边框 1pt `#DCCDAE` / `#2B271D`，填充 `#FBF6EA` / `#171612`，色条宽 3.5、圆角 1.75、内置任务类型走主题色。

### 特征卡 `feature`
圆角 18，边框 1.5pt `#D1AD66`，填充 `#1A140D`，边框渐变 `#F0D28F → #9B7638 → #D1693A`，内辉光 `#D15E2C` @0.30（`RadialGradient`，center `.topTrailing`，endRadius 260），阴影 radius 14 `#33D1693A`。
主按钮：胶囊，填充 `#D9B66F`，描边 0.5pt `#F0D28F`，文字 `#1D140A`。

### 其他
- `typography: .classic` → 标题 **serif**，正文 **system sans**
- `radii: nil` → 沿用 8 / 12 / 16 / 24
- `badge: .ember`，`section: 衬线计数 + 金色渐隐分割线 + 显示图标`
- `glyphs: .lotr`
- **`backdrop` 未设 → `.none`（纯色，无材质）**

### 调色板
| | light | dark |
|---|---|---|
| primary | `#8A6A34` | `#C9A45C` |
| primaryLight | `#B58E4B` | `#E2C27E` |
| backgroundPrimary | `#EFE6D2` | `#0A0907` |
| backgroundSecondary | `#F7F0E1` | `#13110D` |
| backgroundTertiary | `#E2D6BC` | `#1C1913` |
| textPrimary | `#231A10` | `#F0E6D2` |
| accentOrange | `#A8452A` | `#E07A4F` |
| accentGreen | `#4F7048` | `#8FAE86` |

---

## 4. 六个问题（按根因排序，带实测对比度）

对比度按 WCAG 相对亮度公式计算，sRGB。

### P1 · 没有材质，所以只能描线
`ThemeSkin.backdrop` 只有三个主题设了值：paper（`:838` `paperGrain`）、terminal（`:872` `scanlines`）、blueprint（`:923` `draftingGrid`）。魔戒走默认 `.none`，背景是**纯色块**。
这不是审美选择，是补偿行为的源头——因为没有纸的纤维、没有金属的颗粒，就只剩「描边」这一个手段能证明「这里有东西」。

### P2 · 装饰参数不区分明暗，层级在两边是反的
| | 外边框 | 内圈细线 |
|---|---|---|
| 浅色 | `#B89A62` on `#F7F0E1` → **2.36:1**（低于 3:1 门槛） | `#A8874C`@0.22 → 合成 `#E6D9C0`，**1.23:1**（等于不存在） |
| 深色 | `#6A5530` on `#13110D` → **2.65:1**（几乎看不见） | `#D1AD66` on `#13110D` → **8.87:1**（比外框亮 3.3 倍） |

深色模式下该当主角的外轮廓最弱、该退二线的内线最亮。**只调数值不改层级，永远对不齐。**

### P3 · 金色承担了结构角色
浅色里出现六种金：`#8A6A34`（primary）、`#B58E4B`（primaryLight）、`#B89A62`（卡片边框）、`#A8874C`（内线）、`#F0D28F`/`#9B7638`（特征卡渐变）、`#D1693A`（特征卡渐变里的橙）。深色再来一套。
金色是「贵」的语义，铺满边框就不贵了。**没有层级 = 没有主角。**

### P4 · 卡片和背景几乎同明度
页面底 `#EFE6D2` 与卡片底 `#F7F0E1` 对比 **1.09:1**。卡片浮不起来，全靠 1pt 金边（2.36:1）和 12pt 阴影撑着，两个都撑不住。这是「整页发灰、糊成一片」的直接原因。

### P5 · 特征卡是个洞
`#1A140D` 对羊皮纸底 `#F7F0E1` 的对比是 **16.1:1**，紧贴在浅色卡片下方，明度差比正文还大。问题不在深，在橙红内辉光 `#D15E2C` @0.30 整块泛红，让它像另一个 App 的卡片。

### P6 · 结构语言是 iOS 卡片，不是书页
圆角 18 + 12pt 阴影 + 1pt 描边 = 「浮起来的卡片」。中土手抄本是一整页纸，靠留白、水平细线、首字下沉分节。用卡片语言讲书页故事，只能用金边硬撑。

---

## 5. 电影《魔戒》的视觉语言 → 可执行规则

不是形容词，是能落到参数上的规则。

### R1 · 材质优先于线条
电影里没有一块纯色平面：锤打铁的凹坑、皮革裂纹、羊皮纸纤维、石头凿痕、苔藓、烟灰、雨渍。
→ UI 上对应的是**低频噪声 + 边缘暗角**，不是等宽描边。参考实现：`ThemeBackdropOverlay` 里新增一个 `case`，Canvas 画稀疏随机短弧（透明度 0.02~0.03）+ 径向暗角（中心透明 → 边缘 6%）。

### R2 · 金是「旧金」，且只在受光面反光
至尊戒在暗处是暗铜色，只有在火里才显出铭文。所以金色必须**局部 + 有方向 + 有明暗渐变**，绝不能是等宽纯色。
→ 金色只留给：当前选中态、关键数字、印章式徽章、字标、分割线。结构（边框）用无彩暖灰。

### R3 · 光有方向，阴影是冷的
电影几乎每个镜头都有明确光源方向；阴影偏冷绿/冷蓝，不是中性灰。
→ 内辉光保持 `.topTrailing`（方向是对的），但透明度要压到 0.10 以内；阴影色从 `#1F3A2A22`（带绿）继续走，不要中性黑。

### R4 · 低饱和，高饱和只占极小面积
绿是苔绿/橄榄，红是锈红/余烬，金是黄铜。高饱和只出现在熔岩、火这种**极小块**上。
→ 现在 `#D1693A`（特征卡渐变里的橙红）和 `#D15E2C`（内辉光）面积太大，是唯一的越界点。

### R5 · 标题是石刻衬线
Trajan 气质：大写、宽字距、锋利衬线。正文用干净的人文衬线。
→ 现状 `typography: .classic` 已经是 `titleDesign: .serif`（`Color+Weekyii.swift:586`），**方向正确，但只有标题生效，正文仍是系统 sans**。可以考虑 `bodyDesign: .serif` 或给 section 标题加 `tracking`。

### R6 · 深色是主场
电影的气质是暗的（摩瑞亚、巴拉多、夜色下的瑞文戴尔）。深色墨底才撑得住金（内线 8.87:1 就是证据），浅色羊皮纸上金天然吃亏（2.36:1）。
→ 需要决策：是「浅色重做成精灵手抄本（冷米白纸 + 墨绿字 + 金只在首字和边饰）」，还是「做成深色专属主题，浅色自动映射到深色变体」。

---

## 6. 已有资产（不要推翻）

这些是这个主题最成功的部分，改造时应当保留：

1. **14 个手绘 glyph**（`LotrGlyph.swift`）——米斯里尔菱形、铁砧、精灵叶、霜星、卷轴，全部 24×24 网格、圆头线帽，比 SF Symbols 有辨识度。
2. **状态卡插图**（`LotrStatusArtwork.swift:1442+`）——金环 + 火山 + 熔岩流 + glint 脉动，是唯一在讲故事的插图。
3. **`.ember` 徽章**——火焰 glyph + 同色胶囊，语义和造型都对。
4. **衬线标题**——`.classic` 的 `titleDesign` 已经是 serif。

---

## 7. 约束与验证

- **改动尽量收敛**在 `.lotr` skin 字典 + `ThemeBackdrop` 新增一个 case + `ornamentLayer`。不要动 `WeekCard` 的 70 个调用点。
- **测试**：`Weekyii/Weekyii/Tests/ModelTests.swift:4132` 的 `test_themeSkin_lotrDrawsForgedComponents` 校验了 `card != nil`、`card.ornament != nil`、`row.themesBuiltInTypes == true`、`badge.kind == .ember`、`section.count == .serif`、`section.showsIcon == true`、`glyphs == .lotr`。改这些字段要同步改断言。
- **构建必须带** `OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'`，否则 Swift 宏全部展开失败，会看到 1000+ 条假错误。
- **验收**：浅色和深色都要截图看；至少覆盖「当下 / 过去 / 未来 / 一个详情页」；装饰性元素对比度不低于 3:1，或明确说明为什么允许低于。

---

## 8. 待决策（留给下一位）

1. **浅色模式的定位**：手抄本，还是深色的弱化副本？
2. **要不要做书页化**（圆角 18 → 4、去掉阴影、改成上下细线）？这是唯一能真正摆脱「iOS 卡片」的改动，但视觉变化最大。
3. **金色收缩到什么程度**？给出「金只出现在 N 个地方」的明确清单。
4. **材质用哪种**：纤维噪声、金属颗粒，还是石刻凿痕？三种气质不同，不能混。
