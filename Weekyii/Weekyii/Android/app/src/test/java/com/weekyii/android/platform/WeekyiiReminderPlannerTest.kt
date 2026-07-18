package com.weekyii.android.platform

import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

class WeekyiiReminderPlannerTest {
    @Test
    fun suspendedPlanContainsFourFutureCheckpoints() {
        val taskId = UUID.fromString("00000000-0000-0000-0000-000000000001")
        val now = LocalDateTime.of(2026, 7, 20, 8, 0)
        val deadline = LocalDateTime.of(2026, 7, 25, 23, 59)

        val plan = WeekyiiReminderPlanner.suspendedTaskPlan(taskId, deadline, now, ZoneId.of("Asia/Shanghai"))

        assertEquals(listOf("d3", "d1", "d0m", "d0e"), plan.map { it.suffix })
        assertEquals(LocalDateTime.of(2026, 7, 22, 9, 30), plan[0].fireAt)
        assertEquals(LocalDateTime.of(2026, 7, 24, 10, 0), plan[1].fireAt)
        assertEquals(LocalDateTime.of(2026, 7, 25, 9, 0), plan[2].fireAt)
        assertEquals(LocalDateTime.of(2026, 7, 25, 19, 30), plan[3].fireAt)
    }
}
