package com.weekyii.android.platform

import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.DayWithTasks
import java.time.LocalDate
import java.util.Date
import org.junit.Assert.assertEquals
import org.junit.Test

class WeekyiiWidgetSnapshotTest {
    @Test
    fun emptyDayProducesSafeSnapshot() {
        val snapshot = WeekyiiWidgetSnapshot.from(null, LocalDate.of(2026, 7, 20))

        assertEquals("未创建", snapshot.statusLabel)
        assertEquals("今天还没有任务流", snapshot.focusTitle)
        assertEquals(0, snapshot.frozenCount)
    }

    @Test
    fun executingDayShowsFocusFrozenAndKillTime() {
        val day = DayEntity("2026-07-20", Date(0), "MON", DayStatus.EXECUTE, 21, 30, weekOwnerId = "2026-W30")
        val focus = TaskEntity(title = "Focus", order = 1, zone = TaskZone.FOCUS, dayOwnerId = day.dayId)
        val frozen = TaskEntity(title = "Frozen", order = 2, zone = TaskZone.FROZEN, dayOwnerId = day.dayId)

        val snapshot = WeekyiiWidgetSnapshot.from(DayWithTasks(day, listOf(focus, frozen)), LocalDate.of(2026, 7, 20))

        assertEquals("执行中", snapshot.statusLabel)
        assertEquals("Focus", snapshot.focusTitle)
        assertEquals(1, snapshot.frozenCount)
        assertEquals("21:30", snapshot.killTimeLabel)
    }
}
