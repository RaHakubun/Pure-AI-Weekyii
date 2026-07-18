# Weekyii Android 行为镜像设计

**目标**：在 `codex/android-port` worktree 中，把当前 `online-chatgpt-develop` 的 Weekyii iOS 行为完整移植为 Android 原生应用；业务逻辑和操作契约保持一致，界面、导航、系统交互遵循 Android 设计规范。

## 基准与边界

- 行为基准是 `origin/online-chatgpt-develop`，不是旧的 `codex/android-port` 提交。
- Android 使用独立 Room 数据库，不直接读取 SwiftData 文件。
- 设计一个版本化 JSON 归档格式，使 iOS/Android 可以交换备份；首期不做云同步和实时跨设备合并。
- 保留已有 Android 雏形，但不把占位代码视为稳定 API。

## 分层架构

Android 使用 Kotlin + Jetpack Compose + Room + DataStore + WorkManager。

1. `domain`：时间、周计算、任务流规则、状态机、延期/悬置箱策略和可测试的错误语义。
2. `data`：Room 实体、迁移、DAO 和事务型 Repository；UI 不直接接触 DAO。
3. `ui.viewmodel`：把领域结果转换为稳定的 UiState，并集中处理用户可见错误。
4. `ui`：Material 3 页面、导航、手势、日期选择器和 Android 返回行为。
5. `platform`：通知、WorkManager、分享/文件选择、桌面小组件等 Android 能力。

状态机是唯一的跨日/跨周事实源。Today、通知 Worker、应用启动和回到前台都调用同一个 reconcile 入口，避免不同入口各自复制过期规则。

## 数据契约

Room 覆盖 Week、Day、Task、TaskStep、TaskAttachment、Project、MindStamp、SuspendedTask、TaskTypeDefinition 和 AppState。实体使用明确的版本号与迁移，不使用 destructive migration。任务关系保留周→日→任务级联，项目→任务解除关联不删除任务。

任务状态必须支持：`draft → execute → completed/expired`；区域必须支持 Draft、Focus、Frozen、Complete。启动后顺序锁定，完成 Focus 才能推进 Frozen；Kill Time 过期时删除未完成详情，仅保留数量。灵活执行、任务延期、项目任务放置和悬置箱必须复用同一套 Day/Task 约束。

## 页面与操作

- Today：草稿编辑、开始、Focus/Frozen/Complete、Kill Time、延期、灵活执行和 MindStamp 仪式。
- Pending：按月浏览、创建周/日期、周负载摘要、周详情、日任务流编辑。
- Past：周/月统计、热力图、日详情；过期任务只显示数量。
- Extensions：项目磁贴、项目详情/任务台账、MindStamp、悬置箱。
- Settings：主题/外观、默认任务类型与 Kill Time、提醒、执行模式、数据导入导出、诊断与重置。

## 错误与持久化

Repository 在事务内执行跨实体操作，领域层返回可枚举结果或稳定错误，而不是让 Compose 捕获底层 SQLite/Room 异常。启动时先初始化数据库，再执行状态 reconcile；数据库损坏时进入只读诊断界面，不创建伪造的内存数据。

## 测试策略

先为 WeekCalculator、状态机、Today 操作、延期/悬置箱生命周期、项目任务边界和归档校验写失败测试；再实现最小代码。Room DAO 使用内存数据库测试，ViewModel 使用测试时间提供者和测试 CoroutineDispatcher。最终执行单元测试、Compose 关键路径测试和 `assembleDebug`/`lint`。

