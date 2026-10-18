# Weekyii 1.1 (5) — TestFlight candidate

- Date: 2026-10-18 (Asia/Taipei).
- Branch: `online-chatgpt-develop`; source baseline: `ac8a5bd`.
- Previous TestFlight source: `63559fa`, version 1.1 (3).
- Includes merged habit/Today workflow changes, project overdue consistency and next-step deduplication, live kill-time fire updates, week outlook, Pending/Past view-mode persistence, MindStamp image presentation and illustrated About page.
- Candidate-local changes: explicit empty TimeProvider deinit workaround, three test-only expectation updates, App/Widget build number 5 and current localization extraction updates. Machine-local Xcode window state is excluded. Existing stash is not applied.
- App Store Connect already contains 1.1 (4), actively testing with both groups; this release uses the next unused build number 5. The TimeProvider fix is committed separately without version or localization changes.
- Persisted SwiftData declarations and migration plan in `App/WeekyiiPersistence.swift` are unchanged versus `63559fa`; `ProjectModel.swift` changes calculated overdue behavior, not stored fields. Archive settings add optional auto-start fields with legacy defaults; this is separate from the SwiftData schema.

## What to test / 测试内容

请通过 TestFlight 直接更新，不要卸载旧版。更新前后核对已有任务、项目、习惯、附件和设置。

1. 项目：逾期任务只显示数量，不作为下一步；检查今天截止后、仅有逾期任务、逾期与未来任务并存时的显示，确认下一步不重复。
2. 今日与习惯：检查手动启动、启动托管、截止过期、跨日及习惯记录结算，核对已完成与未完成数量。
3. 截止时间：拖动滑块时火焰变化即时跟随，取消恢复原值，确认后时间保存。
4. 周展望与月历：检查关键任务、每日条带和提示；Pending/Past 在周/月视图之间切换后重启，确认记住选择。
5. 心印：检查横图、竖图的居中与背景，编辑/预览切换是否流畅；检查新版“关于 Weekyii”的统计与布局。
6. 数据与同步：更新后先检查本地数据；开启 iCloud 后测试两台设备新增、编辑、删除及离线重连。此次模拟器测试不能替代真机覆盖更新与同步验证。

反馈请附设备型号、iOS 版本、1.1 (5)、复现步骤及截图或录屏。

## Evidence

- Initial full run: 512 unit tests executed, 3 failing cases (8 assertion failures), followed by 23 UI tests passed; `/tmp/weekyii-release-20261018-test.xcresult`.
- User authorized test-only alignment. Revised the three cases in `Tests/ModelTests.swift`: frame-level flame continuity, no synthetic historical habit nodes, and historical monthly nodes only with records. Targeted rerun: 3 passed, 0 failed; `/tmp/weekyii-release-20261018-targeted.xcresult`.
- Full unit reruns exposed a host-app `malloc` abort: `SettingsView.autoStartTimeBinding` → `TimeProvider.__deallocating_deinit` → executor/back-deployment deinit → invalid free. The user authorized the explicit empty deinit workaround for swiftlang/swift#88036; no caller, model or migration changes were made.
- Before-fix async test repeated with process relaunch reproduced SIGABRT; `/tmp/weekyii-timeprovider-20261018-before-repeat.xcresult`. After-fix same test passed all three relaunch iterations; `/tmp/weekyii-timeprovider-20261018-after.xcresult` (iteration details in the corresponding `.log`).
- After-fix full unit suite on iOS 26.2: 512 passed, zero failures/skips; `/tmp/weekyii-timeprovider-20261018-full.xcresult`.
- Manual iOS 26.2 Settings check: repeatedly changed daily start time 09:00 → 10:01 → 11:02 → 10:01 → 09:00 without a crash. Restored original 09:00 and kept auto-start disabled. iOS 26.4 runtime is not installed; not tested there.
- Final after-fix UI regression on iOS 26.2: 23 passed, zero failures; `/tmp/weekyii-release-20261018-final-ui.xcresult`.
- Signed 1.1 (5) archive succeeded: `/tmp/weekyii-release-20261018-final-1.1-5.xcarchive`. Deep signature verification passed; App and Widget both carry build 5. Production APS, expected CloudKit container and App Group entitlements verified.
- Upload receipt: `/tmp/weekyii-release-20261018-upload.log` when performed; this file alone does not prove external availability.
- Real-device in-place upgrade and multi-device sync: not verified in this run.
- Upload and external availability must be verified separately; a successful archive is not an upload receipt or Beta Review approval.

## Release outcome

- Source release commit: `864f563`; pushed to `origin/online-chatgpt-develop` with separate fix `2f44608` and test adjustment `c3daeea`.
- Upload succeeded at 2026-10-18 20:00:17 local time; `Upload succeeded` and `EXPORT SUCCEEDED` in `/tmp/weekyii-release-20261018-upload.log`.
- Apple finished processing. Export compliance questionnaire completed, test notes saved, external group selected and submitted with automatic tester notification enabled.
- App Store Connect build ID: `2618c54a-30ab-4bd3-8d06-b117510b2371`. Final visible status: **正在测试** for 1.1 (5), assigned to internal **Apple haha** and external **外部体验者**; invitation count 6.
- Existing testers can update through TestFlight. This does not certify real-device in-place migration or multi-device iCloud sync; those remain tester validation items.
- Only local Xcode `UserInterfaceState.xcuserstate` remains modified and excluded from commits. This outcome documentation is a follow-up documentation-only commit; it does not alter the uploaded binary.
