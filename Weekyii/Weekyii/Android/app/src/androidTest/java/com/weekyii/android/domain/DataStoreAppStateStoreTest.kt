package com.weekyii.android.domain

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.time.LocalDate
import java.time.LocalDateTime

@RunWith(AndroidJUnit4::class)
class DataStoreAppStateStoreTest {
    @Test
    fun recreatedStoreExposesPersistedStateImmediately() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val expectedDate = LocalDate.of(2026, 7, 19)
        val expectedRollover = LocalDateTime.of(2026, 7, 19, 3, 51)
        val firstStore = DataStoreAppStateStore(context)
        firstStore.setLastProcessedDate(expectedDate)
        firstStore.setLastRollover(expectedRollover)

        val recreatedStore = DataStoreAppStateStore(context)

        assertEquals(expectedDate, recreatedStore.lastProcessedDate.value)
        assertEquals(expectedRollover, recreatedStore.lastRolloverAt.value)
    }
}
