# Weekyii Android Parity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 追平 `origin/online-chatgpt-develop` 的 Weekyii iOS 行为，在 Android 上交付可构建、可持久化、可测试的原生版本。

**Architecture:** 在现有 Android worktree 中保留 Kotlin + Compose + Room 方向，先把领域状态机和事务 Repository 做深，再接入五个产品页面和 Android 系统能力。iOS 只作为行为规约，不共享运行时代码或 SwiftData 文件。

**Tech Stack:** Kotlin, Jetpack Compose, Material 3, Room, DataStore, Coroutines/Flow, WorkManager, Android Notification API, JUnit, Compose UI Test。

---

### Task 1: 建立可重复的 Android 构建基线

**Files:**
- Create: `Weekyii/Weekyii/Android/.gitignore`
- Modify: `Weekyii/Weekyii/Android/app/src/main/AndroidManifest.xml`
- Modify: `Weekyii/Weekyii/Android/gradle.properties`
- Create: `Weekyii/Weekyii/Android/gradle/wrapper/gradle-wrapper.jar` (由 Gradle 8.7 wrapper 生成)

**Steps:**
1. 忽略 `.gradle/`、`.idea/`、`local.properties`、`build/` 和测试输出。
2. 删除 Manifest 的过时 `package` 属性，加入可用的 Android 自适应图标资源。
3. 生成 Gradle 8.7 wrapper，固定 JDK/compileSdk 警告策略。
4. 运行 `./gradlew :app:assembleDebug`，记录资源、Kotlin 和 Room 编译基线。

### Task 2: 先写领域行为失败测试

**Files:**
- Create: `app/src/test/java/com/weekyii/android/domain/WeekCalculatorTest.kt`
- Create: `app/src/test/java/com/weekyii/android/domain/StateMachineTest.kt`
- Create: `app/src/test/java/com/weekyii/android/domain/TodayFlowTest.kt`
- Modify: `app/build.gradle.kts` (测试依赖)

**Steps:**
1. 覆盖 ISO 周编号、跨年周、非法周号和本地时区。
2. 覆盖 draft→execute、Focus 推进、完成收口、跨日过期、Kill Time 过期和 Present/Past/Pending 迁移。
3. 覆盖空任务不能启动、已启动不能编辑、过期任务不保留详情和 daysStartedCount 只增一次。
4. 用 Gradle 运行测试，确认测试先因缺失/错误实现失败。

### Task 3: 完成 Room schema、迁移和事务 Repository

**Files:**
- Modify: `data/db/entities/*.kt`
- Modify: `data/db/dao/*.kt`
- Modify: `data/db/AppDatabase.kt`
- Create: `data/db/migrations/Migrations.kt`
- Modify: `data/repository/WeekyiiRepository.kt`
- Create: `data/repository/RepositoryResult.kt`

**Steps:**
1. 补齐 SuspendedTask、TaskTypeDefinition、tileSize/tileOrder、execution mode 和 draft-zone 解锁字段。
2. 添加 Room schema export 与版本迁移，禁止 destructive migration。
3. 用 `@Transaction` 封装启动、完成 Focus、延期、项目任务放置和过期清理。
4. 让 Repository 对外暴露领域结果，不把 DAO 类型泄漏到 ViewModel。
5. 运行 Room 内存数据库测试和领域测试。

### Task 4: 重建 AppState、启动装配和状态机

**Files:**
- Modify: `domain/AppStateStore.kt`
- Create: `domain/DataStoreAppStateStore.kt`
- Modify: `domain/StateMachine.kt`
- Create: `WeekyiiApplication.kt`
- Modify: `MainActivity.kt`

**Steps:**
1. 用 DataStore 持久化 systemStartDate、lastProcessedDate、lastRolloverAt、daysStartedCount、revisions。
2. 在 Application 单例初始化 Room、Repository、StateMachine、通知/Worker 调度器。
3. 启动、回前台和分钟级 Worker 都调用同一个 reconcile。
4. 数据库打开失败时显示只读诊断状态，不回退到假的内存仓库。
5. 运行状态机测试和应用启动构建。

### Task 5: 完成 Today 行为和 Compose 页面

**Files:**
- Modify: `ui/viewmodel/TodayViewModel.kt`
- Create/Modify: `ui/screens/today/*.kt`
- Create: `ui/components/TaskCard.kt`, `TaskZoneSection.kt`, `KillTimeEditor.kt`, `DraftTaskEditor.kt`

**Steps:**
1. 实现任务新增、编辑、删除、拖拽排序、子任务/附件编辑。
2. 实现开始、完成 Focus、延期、Kill Time 影响预览和灵活执行入口。
3. 将 draft/execute/completed/expired 映射为清晰的 Android UiState。
4. 使用 Material 3 卡片、BottomSheet、Date/Time Picker 和 Android 返回手势。
5. 编写 Today Compose 关键路径测试。

### Task 6: 完成 Pending、Week 和 Past

**Files:**
- Modify: `ui/viewmodel/PendingViewModel.kt`, `PastViewModel.kt`
- Create: `ui/viewmodel/WeekViewModel.kt`
- Modify: `ui/screens/pending/*.kt`, `ui/screens/past/*.kt`
- Create: `ui/screens/week/*.kt`, `ui/components/WeekTopology.kt`

**Steps:**
1. 实现按日期/周编号创建、按月分组、周负载摘要和日详情编辑。
2. 实现当前周七天状态与拓扑浏览。
3. 实现 Past 周/月统计、完成率、专注时长、热力图和过期数量约束。
4. 运行 ViewModel 和 Compose 测试。

### Task 7: 完成 Extensions：Projects、MindStamps、Suspended Tasks

**Files:**
- Modify: `ui/viewmodel/ExtensionsViewModel.kt`
- Create: `ui/viewmodel/MindStampViewModel.kt`, `SuspendedTaskViewModel.kt`
- Modify: `ui/screens/extensions/*.kt`
- Create: `data/repository/ProjectRepository.kt`, `SuspendedTaskRepository.kt`

**Steps:**
1. 实现项目 CRUD、状态生命周期、磁贴大小/排序和项目任务台账。
2. 实现项目日期范围、非过去日、未完成日约束。
3. 实现 MindStamp 文本/图片、随机仪式内容。
4. 实现悬置箱创建、延期、指派、删除、到期清扫和提醒。
5. 运行生命周期和边界测试。

### Task 8: 完成 Settings、主题、任务类型与归档

**Files:**
- Modify: `ui/viewmodel/SettingsViewModel.kt`, `ui/theme/*.kt`
- Modify: `res/values/strings.xml`
- Create: `res/values-zh/strings.xml`, `res/values-en/strings.xml`
- Create: `data/archive/ArchiveService.kt`, `data/archive/ArchiveModels.kt`
- Modify: `ui/screens/settings/SettingsScreen.kt`

**Steps:**
1. 对齐内置/自定义任务类型、主题、外观模式、默认 Kill Time、提醒和执行模式。
2. 实现版本化 JSON 导出/检查/替换导入，导入前校验引用完整性并生成备份。
3. 使用 Android 文件选择器和分享 Intent，不直接暴露应用内部路径。
4. 运行归档 round-trip、非法数据拒绝和本地化测试。

### Task 9: 接入通知、WorkManager 和桌面小组件

**Files:**
- Create: `platform/WeekyiiNotificationService.kt`
- Create: `platform/WeekyiiReconcileWorker.kt`
- Create: `widget/WeekyiiWidget.kt`
- Modify: `AndroidManifest.xml`, `strings.xml`

**Steps:**
1. 请求通知权限，按确定性 ID 调度/取消 Kill Time、悬置箱和固定提醒。
2. 用 WorkManager 执行跨日/跨周 reconcile，避免只依赖进程存活。
3. 提供 Today 摘要、Focus、完成率和 Kill Time 的小组件快照。
4. 运行通知计划纯函数测试和 Worker 约束测试。

### Task 10: 对照验证与交付

**Files:**
- Modify: `README-android.md`
- Create: `docs/plans/2026-07-18-android-parity-verification.md`

**Steps:**
1. 运行 `./gradlew testDebugUnitTest`、`./gradlew connectedDebugAndroidTest`（设备可用时）、`./gradlew lint`、`./gradlew assembleDebug`。
2. 用功能对照表核验 iOS 当前分支的每个用户操作和状态转移。
3. 记录已完成、暂不支持和平台差异；任何差异必须是 Android 系统交互差异而非业务差异。
4. 生成 APK 路径、测试摘要和剩余风险报告。

