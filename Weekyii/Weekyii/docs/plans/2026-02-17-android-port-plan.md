# Android Port Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 iOS Weekyii 代码不变前提下，新建 Android (Kotlin + Jetpack Compose + Room) 子工程，复刻核心数据模型、状态机与 5 页导航骨架，支持本地持久化与基本日/周任务流操作。

**Architecture:** 单模块 Android 应用，MVVM + Repository + Room，本地定时逻辑由 StateMachine 协程驱动；Compose Navigation 建 5 Tab（Past/Today/Pending/Extensions/Settings），共享 ViewModel 透出状态。

**Tech Stack:** Kotlin, Jetpack Compose (Material3), Navigation Compose, Room, Coroutines/Flow, Hilt(可选后续), Android Gradle Plugin 8.x, minSdk 26 / targetSdk 35.

---

### Task 1: 初始化 Android 工程骨架
**Files:**
- Create: `Android/settings.gradle.kts`, `Android/build.gradle.kts`, `Android/gradle.properties`, `Android/gradle/wrapper/...`, `Android/app/build.gradle.kts`, `Android/app/src/main/AndroidManifest.xml`
- Create dirs: `Android/app/src/main/java/com/weekyii/android`, `Android/app/src/main/res/values`
**Steps:**
- 编写 Gradle Wrapper (8.7) 与 AGP 8.3+ 配置；设置 compileSdk/targetSdk 35, minSdk 26。
- 启用 Compose、Kapt、Room 依赖与 Kotlin JVM 21 目标。
- Manifest 声明单 Activity (`MainActivity`) 与必要权限（无特殊权限）。

### Task 2: 定义基础主题与资源
**Files:**
- Create: `Android/app/src/main/res/values/colors.xml`, `strings.xml`, `themes.xml`
- Create: `Android/app/src/main/java/com/weekyii/android/ui/theme/Theme.kt`, `Color.kt`, `Type.kt`
**Steps:**
- 参照 iOS 颜色命名（weekyiiPrimary, taskRegular/DDL/Leisure 等）映射为 Material 色板。
- 定义应用主题、暗色/亮色开关、基础 Typography。

### Task 3: 建立 Room 数据模型与转换
**Files:**
- Create: `Android/app/src/main/java/com/weekyii/android/data/db/entities/*.kt`
- Create: `Android/app/src/main/java/com/weekyii/android/data/db/Converters.kt`
- Create: `Android/app/src/main/java/com/weekyii/android/data/db/AppDatabase.kt`
**Steps:**
- 按 SwiftData 模型定义 WeekEntity/DayEntity/TaskEntity/TaskStepEntity/TaskAttachmentEntity/ProjectEntity/MindStampEntity。
- 保留字段：状态枚举、时间戳、killTime、order/completedOrder、expiredCount 等。
- 提供 TypeConverters 处理枚举、UUID、Date、ByteArray。
- 定义外键与级联删除关系，确保周/日/任务一致。

### Task 4: DAO 与 Repository 层
**Files:**
- Create: `Android/app/src/main/java/com/weekyii/android/data/db/dao/*.kt`
- Create: `Android/app/src/main/java/com/weekyii/android/data/repository/WeekyiiRepository.kt`
- Create: `Android/app/src/main/java/com/weekyii/android/data/repository/WeekCalculator.kt`
**Steps:**
- DAO: WeekDao, DayDao, TaskDao, ProjectDao, MindStampDao 提供查询/插入/更新/删除与组合查询（含按 weekId/dayId 关联）。
- Repository 封装跨实体事务、任务编号排序、状态写入接口。
- WeekCalculator 复刻 iOS 逻辑（weekId, range, validation, weekStartDate）。

### Task 5: 状态机 StateMachine 复刻
**Files:**
- Create: `Android/app/src/main/java/com/weekyii/android/domain/StateMachine.kt`
- Create: `Android/app/src/main/java/com/weekyii/android/domain/TimeProvider.kt`
- Create: `Android/app/src/main/java/com/weekyii/android/domain/AppStateStore.kt`
**Steps:**
- 搬运 iOS `processStateTransitions` 流程：ensureSystemStartDate → processStaleOpenDaysBeforeToday → processCrossDay → processCrossWeek → processKillTime → refreshWeekSummaryMetrics。
- 处理 expire 删除 draft/focus/frozen 任务，仅保留 expiredCount；周迁移 present→past；pending/promote 逻辑。
- TimeProvider 提供 now/today/currentWeekId；AppStateStore 持久化全局状态（可用 DataStore Preferences）。

### Task 6: ViewModel 层与 UseCases
**Files:**
- Create: `Android/app/src/main/java/com/weekyii/android/ui/viewmodel/*.kt`
- Create: `Android/app/src/main/java/com/weekyii/android/ui/model/*.kt`
**Steps:**
- TodayViewModel：draft 编辑、startDay、doneFocus、changeKillTime、show zones。
- PendingViewModel：创建未来周/天、复制 draft。
- PastViewModel：汇总完成/过期统计、月/周视图。
- Extensions/Settings 占位 ViewModel（后续补功能），暴露 Flow<State> 给 UI。

### Task 7: Compose 导航与 Tab 框架
**Files:**
- Create: `Android/app/src/main/java/com/weekyii/android/MainActivity.kt`
- Create: `Android/app/src/main/java/com/weekyii/android/ui/navigation/NavGraph.kt`
- Create: `Android/app/src/main/java/com/weekyii/android/ui/screens/{today,pending,past,extensions,settings}/*.kt`
**Steps:**
- 使用 `Scaffold + NavigationBar` 建 5 标签；每页挂对应 ViewModel。
- Today 屏：Draft/Frozen/Focus/Complete 列表视图 + 操作按钮。
- Pending/Past 屏：周列表、月视图概要卡片；Extensions/Settings 先放占位。

### Task 8: 依赖注入与启动装配
**Files:**
- Create: `Android/app/src/main/java/com/weekyii/android/di/AppModule.kt`
- Update: `Android/app/build.gradle.kts` 添加 Hilt（可选）或手动注入。
**Steps:**
- 提供单例 Room DB、Repository、StateMachine、TimeProvider、AppStateStore。
- 在 `MainActivity` 启动时触发一次 `processStateTransitions()`。

### Task 9: 国际化与文案
**Files:**
- Update: `strings.xml`；Create zh/strings.xml
**Steps:**
- 对齐 iOS 本地化 key，至少覆盖状态、任务类型、按钮文案。

### Task 10: 打包与运行脚本
**Files:**
- Update: `Android/README-android.md`（生成）
**Steps:**
- 记录构建命令 `./gradlew :app:assembleDebug`、本地运行要求；说明与 iOS 并存、不影响原工程。

---
