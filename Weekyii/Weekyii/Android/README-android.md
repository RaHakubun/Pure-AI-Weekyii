# Weekyii Android 子工程（草案版）

> 当前仅落盘代码与目录，无构建依赖下载；待接入 Room/Hilt 等后再运行。

## 结构
- `Android/app/src/main/java/com/weekyii/android/` 主代码
  - `data/db/entities` Room 实体（Week/Day/Task/Step/Attachment/Project/MindStamp + 枚举）
  - `data/db/dao` DAO 接口
  - `data/db/AppDatabase.kt` + `Converters.kt`
  - `data/repository` Repository、WeekCalculator、实体到 UI 模型映射
  - `domain` StateMachine、TimeProvider、AppStateStore（内存版）
  - `ui` Compose 主题、导航、各页占位 UI、ViewModel 骨架
- `Android/app/src/main/res/values` 颜色/字符串/主题资源
- `Android/app/build.gradle.kts`、`settings.gradle.kts` 等（未下载 wrapper）

## 构建（稍后）
- 安装 Android Studio Iguana+，JDK 21。
- 在 `Android/` 目录执行 `./gradlew :app:assembleDebug`（需要补齐 gradle wrapper 后）。

## 待办
- 接入 Room 实例和 DI（Hilt/手动单例），替换 `StubRepoFactory`。
- 按 iOS 逻辑完善 StateMachine 定时触发、通知。
- UI 细化：Today/Pending/Past 真实交互，Extensions/Settings 填充。
- 本地化 key 对齐 iOS。
