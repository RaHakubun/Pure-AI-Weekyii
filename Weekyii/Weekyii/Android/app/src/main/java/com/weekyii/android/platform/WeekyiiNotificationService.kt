package com.weekyii.android.platform

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
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
}
