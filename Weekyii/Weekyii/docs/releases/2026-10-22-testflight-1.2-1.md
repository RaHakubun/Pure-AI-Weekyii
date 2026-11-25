# Weekyii 1.2 (1) — TestFlight candidate

- Date: 2026-10-22 (Asia/Taipei).
- Branch: `online-chatgpt-develop`; source baseline: `5090379` (「docs: add complete Weekyii App Store release SOP」).
- Version commit: `0248f0f` (「chore(release): prepare Weekyii 1.2 (1)」) — App 与 Widget 的 `MARKETING_VERSION = 1.2`、`CURRENT_PROJECT_VERSION = 1`。
- 上一版 TestFlight：1.1 (5)（build `2618c54a-30ab-4bd3-8d06-b117510b2371`，外部组「外部体验者」邀请 6 人）。
- 本次内容：第五轮 iCloud 同步修复（传输层逐条隔离、Zone 丢失不锁存、习惯任务确定性 ID、归档导入/恢复点前暂停同步、`apply` 失败回滚、`serverRecordChanged` 重发走收件箱），以及首页同步横幅入口与换账号二次确认。

## Evidence

- 全量单元测试 516 例通过（该分支当时的总数；`notion-claude/feat-in-app-purchase` 分支第六轮之后为 548 例）。
- UI 测试 23 例通过。
- 归档与签名验证通过：`aps-environment = production`、CloudKit container、App Group 均正确；App 与 Widget 的 build 号一致为 1。
- 归档 → 上传成功，日志原路径 `/tmp/weekyii-release-20261022-upload.log`。**该日志已不在本机**（`/tmp` 被清理），本文是唯一留存记录。

## Release outcome（截至 2026-11-01）

- 构建已上传到 App Store Connect，但**以下四项均未完成**：
  - [ ] 出口合规问卷未填（沿用「不属于上述任意一种算法」，本轮未引入新加密实现）。
  - [ ] 未分发到任何测试组（内部「Apple haha」、外部「外部体验者」均未指派）。
  - [ ] Apple 是否处理完成未确认。
  - [ ] 未记录 ASC build ID（本机无法读取：无 `.p8` API key、无 fastlane/`asc` CLI、无 Transporter）。
- 因此 **1.2 (1) 目前不是可测状态**，外部体验者收不到更新。
- 上述四项都需要账号主体在 App Store Connect 网页完成；操作清单见 `docs/handoff/ICLOUD_ROUND6_HUMAN_CHECKLIST.md` 第 2 节。
- 真机覆盖安装与双设备同步：本次未验证。

## 备注

- 同一 `MARKETING_VERSION` 下 build 号必须单调递增、不可重用；1.2 的下一版从 build 2 开始。
- 若 1.2 (1) 需要替换（例如必须带上第六轮修复），应发 1.2 (2)，不要重用 build 1。
