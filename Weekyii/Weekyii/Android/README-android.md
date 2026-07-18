# Weekyii Android

这是 `online-chatgpt-develop` 行为的 Android 原生实现。业务规则保持一致，界面与系统交互使用 Jetpack Compose、Material 3、Room、DataStore、WorkManager、AlarmManager 和 AppWidget。

## 打开项目

Android Studio 打开目录：

`Weekyii/Weekyii/Android`

等待 Gradle Sync 完成后，选择 `app` 配置与模拟器/真机即可运行。

## 构建与验证

项目使用 Android Studio 自带 JBR（JDK 21）与仓库内 Gradle Wrapper：

```bash
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
ANDROID_HOME="$HOME/Library/Android/sdk" \
./gradlew \
  :app:testDebugUnitTest \
  :app:compileDebugAndroidTestKotlin \
  :app:lintDebug \
  :app:assembleDebug \
  --no-daemon
```

Debug APK：

`app/build/outputs/apk/debug/app-debug.apk`

设备已连接时运行 instrumentation：

```bash
./gradlew :app:connectedDebugAndroidTest --no-daemon
```

## 实现范围

- Today、当前周、Pending 月历/周计划、Past 统计与详情
- 严格/灵活执行、延期、步骤与附件、自定义任务类型
- Projects、MindStamp、悬置任务及其提醒生命周期
- 主题、系统/浅色/深色、默认项目值、Kill Time 提前与固定提醒
- 版本化 JSON 归档、导入前恢复点、Room 迁移、后台 reconcile
- Android 主屏 Today Widget

通知在 Android 13 及以上需要用户在 Settings 页面授予通知权限。
