# Weekyii 1.1 (3) TestFlight candidate — 2026-10-16

## Candidate

- Branch: `online-chatgpt-develop`.
- Previous candidate: `990b776`, version 1.1 (2).
- App and Widget: version 1.1, build 3.
- Includes the current app UI, settings, localization and test changes, plus the kill-time fire design notes.
- Excludes machine-local `.DS_Store`, Xcode `xcuserdata`, `.workbuddy-ai`, unrelated historical review/plan documents and the scratch icon copy. These files remain in the working directory.
- No changes to SwiftData model declarations, migration schemas or iCloud sync services in this candidate diff.

## What to test / 测试内容

请直接通过 TestFlight 更新，不要卸载旧版；更新前后核对原有任务、项目、习惯、附件及设置是否保留。

1. 今日截止时间：拖动滑块向前、向后调整，确认时间与火焰紧迫程度即时响应；取消后恢复原有时间，确认修改后重新进入页面仍保留。检查深浅色、不同主题、减少动效和后台返回。
2. 今日结束状态：分别检查未启动就过期、执行后部分完成并过期、全部完成等状态，确认截止提示、完成数量和已完成任务详情正确。
3. 过去月历：在设置中切换失败标记、未启动标记、完成数量、记录点和过期火苗；检查预览、月历及重启后的设置保留。
4. 扩展页与项目看板：检查习惯周标记、悬置任务倒计时、项目进度/逾期提示，以及不同磁贴尺寸和编辑状态下的文字布局。
5. 习惯历史：切换周、月、年并前后浏览，核对完成、中断、未记录、休息日和未来计划的呈现。

已知项：项目同时存在历史逾期任务和今天/未来任务时，项目焦点卡可能重复显示“下一步”；项目任务的过期详情展示规则尚未统一。此候选版本保留当前行为，未将静态审查建议视为已修复。

如遇问题，请附设备型号、iOS 版本、构建号 1.1 (3)、操作步骤及截图/录屏。

## Verification

- Fresh unit run: 483 passed, 0 failed, 0 skipped; `/tmp/weekyii-release-20261016-unit.xcresult`.
- Fresh UI regression: 22 passed, 0 failed, 0 skipped; `/tmp/weekyii-release-20261016-ui.xcresult`.
- Signed Release archive succeeded; App and Widget both carry build 3. Deep signature verification passed; production provisioning, CloudKit container, App Group and packaged privacy manifests checked.
- Archive: `/tmp/weekyii-release-20261016-1.1-3.xcarchive`. Upload receipt is recorded separately after Apple accepts the upload; this document alone does not establish TestFlight availability.
- Physical-device in-place update and multi-device iCloud sync require tester evidence; simulator checks do not establish these outcomes.
