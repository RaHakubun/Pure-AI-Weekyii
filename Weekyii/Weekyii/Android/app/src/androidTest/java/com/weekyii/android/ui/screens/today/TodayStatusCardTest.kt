package com.weekyii.android.ui.screens.today

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.ui.theme.WeekyiiTheme
import java.time.LocalDate
import org.junit.Rule
import org.junit.Test

class TodayStatusCardTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun statusCardCommunicatesEveryTodayState() {
        val labels = mapOf(
            DayStatus.EMPTY to "空",
            DayStatus.DRAFT to "草稿",
            DayStatus.EXECUTE to "执行中",
            DayStatus.COMPLETED to "已完成",
            DayStatus.EXPIRED to "已过期"
        )
        var renderedStatus by mutableStateOf(DayStatus.EMPTY)
        composeRule.setContent {
            WeekyiiTheme {
                TodayStatusCard(renderedStatus, daysStartedCount = 3, date = LocalDate.of(2026, 7, 19))
            }
        }
        labels.forEach { (status, label) ->
            composeRule.runOnIdle { renderedStatus = status }
            composeRule.onNodeWithText(label).assertIsDisplayed()
            composeRule.onNodeWithText("已启动天数").assertIsDisplayed()
            composeRule.onNodeWithText("2026年7月19日").assertIsDisplayed()
        }
    }
}
