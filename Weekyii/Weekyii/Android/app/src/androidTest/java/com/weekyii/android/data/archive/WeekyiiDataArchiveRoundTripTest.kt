package com.weekyii.android.data.archive

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.weekyii.android.data.db.AppDatabase
import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.SuspendedTaskEntity
import com.weekyii.android.data.db.entities.SuspendedTaskStepEntity
import com.weekyii.android.data.db.entities.SuspendedTaskAttachmentEntity
import com.weekyii.android.data.db.entities.TaskAttachmentEntity
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskStepEntity
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.WeekEntity
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.domain.DataStoreAppStateStore
import com.weekyii.android.domain.DataStoreUserSettingsStore
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.time.LocalTime
import java.util.Date

@RunWith(AndroidJUnit4::class)
class WeekyiiDataArchiveRoundTripTest {
    private lateinit var database: AppDatabase
    private lateinit var repository: WeekyiiDataArchiveRepository
    private lateinit var settings: DataStoreUserSettingsStore

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        settings = DataStoreUserSettingsStore(context)
        repository = WeekyiiDataArchiveRepository(
            database = database,
            settings = settings,
            appState = DataStoreAppStateStore(context),
            backupRecovery = BackupRecoveryService(context)
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun archiveRoundTripPreservesTaskResourcesSuspendedResourcesAndSettings() = runBlocking {
        val week = WeekEntity("2026-W30", Date(0), Date(86_400_000), WeekStatus.PRESENT)
        val day = DayEntity("2026-07-20", Date(0), "MON", DayStatus.DRAFT, weekOwnerId = week.weekId)
        val task = TaskEntity(title = "Task", order = 1, zone = TaskZone.DRAFT, dayOwnerId = day.dayId)
        val suspended = SuspendedTaskEntity(
            title = "Suspended",
            taskType = TaskType.REGULAR,
            createdAt = Date(0),
            decisionDeadline = Date(86_400_000),
            preferredCountdownDays = 1
        )
        database.weekDao().upsert(week)
        database.dayDao().upsert(day)
        database.taskDao().upsert(task)
        database.taskDao().upsertSteps(listOf(TaskStepEntity(title = "step", taskOwnerId = task.id)))
        database.taskDao().upsertAttachments(listOf(TaskAttachmentEntity(data = byteArrayOf(1, 2), fileName = "task.txt", fileType = "text/plain", attachmentOwnerId = task.id)))
        database.suspendedTaskDao().upsert(suspended)
        database.suspendedTaskDao().upsertSteps(listOf(SuspendedTaskStepEntity(title = "s-step", suspendedTaskOwnerId = suspended.id)))
        database.suspendedTaskDao().upsertAttachments(listOf(SuspendedTaskAttachmentEntity(data = byteArrayOf(3, 4), fileName = "s.txt", fileType = "text/plain", suspendedTaskOwnerId = suspended.id)))
        settings.setThemeId("ocean")
        settings.setAppearanceMode("dark")
        settings.setKillTimeReminderMinutes(30)

        val archive = repository.exportArchive()
        database.taskDao().deleteAll()
        database.suspendedTaskDao().deleteAll()
        repository.importReplacing(archive)

        val restoredTask = database.taskDao().findWithSteps(task.id)!!
        val restoredSuspended = database.suspendedTaskDao().findWithDetails(suspended.id)!!
        assertEquals("step", restoredTask.steps.single().title)
        assertArrayEquals(byteArrayOf(1, 2), restoredTask.attachments.single().data)
        assertEquals("s-step", restoredSuspended.steps.single().title)
        assertArrayEquals(byteArrayOf(3, 4), restoredSuspended.attachments.single().data)
        assertEquals(LocalTime.of(20, 0), settings.defaultKillTime.value)
        assertEquals("ocean", settings.themeId.value)
        assertEquals("dark", settings.appearanceMode.value)
        assertEquals(30, settings.killTimeReminderMinutes.value)
    }
}
