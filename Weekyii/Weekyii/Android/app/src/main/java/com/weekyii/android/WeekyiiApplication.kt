package com.weekyii.android

import android.app.Application
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.room.Room
import com.weekyii.android.data.db.AppDatabase
import com.weekyii.android.data.db.MIGRATION_1_2
import com.weekyii.android.data.repository.WeekCalculator
import com.weekyii.android.data.repository.WeekyiiRepository
import com.weekyii.android.data.repository.SuspendedTaskRepository
import com.weekyii.android.domain.DataStoreAppStateStore
import com.weekyii.android.domain.DefaultTimeProvider
import com.weekyii.android.domain.StateMachine
import com.weekyii.android.domain.TimeProvider
import com.weekyii.android.domain.DataStoreUserSettingsStore
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import com.weekyii.android.platform.WeekyiiNotificationService
import com.weekyii.android.platform.WeekyiiReconcileWorker

class WeekyiiApplication : Application() {
    lateinit var database: AppDatabase
        private set
    lateinit var repository: WeekyiiRepository
        private set
    lateinit var timeProvider: TimeProvider
        private set
    lateinit var stateMachine: StateMachine
        private set
    lateinit var appStateStore: DataStoreAppStateStore
        private set
    lateinit var settingsStore: DataStoreUserSettingsStore
        private set
    lateinit var suspendedTaskRepository: SuspendedTaskRepository
        private set
    lateinit var notificationService: WeekyiiNotificationService
        private set
    var startupError: String? = null
        private set

    override fun onCreate() {
        super.onCreate()
        try {
            val zone = ZoneId.systemDefault()
            database = Room.databaseBuilder(this, AppDatabase::class.java, "weekyii.db")
                .addMigrations(MIGRATION_1_2)
                .build()
            timeProvider = DefaultTimeProvider(zone)
            repository = WeekyiiRepository(
                weekDao = database.weekDao(),
                dayDao = database.dayDao(),
                taskDao = database.taskDao(),
                projectDao = database.projectDao(),
                weekCalculator = WeekCalculator(),
                zoneId = zone
            )
            appStateStore = DataStoreAppStateStore(this)
            settingsStore = DataStoreUserSettingsStore(this)
            suspendedTaskRepository = SuspendedTaskRepository(database.suspendedTaskDao(), zone, repository)
            notificationService = WeekyiiNotificationService(this)
            notificationService.ensureChannel()
            stateMachine = StateMachine(
                repo = repository,
                timeProvider = timeProvider,
                appState = appStateStore,
                settings = settingsStore,
                suspendedTaskSweeper = suspendedTaskRepository
            )
            stateMachine.processStateTransitions()
            WorkManager.getInstance(this).enqueueUniquePeriodicWork(
                "weekyii-reconcile",
                ExistingPeriodicWorkPolicy.UPDATE,
                PeriodicWorkRequestBuilder<WeekyiiReconcileWorker>(15, TimeUnit.MINUTES).build()
            )
        } catch (error: Exception) {
            startupError = "本地数据无法打开：${error.localizedMessage ?: "未知错误"}"
        }
    }
}
