package com.weekyii.android.platform

import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID

data class SuspendedReminderPlanItem(
    val identifier: String,
    val suffix: String,
    val fireAt: LocalDateTime,
    val body: String
)

object WeekyiiReminderPlanner {
    private data class Checkpoint(
        val suffix: String,
        val dayOffset: Long,
        val time: LocalTime,
        val body: String
    )

    private val checkpoints = listOf(
        Checkpoint("d3", -3, LocalTime.of(9, 30), "还有 3 天到期：请续期、分配到具体某一天，或删除。"),
        Checkpoint("d1", -1, LocalTime.of(10, 0), "明天到期：请尽快处理这个悬置任务。"),
        Checkpoint("d0m", 0, LocalTime.of(9, 0), "今天到期：建议现在续期或分配到具体日期。"),
        Checkpoint("d0e", 0, LocalTime.of(19, 30), "今晚到期：若仍未处理，系统将自动删除该任务。")
    )

    fun suspendedTaskPlan(
        taskId: UUID,
        decisionDeadline: LocalDateTime,
        now: LocalDateTime,
        zoneId: ZoneId = ZoneId.systemDefault()
    ): List<SuspendedReminderPlanItem> {
        val dueDay = decisionDeadline.atZone(zoneId).toLocalDate()
        val nowInstant = now.atZone(zoneId).toInstant()
        return checkpoints.mapNotNull { checkpoint ->
            val fireDateTime = LocalDateTime.of(dueDay.plusDays(checkpoint.dayOffset), checkpoint.time)
            if (!fireDateTime.atZone(zoneId).toInstant().isAfter(nowInstant)) return@mapNotNull null
            SuspendedReminderPlanItem(
                identifier = "suspended-${taskId}-${checkpoint.suffix}",
                suffix = checkpoint.suffix,
                fireAt = fireDateTime,
                body = checkpoint.body
            )
        }
    }
}
