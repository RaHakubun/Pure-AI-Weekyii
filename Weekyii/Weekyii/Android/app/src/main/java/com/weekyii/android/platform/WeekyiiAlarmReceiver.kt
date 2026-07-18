package com.weekyii.android.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class WeekyiiAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_SUSPENDED_CHECKPOINT) {
            val taskId = intent.getStringExtra(EXTRA_TASK_ID)?.let { runCatching { java.util.UUID.fromString(it) }.getOrNull() } ?: return
            WeekyiiNotificationService(context).apply {
                ensureChannel()
                notifySuspendedTask(taskId, intent.getStringExtra(EXTRA_MESSAGE) ?: "请处理悬置任务")
            }
            return
        }
        if (intent.action != ACTION_KILL_TIME) return
        WeekyiiNotificationService(context).apply {
            ensureChannel()
            notifyKillTime(
                dayId = intent.getStringExtra(EXTRA_DAY_ID) ?: return,
                killTimeText = intent.getStringExtra(EXTRA_KILL_TIME) ?: "20:00",
                unfinishedCount = intent.getIntExtra(EXTRA_UNFINISHED_COUNT, 0),
                preReminder = intent.getBooleanExtra(EXTRA_PRE_REMINDER, false),
                fixedReminder = intent.getBooleanExtra(EXTRA_FIXED_REMINDER, false)
            )
        }
    }

    companion object {
        const val ACTION_KILL_TIME = "com.weekyii.android.action.KILL_TIME"
        const val ACTION_SUSPENDED_CHECKPOINT = "com.weekyii.android.action.SUSPENDED_CHECKPOINT"
        const val EXTRA_DAY_ID = "day_id"
        const val EXTRA_KILL_TIME = "kill_time"
        const val EXTRA_UNFINISHED_COUNT = "unfinished_count"
        const val EXTRA_PRE_REMINDER = "pre_reminder"
        const val EXTRA_FIXED_REMINDER = "fixed_reminder"
        const val EXTRA_TASK_ID = "task_id"
        const val EXTRA_CHECKPOINT = "checkpoint"
        const val EXTRA_MESSAGE = "message"
    }
}
