# TestFlight「测试内容」文案

用于 App Store Connect → TestFlight → 构建版本 → 测试内容。
每次发版替换顶部的版本号，并增删对应模块即可。

当前版本：**1.2 (7)** · 主要语言：简体中文

---

## 简体中文（可直接粘贴）

1.2 (7) 来了。最重要的一件事：**上一版打不开的问题修好了**——1.2 (5) / (6) 一启动就闪退，这一版可以正常进去了。除此之外，主题世界多了一个新成员「昆雅」，项目详情改成按周看任务，iCloud 同步也补了第五、六两轮。

请通过 TestFlight **直接覆盖更新，不要卸载**。更新后先确认旧数据都还在，再往下走。

**一、先确认能打开（这一版的核心）**
1. 覆盖安装后直接启动，应该正常进入「今日」页，不闪退。
2. 进「设置」，停留几秒，上下滚动，再进出几个子页面——上一版就是崩在这里。
3. 杀掉 App 再启动两次，仍然正常。
4. 如果系统语言是英文，切到英文再走一遍。

**二、昆雅：新主题（VIP）**
一套精灵风格：圣剑横在状态卡下方做背景装饰，卡片上是腾格瓦字母，扩展页四个模块各有纹样（星辉、环纹、腾格瓦、白树），专注卡上有一句昆雅语问候。
1. 设置 → 外观与主题 → 选「昆雅」，逛「今日」「本周」「扩展」「悬置箱」。
2. 看圣剑：只在有任务时出现，压在状态插画下方，不挡字、不接点击；没有专注任务时不应画剑。
3. 切深色模式再看一遍；把系统字体调大，确认圣剑和文字不打架。
4. 进「扩展」，看四个模块的纹样是否都在，空态和有数据时都正常。
5. 截止时间卡上的火焰应该还在，过期后仍按原逻辑显示。

**三、猫猫：午睡橘猫（VIP）**
1. 选「猫猫」，浅色、深色各看一遍，确认文字对比清楚、不发灰。
2. 看卡片底色、插图、图标是否都跟着主题走，而不只是换了个颜色。

**四、主题退役与迁移**
1. 「魔戒」「指环王」已下线，列表里不再出现；如果你之前选的是它们，更新后应自动落到「琥珀」，不白屏、不报错。
2. 「蓝图」同样已退役，旧选择也归到「琥珀」。
3. 重新选一个主题，杀掉 App 再开，选择应被记住。
4. 主题应同步到桌面小组件，颜色一致。

**五、项目详情：改成按周看任务**
1. 打开任意项目详情，现在是「每周任务」：按周分组，点某一天能看到那天的任务。
2. 顶部图例标出「已完成 / 已过期 / 未逾期待办」，确认颜色和实际任务对得上。
3. 在项目里新增、编辑、删除任务，返回再进，数据应一致。
4. 空项目应显示空态和「添加第一个任务」入口。

**六、iCloud 同步（第五、六轮）**
这两轮修的是「同步不该悄悄弄坏数据」。
1. 两台设备新增 / 编辑 / 删除任务、项目、心印，另一端应自动收敛，不出现重复或回滚。
2. 断网改几条再联网，确认改动补传、没有互相覆盖。
3. 在设置里切换 iCloud 账号：应弹二次确认，切完后本地数据不丢，旧账号的数据不会被写进新账号。
4. 带附件的任务在另一台设备应能正常打开。
5. 如果某台设备的同步区域被删掉了（比如在别的设备上重置过），App 应能自己恢复，而不是一直卡在错误状态。

**七、VIP（这一版会自动开通）**
这一版是 Beta 配置，TestFlight 里会自动获得 VIP，不需要购买。
1. 设置页「VIP 服务」应显示已开通；六个 VIP 主题（昆雅 / 猫猫 / 粗野 / 霓虹 / 纸感 / 终端）都能直接选。
2. 免费主题有九个：琥珀、海蓝、森绿、玫瑰、薰紫、石墨、落日、薄荷、极夜。
3. 打开 VIP 页，确认月 / 季 / 年 / 终身四档都显示价格，年订阅标着免费试用。
4. 想顺带验证购买流程，可以走一次沙箱购买（不会真实扣款）；点「恢复购买」不应报错。

**八、设置页观感**
1. 设置页的分组列表应该有主题底色，行与行之间不再是默认灰白。
2. 每个主题下都看一遍，深色模式也要看，确认没有「白底白字」。

**九、数据与覆盖安装（老规矩）**
1. 从上一版覆盖安装：周、日、任务、项目、附件、习惯、设置、主题选择，一个都不该少。
2. 两台开启 iCloud 的设备都覆盖安装，再各自改一次数据，确认双向同步。

反馈时请附上：设备型号与系统版本、构建号 1.2 (7)、复现步骤、截图或录屏；若崩溃请附 TestFlight 的崩溃记录。这一版最重要的是「能不能打开」，任何闪退都请立刻反馈。

---

## English (paste into the English localisation)

1.2 (7) is here. The headline: **the build that would not open is fixed** — 1.2 (5) and (6) crashed on launch, and this one starts normally. On top of that, there is a new theme called Quenya, project details now show tasks week by week, and iCloud sync picks up rounds five and six.

Please update in place through TestFlight — do not delete the app first. After updating, confirm your existing data is intact before working through the list below.

**1. Confirm it opens (the point of this build)**
1. Launch straight after updating; you should land on Today with no crash.
2. Open Settings, stay a few seconds, scroll up and down, then enter and leave a few sub-pages — this is exactly where the previous build died.
3. Force quit and launch twice more; still fine.
4. If your device language is English, run through it in English too.

**2. Quenya: the new theme (VIP)**
A new Elvish visual language: a sword sits behind the status card as decoration, cards carry Tengwar lettering, the four modules on Extensions each get their own motif (starlight, ring pattern, Tengwar, White Tree), and the focus card shows a Quenya greeting.
1. Settings → Appearance & Themes → choose Quenya, then visit Today, This Week, Extensions and the Holding Box.
2. Check the sword: it appears only when there is work, sits under the status artwork, never covers text, and is not tappable. With no focus task, no sword should be drawn.
3. Switch to dark mode and repeat. Raise the system text size and confirm the sword and text do not collide.
4. Open Extensions and confirm all four motifs render, in both empty and populated states.
5. The deadline flame should still be there, with past-due behaviour unchanged.

**3. Catnap (VIP)**
1. Choose Catnap and review it in both light and dark mode; text contrast should stay clear, never washed out.
2. Card surfaces, artwork and icons should all follow the theme — not just the colour.

**4. Retired themes**
1. Ringbearer and Lord of the Rings are gone from the list. If you had one selected, you should land on Amber after updating — no blank screen, no error.
2. Blueprint is retired the same way and also falls back to Amber.
3. Pick a theme, force quit, relaunch — the choice should stick.
4. The home screen widget should follow the same theme.

**5. Project details: tasks by week**
1. Open any project. It now shows Weekly Tasks, grouped by week; tap a day to see that day's tasks.
2. The legend marks completed, overdue and open items — check the colours match reality.
3. Add, edit and delete tasks inside the project, go back and return; data should match.
4. An empty project should show the empty state and an "add first task" entry.

**6. iCloud sync (rounds five and six)**
These rounds were about sync never quietly corrupting your data.
1. On two devices, add / edit / delete tasks, projects and habits; the other side should converge, with no duplicates or rollbacks.
2. Go offline, make a few edits, come back online; changes should upload and nothing should be overwritten.
3. Switch iCloud accounts in Settings: you should get a confirmation prompt, local data must survive, and the old account's data must not leak into the new one.
4. Tasks with attachments should open on the other device.
5. If the sync zone on one device was deleted (for example after a reset elsewhere), the app should recover on its own instead of staying stuck.

**7. VIP (granted automatically in this build)**
This is a Beta-configuration build, so TestFlight testers get VIP without purchasing.
1. Settings → VIP Service should show as active, and all six VIP themes (Quenya, Catnap, Brutal, Neon, Paper, Terminal) should be selectable.
2. Nine themes are free: Amber, Ocean, Forest, Rose, Lavender, Graphite, Sunset, Mint, Midnight.
3. Open the VIP page: monthly, quarterly, yearly and lifetime should all show prices, with a free trial on the yearly plan.
4. If you want to exercise the purchase flow, a sandbox purchase is fine (no real charge); Restore Purchases should not error.

**8. Settings appearance**
1. The grouped list in Settings should carry the theme background instead of the default grey.
2. Check every theme, light and dark, for white-on-white text.

**9. Data and in-place upgrade**
1. Update over the previous build: weeks, days, tasks, projects, attachments, habits, settings and theme choice should all survive.
2. Update on two iCloud devices, then edit on each and confirm two-way sync.

When reporting, include device model and OS version, build number 1.2 (7), reproduction steps, and screenshots or a screen recording. For crashes, attach the TestFlight crash log. Whether it opens at all is the single most important thing in this build — report any crash immediately.
