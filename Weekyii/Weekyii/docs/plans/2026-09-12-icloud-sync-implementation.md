# Weekyii iCloud Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在用户登录 iCloud 时，让 Weekyii 的 SwiftData 业务数据自动在同一用户的 iPhone 与 iPad 间同步，并为未来 macOS 客户端保留复用能力。

**Architecture:** 保持 SwiftData 为唯一业务读写入口，通过 `ModelConfiguration.CloudKitDatabase.private` 镜像到 CloudKit Private Database。新增 V7 CloudKit-compatible Schema，CloudKit 状态监控与业务视图解耦，远端合并后复用现有数据不变量修复流程。

**Tech Stack:** Swift 5、SwiftUI、SwiftData、CloudKit、XCTest、Xcode 26.2

---

### Task 1: 固化同步兼容契约

**Files:**
- Modify: `Tests/ModelTests.swift`
- Modify: `App/WeekyiiPersistence.swift`

**Step 1: Write the failing test**

增加测试，断言当前 Schema 版本为 V7、所有实体无唯一约束、所有关系为 optional 且存在 inverse，并建立包含 V6 全部实体的文件存储。

**Step 2: Run it to make sure it fails**

Run: `xcodebuild test -project Weekyii.xcodeproj -scheme Weekyii -destination 'platform=iOS Simulator,id=78AEA02E-5B71-4BDB-87F8-EA0F844EB8CC' -only-testing:WeekyiiTests/ModelTests/test_cloudSyncSchema_isCloudKitCompatible CODE_SIGNING_ALLOWED=NO`

Expected: FAIL because V6 contains unique constraints and unpaired relationships.

**Step 3: Write minimal implementation**

冻结 V6 的历史模型定义；新增 `WeekyiiSchemaV7`，将全局业务模型作为 V7 当前模型，并将迁移计划追加 V6 → V7。

**Step 4: Run the tests and make sure they pass**

Run the focused Schema compatibility test and all persistence migration tests.

**Step 5: Commit**

`git commit -m "feat: add CloudKit-compatible schema v7"`

### Task 2: 保证 V6 本地数据无损迁移

**Files:**
- Modify: `Tests/ModelTests.swift`
- Modify: `Models/WeekModel.swift`
- Modify: `Models/DayModel.swift`
- Modify: `Models/TaskItem.swift`
- Modify: `Models/TaskStep.swift`
- Modify: `Models/TaskAttachment.swift`
- Modify: `Models/ProjectModel.swift`
- Modify: `Models/MindStampItem.swift`
- Modify: `Models/TaskTypeDefinition.swift`
- Modify: `App/WeekyiiPersistence.swift`
- Modify: `Services/DataArchiveService.swift`

**Step 1: Write the failing test**

创建 V6 文件数据库，写入周、日、普通任务、步骤、附件、项目、MindStamp、暂存任务和自定义类型；升级到 V7 后逐项断言标识、字段、关系和二进制数据保留。

**Step 2: Run it to make sure it fails**

Expected: FAIL before V7 migration is implemented.

**Step 3: Write minimal implementation**

移除当前模型的唯一约束；为无默认值属性补齐持久化默认值；为步骤和附件补齐两组可选 inverse；更新归档 Schema 版本但保持格式向后兼容。

**Step 4: Run the tests and make sure they pass**

运行 V1–V6 迁移测试、模型测试和归档测试的稳定子集。

**Step 5: Commit**

`git commit -m "test: preserve local data through cloud schema migration"`

### Task 3: 启用自动 Private Database 镜像

**Files:**
- Modify: `Resources/Weekyii.entitlements`
- Modify: `Weekyii.xcodeproj/project.pbxproj`
- Modify: `App/WeekyiiPersistence.swift`
- Modify: `Tests/ModelTests.swift`

**Step 1: Write the failing test**

为持久化配置选择增加测试：内存/测试容器使用 `.none`，生产容器使用 `iCloud.com.fluentdesign.Weekyii` 的 private database。

**Step 2: Run it to make sure it fails**

Expected: FAIL because every configuration currently uses `.none`.

**Step 3: Write minimal implementation**

引入可测试的存储模式；生产启动始终选择 CloudKit private database；配置 iCloud Container、CloudKit service 和 Remote Notifications 能力。

**Step 4: Run the tests and make sure they pass**

运行配置测试、无签名模拟器构建，以及带开发团队的 generic iOS device 构建。

**Step 5: Commit**

`git commit -m "feat: enable automatic private iCloud sync"`

### Task 4: 展示同步状态并触发远端收敛

**Files:**
- Create: `Services/CloudSyncMonitor.swift`
- Create: `Tests/CloudSyncMonitorTests.swift`
- Modify: `App/WeekyiiApp.swift`
- Modify: `Resources/SettingsView.swift`
- Modify: `Resources/UserSettings.swift`
- Modify: `Resources/Localizable.xcstrings`
- Modify: `Weekyii.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

测试 CloudKit account status 和镜像事件到用户状态的映射，以及远端成功导入后请求领域数据收敛。

**Step 2: Run it to make sure it fails**

Expected: FAIL because `CloudSyncMonitor` does not exist.

**Step 3: Write minimal implementation**

使用 `@Observable @MainActor` 实现监控器；监听账号状态与 CloudKit mirroring event；将设置页占位 Toggle 替换为只读的自动同步状态；删除已经无意义的 `iCloudSyncEnabled` 偏好。

**Step 4: Run the tests and make sure they pass**

运行监控器单元测试、设置页编译及状态机不变量测试。

**Step 5: Commit**

`git commit -m "feat: surface automatic iCloud sync status"`

### Task 5: 发布前验证和运维文档

**Files:**
- Modify: `SWIFTDATA_MIGRATION_RULES.md`
- Modify: `docs/release-checklist.md`
- Create: `docs/icloud-sync-runbook.md`

**Step 1: Run automated verification**

运行所有不受既有归档模拟器崩溃影响的单元测试、Debug 模拟器构建、Release generic iOS 构建和 App Store preflight。

**Step 2: Run manual device verification**

在同一 iCloud 测试账号的 iPhone 和 iPad 上验证首次上传、双向编辑、删除、离线恢复、附件和并发 Focus 修改。

**Step 3: Deploy CloudKit production schema**

在 CloudKit Console 审核 development Schema，仅在真机验证通过后部署到 production。

**Step 4: Commit**

`git commit -m "docs: add iCloud sync release runbook"`

