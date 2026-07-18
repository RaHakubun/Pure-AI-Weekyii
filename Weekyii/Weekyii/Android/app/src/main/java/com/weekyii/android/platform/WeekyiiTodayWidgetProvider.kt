package com.weekyii.android.platform

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.weekyii.android.R
import com.weekyii.android.WeekyiiApplication
import com.weekyii.android.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate

class WeekyiiTodayWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                val app = context.applicationContext as? WeekyiiApplication
                val today = LocalDate.now()
                val day = runCatching { app?.repository?.getDayWithTasks(today.toString()) }.getOrNull()
                val snapshot = WeekyiiWidgetSnapshot.from(day, today)
                withContext(Dispatchers.Main) {
                    appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, render(context, snapshot)) }
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, WeekyiiTodayWidgetProvider::class.java))
            onUpdate(context, manager, ids)
        }
    }

    private fun render(context: Context, snapshot: WeekyiiWidgetSnapshot): RemoteViews = RemoteViews(
        context.packageName,
        R.layout.widget_today
    ).apply {
        setTextViewText(R.id.widget_date, "Weekyii · ${snapshot.dateLabel}")
        setTextViewText(R.id.widget_status, snapshot.statusLabel)
        setTextViewText(R.id.widget_focus, snapshot.focusTitle)
        setTextViewText(R.id.widget_frozen, "冻结区 ${snapshot.frozenCount} 项")
        setTextViewText(R.id.widget_kill_time, "Kill Time ${snapshot.killTimeLabel}")
        val launch = Intent(context, MainActivity::class.java)
        setOnClickPendingIntent(
            R.id.widget_root,
            android.app.PendingIntent.getActivity(
                context,
                0,
                launch,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
        )
    }

    companion object {
        const val ACTION_REFRESH = "com.weekyii.android.action.WIDGET_REFRESH"

        fun requestRefresh(context: Context) {
            context.sendBroadcast(Intent(context, WeekyiiTodayWidgetProvider::class.java).setAction(ACTION_REFRESH))
        }
    }
}
