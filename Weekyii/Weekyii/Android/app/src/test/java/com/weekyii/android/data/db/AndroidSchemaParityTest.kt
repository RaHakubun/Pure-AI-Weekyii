package com.weekyii.android.data.db

import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.ProjectEntity
import com.weekyii.android.data.db.entities.TaskEntity
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidSchemaParityTest {
    @Test
    fun dayModelContainsCurrentExecutionControls() {
        val fields = DayEntity::class.java.declaredFields.map { it.name }.toSet()
        assertTrue("executionModeRaw", fields.contains("executionModeRaw"))
        assertTrue("isDraftZoneUnlocked", fields.contains("isDraftZoneUnlocked"))
        assertTrue("followsDefaultKillTime", fields.contains("followsDefaultKillTime"))
    }

    @Test
    fun taskAndProjectModelsContainCurrentPresentationLinks() {
        val taskFields = TaskEntity::class.java.declaredFields.map { it.name }.toSet()
        val projectFields = ProjectEntity::class.java.declaredFields.map { it.name }.toSet()
        assertTrue("taskTypeIdRaw", taskFields.contains("taskTypeIdRaw"))
        assertTrue("tileSizeRaw", projectFields.contains("tileSizeRaw"))
        assertTrue("tileOrder", projectFields.contains("tileOrder"))
    }

    @Test
    fun currentSchemaIncludesSuspendedTasksAndCustomTaskTypes() {
        assertTrue(
            runCatching { Class.forName("com.weekyii.android.data.db.entities.SuspendedTaskEntity") }.isSuccess
        )
        assertTrue(
            runCatching { Class.forName("com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity") }.isSuccess
        )
        assertTrue(MIGRATION_1_2.startVersion == 1)
        assertTrue(MIGRATION_1_2.endVersion == 2)
    }
}
