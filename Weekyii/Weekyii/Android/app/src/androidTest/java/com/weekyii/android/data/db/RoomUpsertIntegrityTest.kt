package com.weekyii.android.data.db

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.ProjectEntity
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskStepEntity
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.WeekEntity
import com.weekyii.android.data.db.entities.WeekStatus
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Date

@RunWith(AndroidJUnit4::class)
class RoomUpsertIntegrityTest {
    private lateinit var database: AppDatabase

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun parentUpdatesPreserveTaskLinksAndResources() = runBlocking {
        val week = WeekEntity("2026-W30", Date(0), Date(1), WeekStatus.PRESENT)
        val day = DayEntity("2026-07-22", Date(0), "WED", DayStatus.EMPTY, weekOwnerId = week.weekId)
        val project = ProjectEntity(name = "Parity", startDate = Date(0), endDate = Date(1))
        database.weekDao().upsert(week)
        database.dayDao().upsert(day)
        database.projectDao().upsert(project)
        val task = TaskEntity(title = "Keep links", order = 1, zone = TaskZone.DRAFT, dayOwnerId = day.dayId, projectOwnerId = project.projectId)
        database.taskDao().upsert(task)
        database.taskDao().upsertSteps(listOf(TaskStepEntity(title = "Keep step", taskOwnerId = task.id)))

        database.projectDao().upsert(project.copy(status = ProjectStatus.ACTIVE))
        database.dayDao().upsert(day.copy(status = DayStatus.DRAFT))
        database.taskDao().upsert(task.copy(title = "Updated"))

        val storedTask = database.taskDao().findById(task.id)
        assertEquals(project.projectId, storedTask?.projectOwnerId)
        assertEquals(day.dayId, storedTask?.dayOwnerId)
        assertEquals("Updated", storedTask?.title)
        assertNotNull(database.taskDao().findWithSteps(task.id)?.steps?.singleOrNull { it.title == "Keep step" })
    }
}
