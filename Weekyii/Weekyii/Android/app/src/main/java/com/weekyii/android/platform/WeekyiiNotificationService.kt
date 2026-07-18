package com.weekyii.android.platform

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Intent
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.weekyii.android.R

interface SuspendedNotificationScheduler {
    fun scheduleSuspendedTask(taskId: UUID, decisionDeadline: LocalDateTime)
    fun cancelSuspendedTask(taskId: UUID)
}

class WeekyiiNotificationService(private val context: Context) : SuspendedNotificationScheduler {
    companion object {
        const val CHANNEL_ID = "weekyii_deadlines"
        private const val CHANNEL_NAME = "Weekyii 截止提醒"
    }

    fun ensureChannel() {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "任务 Kill Time 与状态推进提醒"
            }
        )
    }

    fun notifyKillTime(dayId: String, killTimeText: String, unfinishedCount: Int, preReminder: Boolean = false, fixedReminder: Boolean = false) {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(when {
                fixedReminder -> "Weekyii 固定提醒"
                preReminder -> "Weekyii 提前提醒"
                else -> "Weekyii Kill Time"
            })
            .setContentText(
                if (fixedReminder) "固定时刻提醒：当前还有 $unfinishedCount 项待处理"
                else if (preReminder) "距离截止还有 $killTimeText，当前还有 $unfinishedCount 项"
                else "今天还有 $unfinishedCount 项，截止时间 $killTimeText"
            )
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify(dayId.hashCode(), notification)
    }

    fun scheduleKillTime(
        dayId: String,
        at: LocalDateTime,
        unfinishedCount: Int,
        reminderMinutes: Int = 0,
        fixedReminderEnabled: Boolean = false,
        fixedReminderAt: LocalDateTime? = null
    ) {
        cancelKillTime(dayId)
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        fun schedule(triggerAt: LocalDateTime, requestCode: Int, preReminder: Boolean, fixedReminder: Boolean) {
            val intent = Intent(context, WeekyiiAlarmReceiver::class.java).apply {
                action = WeekyiiAlarmReceiver.ACTION_KILL_TIME
                putExtra(WeekyiiAlarmReceiver.EXTRA_DAY_ID, dayId)
                putExtra(WeekyiiAlarmReceiver.EXTRA_KILL_TIME, "%02d:%02d".format(at.hour, at.minute))
                putExtra(WeekyiiAlarmReceiver.EXTRA_UNFINISHED_COUNT, unfinishedCount)
                putExtra(WeekyiiAlarmReceiver.EXTRA_PRE_REMINDER, preReminder)
                putExtra(WeekyiiAlarmReceiver.EXTRA_FIXED_REMINDER, fixedReminder)
            }
            val pending = PendingIntent.getBroadcast(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val trigger = triggerAt.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            if (trigger > System.currentTimeMillis()) alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending)
        }
        schedule(at, dayId.hashCode(), preReminder = false, fixedReminder = false)
        if (unfinishedCount > 0 && reminderMinutes > 0) {
            val preAt = at.minusMinutes(reminderMinutes.toLong())
            schedule(preAt, dayId.hashCode() + 1, preReminder = true, fixedReminder = false)
        }
        if (unfinishedCount > 0 && fixedReminderEnabled && fixedReminderAt != null) {
            schedule(fixedReminderAt, dayId.hashCode() + 2, preReminder = false, fixedReminder = true)
        }
        WeekyiiTodayWidgetProvider.requestRefresh(context)
    }

    fun cancelKillTime(dayId: String) {
        val intent = Intent(context, WeekyiiAlarmReceiver::class.java).apply { action = WeekyiiAlarmReceiver.ACTION_KILL_TIME }
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        listOf(dayId.hashCode(), dayId.hashCode() + 1, dayId.hashCode() + 2).forEach { requestCode ->
            val pending = PendingIntent.getBroadcast(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            alarmManager.cancel(pending)
        }
        WeekyiiTodayWidgetProvider.requestRefresh(context)
    }

    override fun scheduleSuspendedTask(taskId: UUID, decisionDeadline: LocalDateTime) {
        cancelSuspendedTask(taskId)
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        WeekyiiReminderPlanner.suspendedTaskPlan(taskId, decisionDeadline, LocalDateTime.now(), ZoneId.systemDefault())
            .forEach { item ->
                val intent = Intent(context, WeekyiiAlarmReceiver::class.java).apply {
                    action = WeekyiiAlarmReceiver.ACTION_SUSPENDED_CHECKPOINT
                    putExtra(WeekyiiAlarmReceiver.EXTRA_TASK_ID, taskId.toString())
                    putExtra(WeekyiiAlarmReceiver.EXTRA_CHECKPOINT, item.suffix)
                    putExtra(WeekyiiAlarmReceiver.EXTRA_MESSAGE, item.body)
                }
                val pending = PendingIntent.getBroadcast(
                    context,
                    suspendedRequestCode(taskId, item.suffix),
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val trigger = item.fireAt.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending)
            }
    }

    override fun cancelSuspendedTask(taskId: UUID) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        listOf("d3", "d1", "d0m", "d0e", "0", "1", "2").forEach { suffix ->
            val intent = Intent(context, WeekyiiAlarmReceiver::class.java).apply {
                action = WeekyiiAlarmReceiver.ACTION_SUSPENDED_CHECKPOINT
                putExtra(WeekyiiAlarmReceiver.EXTRA_TASK_ID, taskId.toString())
                putExtra(WeekyiiAlarmReceiver.EXTRA_CHECKPOINT, suffix)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                suspendedRequestCode(taskId, suffix),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pending)
        }
    }

    fun notifySuspendedTask(taskId: UUID, body: String) {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("悬置箱提醒")
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify("suspended-$taskId".hashCode(), notification)
    }

    private fun suspendedRequestCode(taskId: UUID, suffix: String): Int = "suspended-$taskId-$suffix".hashCode()
}
