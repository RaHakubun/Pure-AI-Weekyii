# TestFlight「测试内容」文案

用于 App Store Connect → TestFlight → 构建版本 → 测试内容。
每次发版替换顶部的版本号，并增删对应模块即可。

当前版本：**1.0 (5)** · 主要语言：简体中文

---

## 简体中文（可直接粘贴）

本次更新包含四块内容：**4 个全新个性化主题**、**设置页扩充**、**悬置箱提醒与到期处理**、**本周结构树绘制修复**。请重点测试以下场景。

### 一、4 个全新个性化主题

设置页新增「粗野 / 霓虹 / 纸感 / 终端」四个主题，它们不只是换配色，圆角、描边、阴影和图标形态都不同。

1. 在主题选择处依次切换到这四个主题，确认每个主题的整体观感确实不同，而不是只有颜色变化。
2. 切到新主题后进入「今日」页，查看状态插图；再依次打开「本周」「扩展」「悬置箱」，确认文字与背景对比度清晰、没有看不清的浅色字。
3. 每个新主题都分别在浅色与深色模式下各看一遍。
4. 切换主题后回到桌面查看小组件，颜色应与 App 内一致。
5. 开启「减少动效」后，状态插图与磁贴的动画应全部停止。

### 二、设置页新增项

1. **语言**：新增界面语言选项，切换后需要**完全退出并重新打开** Weekyii 才会生效，请确认提示与实际表现一致。
2. **动效**：新增「减少动效」（停止主题背景、转场、磁贴翻转动画）与「模块磁贴自动轮换」两个开关，改动应立即生效；「减少动效」开启后磁贴轮换也应一并停止。
3. **悬置箱**：新增默认倒计时、到期处理方式、到期提醒（开关 / 强度 / 提前天数 / 当晚提醒时刻）。
4. **项目看板**：新增每行列数（2–6）、默认颜色、默认图标；列数调小后磁贴应变大，宽幅磁贴应自动收窄而不越界。
5. **使用历程**：新增恢复点保留数量。
6. 改完上述设置后，**强制退出 App 再重开**，所有设置应完整保留。

### 三、悬置箱提醒与到期处理

1. 把「到期处理方式」设为**保留为逾期待处理**，让一个悬置任务过期：它应继续留在悬置箱并显示「已逾期 N 天」，且仍可续期 / 分配 / 删除。
2. 改回**到期自动删除**，过期任务应直接消失、不留记录。
3. 把「提醒强度」依次切到精简 / 标准 / 充分，确认实际收到提醒的时机与设置页的描述文字一致。
4. 新建悬置任务时，倒计时默认值应等于设置里的「悬置箱默认倒计时」，且在保存前仍可单独调整。
5. 关闭「到期提醒」后，不应再收到任何悬置任务的到期提醒。

### 四、本周结构树（全屏视图）

1. 打开本周结构树全屏视图：相邻日期的任务卡不应再互相压叠；紧凑日期卡的文字（如「14日 · 2」）不应折行或撞到角标。
2. **请特别留意连线**：连接线不应穿过日期卡、分组节点或任务卡。
3. 轻点某一天，应聚焦到该天的任务子树；不应出现「点了没反应」。
4. 轻点任务卡，应显示任务详情，**不应**显示「任务已遗忘」。
5. 已知限制：一天任务较多（≥4 个）时，子树装不下紧凑画布，需要拖动查看后续行。

### 五、其他改动

1. 扩展页的模块磁贴应每隔几秒轮换展示真实内容；关闭「模块磁贴自动轮换」后应停止轮换。
2. 关闭「开始仪式」后，确认警告提示应直接开始一天，不再弹出印章。
3. 请留意 App 图标已更换。
4. 沿用上一版：iCloud 自动同步请再做一次回归（新建 / 修改 / 删除任务、项目、呆胶布、悬置任务，另一端应自动出现相同变更；带附件的任务在另一台设备应能正常打开）。
5. 从上一版（1.0 构建 4）**直接覆盖安装，不要卸载**：原有周、日、任务、项目、附件与全部设置应完整保留。

### 反馈时请附上

设备型号与系统版本、构建号 1.0 (5)、复现步骤、截图或录屏；若崩溃请附上 TestFlight 的崩溃记录。

---

## 已知问题（可选，按需保留或删除）

- 英文语言环境下，部分新增文案（主题名、设置项）仍显示中文，本地化尚未完成，正在修复中。
- 本周结构树中，一天任务较多时子树需要拖动查看，属当前画布尺寸的物理限制。
- iCloud 同步为自动开启、无开关；未登录 iCloud 时 App 仍可正常本地使用。

---

## English (optional — fill if the app ships an English localization)

This update has four focus areas: **four new personalised themes**, **expanded settings**, **suspended-box reminders and expiry handling**, and **Week Topology drawing fixes**.

### 1. Four new personalised themes

Settings now offers "Brutal / Neon / Paper / Terminal". These change corner radius, borders, shadows and icon form — not just the palette.

1. Switch through all four and confirm each one looks genuinely different, not merely recoloured.
2. Open Today to see the status artwork, then Week / Extensions / Suspended Box — check text contrast is readable everywhere.
3. Check each new theme in both light and dark appearance.
4. Check the home-screen widget matches the in-app theme.
5. With "Reduce motion" on, status artwork and tile animations must stop.

### 2. New settings

1. **Language** — takes effect only after a full quit and relaunch; confirm the hint matches reality.
2. **Motion** — "Reduce motion" and "Module tile auto-rotation"; changes apply immediately, and reduce motion should also stop tile rotation.
3. **Suspended box** — default countdown, expiry policy, due reminders (toggle / intensity / advance days / evening time).
4. **Project board** — columns per row (2–6), default colour, default icon. Fewer columns should enlarge tiles; wide tiles should narrow instead of overflowing.
5. **Usage history** — recovery point retention count.
6. Force-quit and relaunch: every setting must persist.

### 3. Suspended-box reminders and expiry

1. Set the expiry policy to **keep as overdue**: an expired suspended task must stay in the box showing "overdue by N days", still renew / assign / deletable.
2. Switch back to **auto-delete**: expired tasks disappear with no record.
3. Cycle reminder intensity through Minimal / Standard / Full; actual reminder timing must match the description on the settings screen.
4. New suspended tasks must default to the configured countdown, still adjustable before saving.
5. With due reminders off, no suspended-box notifications should arrive.

### 4. Week Topology (full-screen)

1. Task cards for adjacent days must no longer overlap; compact day cards (e.g. "14 · 2") must not wrap or hit the badge.
2. **Watch the connectors specifically**: no line should cross a day card, group node or task card.
3. Tapping a day should focus that day's task subtree — no "nothing happens".
4. Tapping a task card must show task details, **not** "task forgotten".
5. Known limit: with four or more tasks in a day the subtree does not fit the compact canvas and must be scrolled.

### 5. Other changes

1. Extensions module tiles should rotate through real content; turning off auto-rotation stops it.
2. With the start ritual disabled, confirming the warning starts the day directly with no stamp.
3. Note the app icon has changed.
4. iCloud sync regression (unchanged from the previous build): create / edit / delete tasks, projects, MindStamps and suspended tasks on device A — device B must receive the same changes; attachments must open on the other device.
5. **Install over the previous build (1.0 build 4) without uninstalling**: existing weeks, days, tasks, projects, attachments and all settings must be preserved.

### When reporting

Include device model and OS version, build number 1.0 (5), reproduction steps, and screenshots or a screen recording. For crashes, attach the TestFlight crash log.

---

## 复用说明

- 每次发版先改顶部的「当前版本」，再删掉本版不涉及的模块。
- 若某次只是小修，把正文压缩成 3–5 条要点即可，不要整篇沿用。
- 「已知问题」一段建议保留：能显著减少测试员重复上报已知缺陷。
