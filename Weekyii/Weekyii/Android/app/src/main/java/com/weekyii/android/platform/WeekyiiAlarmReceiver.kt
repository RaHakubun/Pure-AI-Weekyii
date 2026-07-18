package com.weekyii.android.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class WeekyiiAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_KILL_TIME) return
        WeekyiiNotificationService(context).apply {
            ensureChannel()
            notifyKillTime(
                dayId = intent.getStringExtra(EXTRA_DAY_ID) ?: return,
                killTimeText = intent.getStringExtra(EXTRA_KILL_TIME) ?: "20:00",
                unfinishedCount = intent.getIntExtra(EXTRA_UNFINISHED_COUNT, 0)
            )
        }
    }

    companion object {
        const val ACTION_KILL_TIME = "com.weekyii.android.action.KILL_TIME"
        const val EXTRA_DAY_ID = "day_id"
        const val EXTRA_KILL_TIME = "kill_time"
        const val EXTRA_UNFINISHED_COUNT = "unfinished_count"
    }
}
