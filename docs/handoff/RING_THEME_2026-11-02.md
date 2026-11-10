# 指环王主题（ring）交接 · 2026-11-02

新增付费主题 `WeekTheme.ring`「指环王」，方向 A「至尊戒·黑金」：黑漆 + 单一金色。
**魔戒（lotr）完全未改动**，两套主题并存。VIP 主题由 6 套变为 7 套。

> 本分支在无 Swift 编译器的环境中完成，**未编译、未跑测试**。请先 `xcodebuild build` + `xcodebuild test`。

## 色板
| Token | 浅色 | 深色 |
|---|---|---|
| 页面 / 卡片 / 三级 | #ECE5D6 / #F7F2E7 / #E0D7C4 | #0F0E0C / #1A1815 / #25221D |
| 线 | #8C8475 | #3E392F |
| 文字 1/2/3 | #1E1B17 / #5E584E / #8D8679 | #EDE4D0 / #B5AA93 / #7E7565 |
| 黑漆 | #342E27 → #16130F | #2E2820 → #0B0A08 |
| 金 高/中/低（`RingGilt`） | #D9C08A / #A8874F / #7E6232 | #E8D29C / #C9AD72 / #8C7240 |
| 朱批 rubric | #8A6B35 | #D4B77A |
| 任务 常规/DDL/休闲 | #3A4E66 / #9A4A34 / #5E6E4E | #9AB0C8 / #D99478 / #A9BA92 |
| 余烬 ember（只用于火光，不做填充） | #D2643A | #E0784A |

## 规则
- 圆角 4/6/8/10：卡片 8，专注面板 10，按钮/分段 8，任务章 6。
- 卡片：书签丝带挂在**右上**（`ribbonTrailing`，距右 48pt）。
- 任务行：底部细线 + 30pt 方章（类型色 8% 填充 + 35% 描边 + 中土纹样），行本身不染色。
- 专注面板：黑漆皮面 + 金线压边；按钮为圆角矩形 `.roundedRect`。
- 滑块：6pt 轨道，浅色填黑漆、深色填金；拇指为纸色椭圆 + 3.4pt 金圈。
- Logo：衬线斜体单金渐变，无铭文。
- 今日背景 `RingStudyBackground`：浅色羊皮纸 + 下三分之一墨线山脉/古道/罗盘；深色顶部烛光 + 淡金地图线。
- 状态插画 `RingStatusIllustration`：墨线地图、至尊戒、末日火山余烬呼吸（尊重减弱动态）。

## 新增通用 token（默认值保持其他主题原样）
- `ThemeSurfaceSkin.ribbonTrailing`
- `ThemeRowSkin.chipSize / chipCornerRadius / chipFillOpacity / chipBorderOpacity / rowWashOpacity`（默认 = 猫猫原值 32/11/0.16/0/0.07）
- `ThemeActionKind.roundedRect`、`ThemeGlyphSet.ring`、`ThemeSkin.drawsMiddleEarthGlyphs`（lotr 或 ring）

## 涉及文件
Color+Weekyii.swift、PurchaseService.swift、WeekCard.swift、TaskRowView.swift、KillTimeSlider.swift、WeekLogo.swift、
TodayView.swift、ThemeStatusArtwork.swift、SettingsView.swift（ringMark）、LiveModuleTile.swift、ContentView.swift、
ExtensionsHubView.swift、LotrGlyph.swift、TaskCard.swift、Localizable.xcstrings（theme.ring.name）、ModelTests.swift。

## 真机检查点
1. 今日/本周分段控件圆角（6/8）是否和卡片一致。
2. 丝带在右上，不压标题右侧的计数/按钮。
3. 任务方章 30pt 是否与标题基线居中。
4. 状态插画在深浅色下的对比度、余烬呼吸是否过亮。
5. 设置页主题列表出现「指环王」，未解锁时回退 amber。
