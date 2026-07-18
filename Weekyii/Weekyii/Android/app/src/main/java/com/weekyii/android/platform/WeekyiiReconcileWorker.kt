package com.weekyii.android.platform

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.weekyii.android.WeekyiiApplication

class WeekyiiReconcileWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val app = applicationContext as? WeekyiiApplication ?: return Result.failure()
        return runCatching {
            app.stateMachine.reconcile(force = false)
            Result.success()
        }.getOrElse { Result.retry() }
    }
}
