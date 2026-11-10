# TestFlight「测试内容」文案

用于 App Store Connect → TestFlight → 构建版本 → 测试内容。
每次发版替换顶部的版本号，并增删对应模块即可。

当前版本：**1.2 (6)** · 主要语言：简体中文

---

## 简体中文（可直接粘贴）

1.2 (6) 来了。这一版把「外观」做成了一个真正的主题世界——魔戒重做成西界红皮书，猫猫和指环王两个新主题上线；同时把 iCloud 同步又拧紧了一圈。

请通过 TestFlight **直接覆盖更新，不要卸载**。更新后先确认旧数据、旧的主题选择都还在，再往下测。本版不改动数据结构，升级无感过渡。

### 一、魔戒：西界红皮书

魔戒主题整块重做：电影道具感的图标、羊皮纸与皮面材质、蜡封、丝带书签，卡片带四面墨框，任务行回到账本线。

1. 切到「魔戒」，依次看「今日」「本周」「扩展」「过去」「设置」，确认羊皮纸底纹、墨框与书页瓦片都在，不是只换了配色。
2. 切到深色模式，确认是「伊希尔丁之夜」那一套，而不是简单反色。
3. 「今日」页的截止时间火焰、蜡封、状态插图是否协调，有没有压字或错位。
4. 拖动截止时间滑块，火焰应即时跟随，取消后回到原值。

### 二、两个新主题：猫猫 / 指环王

1. 「猫猫」：午睡橘猫主题，检查插图、卡片底色与文字对比度，浅色 / 深色各看一遍。
2. 「指环王」：至尊戒·黑金，黑漆底加单一金色，检查金色描边在深色下是否过亮、浅色下是否发灰。
3. 两个主题都要确认：图标、圆角、阴影确实跟着变，而不只是换色。

### 三、蓝图主题退役

1. 如果你之前选的是「蓝图」，更新后应自动落到「琥珀」，且不再出现在主题列表里。
2. 选别的主题、重启 App，选择应被记住。

### 四、VIP 与内购（沙箱）

这一版是 Beta 配置，**在 TestFlight 里会自动获得 VIP，不需要购买**。所以你会直接看到 VIP 主题和 iCloud 同步可用。

1. 先确认 VIP 状态：设置页「VIP 服务」应显示已开通，七个 VIP 主题（魔戒 / 猫猫 / 指环王 / 粗野 / 霓虹 / 纸感 / 终端）都能直接选。
2. 打开 VIP 页，确认月 / 季 / 年 / 终身四档都显示价格，年订阅标着 2 周免费试用。
3. 想顺带验证购买流程的话，可以走一次沙箱购买（不会真实扣款），确认购买后权益仍然正常、主题不解锁异常。
4. 点「恢复购买」，确认不报错；哪一档没显示价格或没显示试用，截图告诉我是哪一档。

### 五、iCloud 同步（本轮重点）

这一轮修的是「同步不该悄悄弄坏数据」。

1. 两台设备新增 / 编辑 / 删除任务、项目、心印，另一端应自动收敛，不出现重复或回滚。
2. 断开网络改几条，再联网，确认改动补传、没有互相覆盖。
3. 在设置里切换 iCloud 账号：应弹二次确认，切完后本地数据不丢，旧账号的数据不被写进新账号。
4. 带附件的任务在另一台设备应能正常打开（附件按内容哈希校验）。

### 六、数据与覆盖安装（老规矩）

1. 从上一版（1.2 (4) 或 1.2 (5)）覆盖安装：周、日、任务、项目、附件、习惯、设置、主题选择，一个都不该少。
2. 开启 iCloud 的两台设备都覆盖安装，再各自改一次数据，确认双向同步。

### 反馈时请附上

设备型号与系统版本、构建号 1.2 (6)、复现步骤、截图或录屏；若崩溃请附上 TestFlight 的崩溃记录。上一版启动崩溃的修复就在这条链路上，任何闪退都请立刻反馈。

---

## 已知问题（可选，按需保留或删除）

- 蓝图主题已退役，旧选择会自动归到琥珀。
- iCloud 同步属于 VIP 能力，未购买时本地使用不受影响。
- 模拟器与真机的栈大小不同（8 MB vs 1 MB），启动类问题只能靠真机验证。

---

## English (optional — fill if the app ships an English localization)

1.2 (6) is here. This release turns appearance into a real theme world — the Lord of the Rings theme is rebuilt as the Red Book of Westmarch, and two new themes arrive: Catnap and the One Ring. iCloud sync also gets another round of hardening.

Please update **directly over the previous build — do not uninstall**. Confirm your data and theme choice survived, then work through the list. No data-schema changes.

### 1. The Red Book of Westmarch

The Lord of the Rings theme is rebuilt: prop-style glyphs, parchment and leather surfaces, a wax seal, a ribbon bookmark, ink borders on cards, ledger rules back in task rows.

1. Switch to "Ringbearer" and visit Today / Week / Extensions / Past / Settings; parchment, ink borders and page tiles must all be there — not just a palette swap.
2. Switch to dark appearance: it should be the Ithildin night set, not a plain inversion.
3. Check the deadline flame, wax seal and status artwork on Today — no overlapping text, no misalignment.
4. Drag the deadline slider: the flame must follow immediately; cancelling restores the previous value.

### 2. Two new themes: Catnap and Lord of the Rings

1. "Catnap" — a napping ginger cat theme. Check artwork, card surfaces and contrast in both appearances.
2. "Lord of the Rings" — black lacquer with a single gold. Check the gold strokes are neither blown out in dark nor muddy in light.
3. Both must change glyphs, radii and shadows, not only colours.

### 3. Blueprint retired

1. If you had "Blueprint" selected, you should land on "Amber" after updating, and Blueprint should no longer be listed.
2. Pick another theme, relaunch, and confirm the choice persists.

### 4. VIP and purchases (sandbox)

Personalised themes, iCloud sync and Flexible mode are VIP features. Please walk the real purchase flow with a sandbox account.

1. Open the VIP page: monthly / quarterly / yearly / lifetime must all show prices; yearly carries the 14-day free trial note.
2. Buy one plan (sandbox does not charge you) and confirm themes unlock immediately and sync becomes available.
3. Tap "Restore Purchases"; then sign in on a second device with the same Apple Account — the entitlement should follow.
4. If any plan shows no price or no trial, screenshot which one.

### 5. iCloud sync (focus of this release)

1. Create / edit / delete tasks, projects and MindStamps on two devices; both sides must converge with no duplicates or rollbacks.
2. Go offline, make changes, come back online: changes must upload without overwriting each other.
3. Switch the iCloud account in Settings: a second confirmation appears, local data survives, and the old account's data is not written into the new one.
4. Attachments must open on the other device (blobs are verified by content hash).

### 6. Data and over-install (as always)

1. Install over 1.2 (4): weeks, days, tasks, projects, attachments, habits, settings and theme choice — nothing should go missing.
2. On both iCloud devices, install over the previous build, then change data on each side and confirm two-way sync.

### When reporting

Include device model and OS version, build number 1.2 (6), reproduction steps, and screenshots or a screen recording. For crashes, attach the TestFlight crash log. The previous launch-crash fix lives on this same path — report any crash immediately.

---

## 复用说明

- 每次发版先改顶部的「当前版本」，再删掉本版不涉及的模块。
- 若某次只是小修，把正文压缩成 3–5 条要点即可，不要整篇沿用。
- 「已知问题」一段建议保留：能显著减少测试员重复上报已知缺陷。
