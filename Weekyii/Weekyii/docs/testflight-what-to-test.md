# TestFlight「测试内容」文案

用于 App Store Connect → TestFlight → 构建版本 → 测试内容。
每次发版替换顶部的版本号，并增删对应模块即可。

当前版本：**1.2 (1)** · 主要语言：简体中文

---

## 简体中文（可直接粘贴）

1.2 来了，这是一次「看起来完全不一样」的大改版——新主题、新小组件、新 Live Activity，都在这一版。

请通过 TestFlight **直接覆盖更新，不要卸载**。更新后先确认旧数据都还在，再跟着下面的清单体验新东西。本版不改动任何数据结构，升级无感过渡。

### 一、换上你的主题：五个世界，五种脾气

设置页的主题（默认 + 粗野 / 霓虹 / 纸感 / 终端）现在由全新的 ThemeSkin 驱动——圆角、阴影、页面底色、选中态和排版全部跟着主题走，不再是「只换了个颜色」。

1. 依次切换每个主题，逛一遍「今日」「本周」「扩展」「悬置箱」「设置」，感受每个主题独有的气质。
2. 每个主题在浅色、深色模式下各看一遍，确认文字清晰，没有看不清的浅色字。
3. 「今日」页的状态插图全部重绘：切主题时看看它是否跟着变身、有没有错位或残留旧图。
4. 开着「减少动效」的话，插图与磁贴动画应该都静止。
5. 换完主题回到桌面，小组件应该和 App 里一个脾气。

### 二、小组件：放在桌面上的今日全景

主屏和锁屏小组件都重做了。现在小组件上能看到截止时间、日界提示、即将开始的任务和任务类型颜色——不打开 App，一眼知道今天要干什么。

1. 重新添加各尺寸小组件，确认加载正常、没有占位空壳。
2. 把小组件和 App 内「今日」页对照，信息应该一致。
3. 完成一个任务，看小组件是否及时刷新。

### 三、Live Activity / 灵动岛：计时活着，操作不打断

启动一天后，锁屏和灵动岛上的倒计时、时间环会实时走动，临近截止自动变色提醒。更顺手的是：「完成」「移到明天」在灵动岛上点一下就能办，带确认步骤，全程不用打开 App。

1. 启动一天，观察倒计时、时间环实时走动。
2. 依次确认正常 / 即将截止 / 已逾期三种状态；超过截止时间应自动切到逾期态。
3. 直接在 Live Activity / 灵动岛上点「完成」「移到明天」（不要打开 App），然后再打开 App，核对任务状态、队列顺序和统计数字。
4. 留意任务类型的名称、图标、颜色，以及下一个任务和待办数量的显示。

### 四、两个让你更顺的修复

1. 执行队列更稳了：连续完成多个任务、经过 done focus 和 repair，队列不再乱序或重复。
2. 焦点卡的「推迟」「交换」按钮不再中英混杂，跟随 App 当前语言。

### 五、数据与同步（老规矩）

1. 从 1.1 (5) 覆盖安装：周、日、任务、项目、附件、习惯、设置，一个都不该少。
2. iCloud 双设备回归：新建 / 编辑 / 删除任务和项目，另一端应自动同步；带附件的任务在另一台设备能正常打开。

### 反馈时请附上

设备型号与系统版本、构建号 1.2 (1)、复现步骤、截图或录屏；若崩溃请附上 TestFlight 的崩溃记录。这一版好不好看、好不好用，你们说了算。

---

## 已知问题（可选，按需保留或删除）

- 如发现英文环境下个别新增文案仍显示中文，请反馈具体位置，本地化仍在收尾。
- iCloud 同步为自动开启、无开关；未登录 iCloud 时 App 仍可正常本地使用。

---

## English (optional — fill if the app ships an English localization)

1.2 is here — a build that looks completely different. New themes, new widgets, new Live Activity, all in one update.

Please update **directly over the previous build — do not uninstall**. Confirm your old data is intact first, then walk through the list below. No data-schema changes in this build.

### 1. Make it yours: five worlds, five moods

Every theme (default plus Brutalist / Neon / Paper / Terminal) is now driven by a new ThemeSkin — corner radius, shadows, surfaces, selected state and typography all follow the theme, not just the palette.

1. Switch through each theme and visit Today / Week / Extensions / Suspended Box / Settings; feel the personality of each one.
2. Check each theme in light and dark appearance; text must stay readable.
3. The Today status artwork is fully redrawn — watch it transform with the theme, with no misplacement or stale artwork.
4. With "Reduce motion" on, artwork and tile animations must stop.
5. After switching themes, the home-screen widget should match the app.

### 2. Widgets: your day, on the home screen

Home-screen and lock-screen widgets are redesigned. They now show deadline, day boundary, upcoming tasks and task-type colours — a glance is enough to know what today asks of you.

1. Re-add each widget size; they must load with no placeholder content.
2. Compare the widget against the in-app Today screen; information must match.
3. Complete a task and check the widget refreshes promptly.

### 3. Live Activity / Dynamic Island: time that moves, actions that don't interrupt

After starting a day, the lock-screen Live Activity and Dynamic Island tick in real time and shift to a due-soon look as the deadline nears. Best of all: "Done" and "Move to tomorrow" work right from the island, with a confirm step, without ever opening the app.

1. Start a day and watch the countdown, ring and bar move in real time.
2. Confirm normal / due-soon / overdue phases; past the deadline it must switch automatically.
3. Use "Done" and "Move to tomorrow" directly from the Live Activity / Dynamic Island (without opening the app), then open the app and verify task state, queue order and counters.
4. Watch the task type name, icon, colour, next task and pending count.

### 4. Two fixes that make things smoother

1. The execution queue is steadier: order stays stable after completing several tasks and going through done focus and repair.
2. Focus-card "Postpone" / "Swap" buttons follow the app language, no more mixed strings.

### 5. Data & sync (as always)

1. Install over 1.1 (5): weeks, days, tasks, projects, attachments, habits and settings — nothing should go missing.
2. iCloud two-device regression: create / edit / delete tasks and projects; the other device must converge; attachments must open on the other device.

### When reporting

Include device model and OS version, build number 1.2 (1), reproduction steps, and screenshots or a screen recording. For crashes, attach the TestFlight crash log. Whether this build looks and feels right is your call.

---

## 复用说明

- 每次发版先改顶部的「当前版本」，再删掉本版不涉及的模块。
- 若某次只是小修，把正文压缩成 3–5 条要点即可，不要整篇沿用。
- 「已知问题」一段建议保留：能显著减少测试员重复上报已知缺陷。
