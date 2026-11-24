# Weekyii iOS 扩展界面视觉改造报告

## 1. 基准与交付状态

- 目标：`online-chatgpt-develop` iOS/iPhone；检查并取用远程提交 `04f8515ae657b784e5e6126cba86f57a19556bae`。
- 代码已推送到 `online-chatgpt-develop`，代码提交 `c88a55aeba828df1514af214ef58614ae321268a`；这份报告作为后续独立文档提交。未创建 PR。
- 设计参考图为上次讨论的第二轮静态设计稿；这是目标方向，不是 SwiftUI 实机截图。
- 本环境为 Linux，无 Xcode、`xcodebuild`、Swift 编译器和 iOS 模拟器，**没有编译、运行 XCTest 或实际截图对照**。不能以静态检查代替 Xcode 编译及运行。

## 2. 代码改动

- `Features/Extensions/HabitsFullView.swift`：今日进度改为大数字加进度条，移除重复且文字较小的圆环；连续天数移到规则信息旁。统计计算、习惯入口和状态保持原样。
- `Features/Extensions/HabitDetailView.swift`：将统计标题从卡片内部调整到外部；保留四项统计、条件显示的“加入今日”和周/月/年历史逻辑。
- `Features/Extensions/ExtensionsHubView.swift`：悬置说明与统计合并，提供直接“分配到某天”的入口，原有菜单和删除确认保留。项目的现有磁贴、尺寸、排序、编辑与状态筛选不移除；新增仅在当前页面有效的“磁贴/轨迹”视图切换。轨迹复用已过滤、按看板顺序排列的项目和现有快照；点按继续进入既有详情。进行中显示下一步，已完成/归档不显示下一步；空项目不显示 0/0 进度。轨迹连线是装饰，不代表时间或项目依赖。
- `Features/Extensions/MindStampListView.swift`：调整文字/图片/时间与操作的层次；保留点击内容编辑、图片原图预览、删除及确认，额外提供显式编辑按钮。
- `Resources/Localizable.xcstrings`：新增 6 条视觉文案的英文、简体中文翻译。
- `WeekyiiUITests/DraftReorderUITests.swift`：新增 `testProjectDisplaySwitchKeepsExistingProjectAndOpensDetail`，覆盖创建空项目、切轨迹、进入详情、返回及切回磁贴；**未运行**。

未修改 `Models/`、`Services/`、SwiftData 模型或 iCloud 逻辑，也未改变进度、逾期、习惯排程和任务生命周期的计算。新增项目视图选择是临时 SwiftUI 状态，重新进入页面后默认为磁贴，不写入数据库或同步。

## 3. 与设计稿的区别及未完成验证

- 原磁贴视图有自己的尺寸、颜色与内容规则，此次优先保留原实现，不会逐像素变成设计图里的磁贴。轨迹视图新增了数据行与连接线，但真实字体、皮肤与系统控件会影响效果。
- 习惯详情保留原有历史组件及日期状态，而不是将静态图直接覆盖。悬置箱的其他任务保留完整原卡片，未压缩为图中极简行；呆胶布删除保留原图标按钮。设计稿中的示例数据不会自动生成。
- 未改造习惯/呆胶布/悬置/项目创建与编辑器的表单和交互，仍使用原有界面；设计稿展示的是列表及习惯详情，不应理解为全部嵌套弹窗均已重绘。
- 在不同主题或深色模式下，项目轨迹行使用现有背景色和项目强调色；是否与特殊主题的卡片皮肤一致，需要人工确认。屏幕尺寸、辅助字体、长名称、键盘、分屏也尚未运行验证。

## 4. 已执行的检查

1. `git diff --check`：通过。
2. `Localizable.xcstrings` 使用 `jq empty` / JSON 解析：通过；新增 6 个 key 均具备 `en` 和 `zh-Hans`。
3. Tree-sitter Swift 对本次修改的 5 个 Swift 文件执行语法解析：未检出 `ERROR` 或缺失节点。它不是 Swift 类型检查或 Xcode 编译。
4. 用基准提交的临时 Git index 执行 `git apply --cached --check`：补丁可应用。
5. 确认变更文件不在 `Models/` 或 `Services/`。

## 5. 本地获取与 Xcode 检查

请先备份工作区并确保没有未提交改动，然后拉取远端分支。`git log` 中应能找到代码提交 `c88a55a`；若本地有未提交改动或 pull 无法快进，先审查，不要强制覆盖。

```bash
git status -sb
git fetch origin
git switch online-chatgpt-develop
git pull --ff-only origin online-chatgpt-develop
git log -4 --oneline
open Weekyii/Weekyii/Weekyii.xcodeproj
```

Xcode 选择共享 scheme `Weekyii`，先 Build，再在可用 iPhone 模拟器上运行测试。可先执行新增的 `WeekyiiUITests/DraftReorderUITests/testProjectDisplaySwitchKeepsExistingProjectAndOpensDetail`；另外运行现有的扩展空态和呆胶布创建、编辑、删除相关测试。若使用命令行，先通过 `xcrun simctl list devices available` 查看设备，再替换下列设备名称：

```bash
xcodebuild test \
  -project Weekyii/Weekyii/Weekyii.xcodeproj \
  -scheme Weekyii \
  -destination 'platform=iOS Simulator,name=替换为可用的 iPhone 模拟器名称' \
  -only-testing:WeekyiiUITests/DraftReorderUITests/testProjectDisplaySwitchKeepsExistingProjectAndOpensDetail
```

### 手工验收清单

- [ ] 习惯：空态、今日有/无计划、完成/待完成/中断/无需、已停用、长名称；详情四项统计、周/月/年切换和“加入今日”出现条件不变。
- [ ] 悬置：总数、7 天内、今日到期与实际数据一致；即将到期/其他分组、到期与已逾期；直接分配与菜单分配、编辑、10/30 天续期、删除确认均正常。若该用户的过期配置会自动处理悬置任务，按其实际设置核验。
- [ ] 呆胶布：空态、纯文字、仅图片、图文、长文字；点击内容和显式编辑均可编辑；点图看原图；删除需确认，取消不删除。
- [ ] 项目：空态；四种磁贴尺寸与自定义列数；编辑、拖拽排序、调整尺寸、删除确认；切轨迹再切回，项目顺序和尺寸不变。
- [ ] 轨迹：进行中/已完成/已归档筛选；零任务、无下一步、有逾期、有下一步日期及长标题；点项目进入同一详情；没有把逾期任务当成下一步。
- [ ] 视觉：与第二轮设计图对照，并检查小屏/大屏、系统大字体、英文、浅色/深色及个性主题；底部导航、系统弹窗与键盘不遮挡操作；VoiceOver 能读出状态与操作。
- [ ] 验证后反馈 Xcode 的具体编译错误、测试日志和对照截图；本次未验证，因此任何实际布局问题均应先修复再合并。
