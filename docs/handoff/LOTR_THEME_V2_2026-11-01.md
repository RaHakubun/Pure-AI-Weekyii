# 魔戒主题 v2：红皮书抄本 / 伊希尔丁之夜（2026-11-01）

只换皮，不动布局：所有页面的结构、间距、交互保持原样。今日页状态插画（金环 + 末日火山，`LotrStatusIllustration`）与截止时间火焰未改。

## 配色（`WeekThemePalettePair.forTheme(.lotr)`）
| 角色 | 浅色 | 深色 |
|---|---|---|
| primary（森林绿 / 精灵鼠尾草） | #263B30 | #A3BFAA |
| backgroundPrimary（羊皮纸 / 刚铎夜石） | #E9DFC8 | #12181E |
| backgroundSecondary（卡片纸） | #F4EEDF | #1B232A |
| textPrimary | #222724 | #E6E0D0 |
| accentOrange / taskDDL（铁锈红） | #805044 | #C98A74 |
| accentGreen / taskLeisure（苔藓绿） | #536448 | #A0B78A |
| taskRegular（刚铎蓝灰） | #26384A | #93AECA |
| 旧金（tooling / gilt） | #B59A62 | #C4A86E |

## 新增皮肤令牌（其他主题均为 nil，行为不变）
- `ThemeSurfaceSkin.ornament`（已有）：魔戒卡片启用，作为地图图框式内衬细线。
- `ThemeFeatureSkin.inscription`：专注封面顶部的精灵文饰带（`ElvishInscriptionBand`，生成的笔画，不是真实文字）。
- `ThemeSectionSkin.ruleEndMark`：分区标题细线末端的一枚小金环。
- `ThemeSkin.gildedFill`：选中控件（今日/本周切换、主按钮、过去月历选中日）改为绿皮面 + 金线，墨色由 `ink` 提供。

## 组件改动
- WeekCard：书签丝带移到左上（13×21，左缩进 18）；专注封面加文饰带并在顶部让出 8pt。
- WeekLogo：魔戒下在字标下方叠加一道极淡的戒文（overlay，不影响尺寸）。
- KillTimeSlider：魔戒下滑块为一枚金戒，尺寸与手势不变。
- 今日背景：浅色墨线地图补安都因河与 ERIADOR / GONDOR / THE SHIRE / MORDOR 地名；深色雨夜底色改为刚铎蓝灰。
- 过去月历：今天描边改旧金，选中日为绿皮面 + 金线。

## 测试
`ModelTests` 中与魔戒色值相关的断言已同步新值；`test_themeSkin_lotrDrawsForgedComponents` 增加对新令牌的断言，并确认其他主题不受影响。需本地 `xcodebuild test` 验证编译与快照。
