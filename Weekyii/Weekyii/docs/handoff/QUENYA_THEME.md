# 昆雅主题交接

- 独立主题标识 `quenya`；沿用现有主题选择及存储逻辑，不改变会员权限规则（新主题当前为免费）。
- 圣剑是纯装饰，使用状态卡的 bounds anchor 横放在整组内容的背景层，紧邻状态插画下方；状态卡底部渐透、专注卡不透明，卡片和交互位置保持不变。不存在专注任务时不绘制剑。状态插画直接复用现有实现。
- 扩展主页维持原有模块排列：呆胶布用星辉、悬置箱用环纹、习惯用腾格瓦、项目用七星翼冠白树。装饰在卡片背景层，不接收触控或无障碍焦点；空态与有数据状态共用。白树为根据用户确认的预览原创绘制，参考：https://commons.wikimedia.org/wiki/File:Flag_of_the_Kings_of_Gondor.svg；影视造型及相关知识产权需在上线前确认。
- KillTime 火焰继续使用原有 `KillTimeFlameBackground` 与火焰色板，昆雅主题在截止时间卡不可编辑时也保留火焰；过期状态仍保持原有脚注逻辑。
- `sí`（现在）、`lúmë`（时间）是装饰性辅助文字；专注卡文字为昆雅语问候语 *Elen síla lúmenn’ omentielvo* 的腾格瓦转写，不替代操作标签。实际排印及转写应在 iOS 实机和语言专家处复核。
- 字标使用 Cinzel（SIL OFL 1.1，https://github.com/google/fonts/tree/main/ofl/cinzel），腾格瓦使用 Alcarin Tengwar（SIL OFL 1.1，https://github.com/Tosche/Alcarin-Tengwar）。字体许可证随资源附带。剑图为预览阶段生成的透明素材。涉及电影造型、专有名称和相关视觉元素，上线前应自行确认商用及知识产权授权。
- 在 Xcode 中运行 `WeekyiiTests`，并用 `Weekyii Beta` 在浅色和深色、不同文字大小、窄屏及有/无专注任务状态检查圣剑遮挡和火焰。Linux `swiftc -parse` 只能验证语法，不是编译或测试。
