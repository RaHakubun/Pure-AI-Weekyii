package com.weekyii.android.domain

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DataStoreUserSettingsParityTest {
    @Test
    fun futurePlanningPreferencesPersistAcrossStoreRecreation() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val first = DataStoreUserSettingsStore(context)
        val current = withTimeout(5_000) {
            combine(
                first.weekStartsOnMonday,
                first.pendingMonthShowRegular,
                first.pendingMonthShowDDL,
                first.pendingMonthShowLeisure
            ) { monday, regular, ddl, leisure -> listOf(monday, regular, ddl, leisure) }
                .first()
        }
        try {
            first.setWeekStartsOnMonday(false)
            first.setPendingMonthMarkers(regular = false, ddl = true, leisure = false)

            val recreated = DataStoreUserSettingsStore(context)
            val restored = withTimeout(5_000) {
                combine(
                    recreated.weekStartsOnMonday,
                    recreated.pendingMonthShowRegular,
                    recreated.pendingMonthShowDDL,
                    recreated.pendingMonthShowLeisure
                ) { monday, regular, ddl, leisure -> listOf(monday, regular, ddl, leisure) }
                    .first { it == listOf(false, false, true, false) }
            }
            assertEquals(listOf(false, false, true, false), restored)
        } finally {
            first.setWeekStartsOnMonday(current[0])
            first.setPendingMonthMarkers(current[1], current[2], current[3])
        }
    }
}
