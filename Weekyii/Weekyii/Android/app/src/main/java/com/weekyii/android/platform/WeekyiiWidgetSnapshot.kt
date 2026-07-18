package com.weekyii.android.platform

import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.DayWithTasks
import com.weekyii.android.data.db.entities.TaskZone
import java.time.LocalDate

data class WeekyiiWidgetSnapshot(
    val dateLabel: String,
    val statusLabel: String,
    val focusTitle: String,
    val frozenCount: Int,
    val killTimeLabel: String
) {
    companion object {
        fun from(day: DayWithTasks?, date: LocalDate): WeekyiiWidgetSnapshot {
            if (day == null) return WeekyiiWidgetSnapshot(
                dateLabel = date.toString(),
                statusLabel = "未创建",
                focusTitle = "今天还没有任务流",
                frozenCount = 0,
                killTimeLabel = "20:00"
            )
            val focus = day.tasks.firstOrNull { it.zone == TaskZone.FOCUS }
            return WeekyiiWidgetSnapshot(
                dateLabel = date.toString(),
                statusLabel = when (day.day.status) {
                    DayStatus.EMPTY -> "空白"
                    DayStatus.DRAFT -> "草稿"
                    DayStatus.EXECUTE -> "执行中"
                    DayStatus.COMPLETED -> "已完成"
                    DayStatus.EXPIRED -> "已过期"
                },
                focusTitle = focus?.title ?: if (day.day.status == DayStatus.COMPLETED) "今日任务已完成" else "当前没有专注任务",
                frozenCount = day.tasks.count { it.zone == TaskZone.FROZEN },
                killTimeLabel = "%02d:%02d".format(day.day.killHour, day.day.killMinute)
            )
        }
    }
}
