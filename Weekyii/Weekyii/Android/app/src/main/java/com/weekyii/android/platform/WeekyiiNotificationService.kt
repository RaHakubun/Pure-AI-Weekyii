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
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.weekyii.android.R

class WeekyiiNotificationService(private val context: Context) {
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

    fun notifyKillTime(dayId: String, killTimeText: String, unfinishedCount: Int) {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Weekyii Kill Time")
            .setContentText("今天还有 $unfinishedCount 项，截止时间 $killTimeText")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify(dayId.hashCode(), notification)
    }

    fun scheduleKillTime(dayId: String, at: LocalDateTime, unfinishedCount: Int) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val intent = Intent(context, WeekyiiAlarmReceiver::class.java).apply {
            action = WeekyiiAlarmReceiver.ACTION_KILL_TIME
            putExtra(WeekyiiAlarmReceiver.EXTRA_DAY_ID, dayId)
            putExtra(WeekyiiAlarmReceiver.EXTRA_KILL_TIME, "%02d:%02d".format(at.hour, at.minute))
            putExtra(WeekyiiAlarmReceiver.EXTRA_UNFINISHED_COUNT, unfinishedCount)
        }
        val pending = PendingIntent.getBroadcast(context, dayId.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val trigger = at.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending)
    }

    fun cancelKillTime(dayId: String) {
        val intent = Intent(context, WeekyiiAlarmReceiver::class.java).apply { action = WeekyiiAlarmReceiver.ACTION_KILL_TIME }
        val pending = PendingIntent.getBroadcast(context, dayId.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        context.getSystemService(AlarmManager::class.java).cancel(pending)
    }
}
