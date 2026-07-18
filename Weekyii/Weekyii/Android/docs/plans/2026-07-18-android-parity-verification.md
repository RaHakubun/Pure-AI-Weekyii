# Android Parity Verification

Target: `online-chatgpt-develop` at `b07c2473d93449d548aead25e5261a25db5eeb84`

Android branch: `codex/android-port`

## Automated verification

The following matrix is the release gate:

```bash
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
ANDROID_HOME='/Users/luobowen/Library/Android/sdk' \
./gradlew \
  :app:testDebugUnitTest \
  :app:compileDebugAndroidTestKotlin \
  :app:lintDebug \
  :app:assembleDebug \
  --no-daemon
```

Expected result: `BUILD SUCCESSFUL`.

## Device verification

Two instrumentation suites are present:

- Room relationship/upsert integrity
- Full archive round trip including task/suspended resources and persisted settings

Run them after an emulator or physical device appears in `adb devices`:

```bash
ANDROID_HOME='/Users/luobowen/Library/Android/sdk' \
./gradlew :app:connectedDebugAndroidTest --no-daemon
```

If Android 13 or later is used, grant notification permission from the app's Settings page before manually checking Kill Time and suspended-task notifications.

## Platform adaptations

- iOS WidgetKit behavior is represented by an Android home-screen AppWidget.
- iOS notification requests are represented by AlarmManager checkpoint alarms.
- iCloud remains outside the Android implementation, matching the iOS branch where it is still a placeholder.
