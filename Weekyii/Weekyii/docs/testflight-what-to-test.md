# TestFlight「测试内容」文案

用于 App Store Connect → TestFlight → 构建版本 → 测试内容。
每次发版替换顶部的版本号，并增删对应模块即可。

当前版本：**1.0 (4)** · 主要语言：简体中文

---

## 简体中文（可直接粘贴）

本次更新包含两块内容：**扩展页磁贴改版** 与 **iCloud 自动同步**。请重点测试以下场景。

### 一、扩展页磁贴

1. 进入「扩展」页，首页三块模块磁贴（呆胶布 / 悬置箱 / 项目）会每隔几秒自动轮换展示真实内容，请确认切换流畅、内容与各模块实际数据一致。
2. 点进「项目」，长按任意磁贴进入编辑态：
   - 拖动磁贴调整顺序，松手后顺序应保持（退出重进不还原）；
   - 点右下角缩放按钮循环切换磁贴尺寸（迷你 / 小 / 中 / 宽），切换后磁贴之间不重叠、不遮挡；
   - 点左上角减号删除项目，确认弹窗应有「仅删除项目」和「连同任务一起删除」两个选项。
3. 在非编辑态轻点磁贴应进入项目详情。请特别留意：**长按进入编辑态后松手，是否会误跳进详情页**。
4. 切换顶部「进行中 / 已完成 / 已归档」筛选，确认磁贴列表与项目状态一致。

### 二、iCloud 自动同步

> 前置条件：请使用同一个 Apple ID 登录 iCloud，最好准备两台设备（如 iPhone + iPad）互测。

1. 设置页的「iCloud 同步」应正确显示当前状态：正在检查 / 已开启 / 正在同步 / 已同步 / 请先登录 iCloud / 同步遇到问题。
2. 设备 A 新建、修改、删除任务、项目、呆胶布、悬置任务，设备 B 应自动出现相同变更（反向再测一次）。
3. 带图片或文件附件的任务，在另一台设备上应能正常打开附件。
4. 一台设备断网操作，恢复网络后应自动补传，数据不丢失。
5. 两端同时离线为同一天各建任务，联网后双方任务都应保留。
6. **从上一版（1.0 构建 2）直接覆盖安装，不要卸载**：原有周、日、任务、项目、附件应完整保留。
7. 注意：**通知、默认截止时间、执行模式、主题、默认项目时长**属于设备本地设置，**不会**同步，这是预期行为。

### 反馈时请附上

设备型号与系统版本、构建号 1.0 (4)、复现步骤、截图或录屏；若崩溃请附上 TestFlight 的崩溃记录。

---

## 已知问题（可选，按需保留或删除）

- 英文语言环境下，扩展页部分文案仍显示中文，尚未完成本地化，正在修复中。
- iCloud 同步为自动开启、无开关；未登录 iCloud 时 App 仍可正常本地使用。

---

## English (optional — fill if the app ships an English localization)

This update has two focus areas: **redesigned Extensions tiles** and **automatic iCloud sync**.

### 1. Extensions tiles

1. Open the Extensions tab. The three module tiles (MindStamps / Suspended / Projects) rotate through real content every few seconds — check that the transitions are smooth and the content matches each module's actual data.
2. Tap into Projects, then long-press a tile to enter edit mode:
   - Drag tiles to reorder; the order should persist after leaving and re-entering.
   - Tap the resize button (bottom-right) to cycle tile sizes (mini / small / medium / wide). Tiles must not overlap or cover each other.
   - Tap the minus button (top-left) to delete a project; the confirmation sheet should offer both "delete project only" and "delete project with tasks".
3. Tapping a tile outside edit mode should open project details. Please watch for this specifically: **after long-pressing into edit mode and releasing, does it accidentally navigate to the detail page?**
4. Switch the "Active / Completed / Archived" filter and confirm the tile list matches the project status.

### 2. Automatic iCloud sync

> Prerequisite: sign in to iCloud with the same Apple ID. Two devices (e.g. iPhone + iPad) are recommended.

1. Settings → "iCloud sync" should show the correct state: checking / enabled / syncing / synced / please sign in to iCloud / sync problem.
2. Create, edit and delete tasks, projects, MindStamps and suspended tasks on device A; device B should receive the same changes (then test in reverse).
3. Tasks with image or file attachments should open correctly on the other device.
4. Make changes on one device while offline; after reconnecting, they should upload automatically with no data loss.
5. Create tasks for the same day on both devices while offline; after reconnecting, both should be preserved.
6. **Install over the previous build (1.0 build 2) without uninstalling**: existing weeks, days, tasks, projects and attachments must be preserved.
7. Note: notifications, default kill time, execution mode, theme and default project duration are device-local settings and are intentionally **not** synced.

### When reporting

Include device model and OS version, build number 1.0 (4), reproduction steps, and screenshots or a screen recording. For crashes, attach the TestFlight crash log.

---

## 复用说明

- 每次发版先改顶部的「当前版本」，再删掉本版不涉及的模块。
- 若某次只是小修，把正文压缩成 3–5 条要点即可，不要整篇沿用。
- 「已知问题」一段建议保留：能显著减少测试员重复上报已知缺陷。
