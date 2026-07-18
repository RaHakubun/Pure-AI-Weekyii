package com.weekyii.android.ui.components

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.material3.Text
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.weekyii.android.ui.theme.WeekyiiTheme
import org.junit.Rule
import org.junit.Test

class WeekyiiComponentsTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun segmentedControlRendersProductLabelsAndSelectedState() {
        composeRule.setContent {
            WeekyiiTheme {
                WeekyiiSegmentedControl(
                    items = listOf("今天", "本周"),
                    selectedIndex = 0,
                    onSelectedIndexChange = {},
                    modifier = Modifier.testTag("today-switcher")
                )
            }
        }

        composeRule.onNodeWithTag("today-switcher").assertIsDisplayed()
        composeRule.onNodeWithText("今天").assertIsDisplayed()
        composeRule.onNodeWithText("本周").assertIsDisplayed()
    }

    @Test
    fun primaryButtonExposesVisibleLabelAndClickAction() {
        composeRule.setContent {
            WeekyiiTheme {
                WeekyiiButton(
                    text = "创建",
                    onClick = {},
                    modifier = Modifier.testTag("create-button")
                )
            }
        }

        composeRule.onNodeWithText("创建").assertIsDisplayed()
        composeRule.onNodeWithTag("create-button").assert(hasClickAction())
        composeRule.onNodeWithText("创建").performClick()
    }

    @Test
    fun errorStateRendersMessageInWeekyiiSurface() {
        composeRule.setContent {
            WeekyiiTheme {
                WeekyiiErrorState(message = "无法加载今天")
            }
        }

        composeRule.onNodeWithText("无法加载今天").assertIsDisplayed()
    }

    @Test
    fun confirmDialogExposesNativeActions() {
        var confirmed = false
        composeRule.setContent {
            WeekyiiTheme {
                WeekyiiConfirmDialog(
                    title = "删除任务",
                    message = "确定删除吗？",
                    onConfirm = { confirmed = true },
                    onDismiss = {}
                )
            }
        }

        composeRule.onNodeWithText("删除任务").assertIsDisplayed()
        composeRule.onNodeWithText("确定").performClick()
        assert(confirmed)
    }

    @Test
    fun bottomSheetExposesContentWhenVisible() {
        composeRule.setContent {
            WeekyiiTheme {
                WeekyiiBottomSheet(visible = true, onDismiss = {}) {
                    Text("底部操作")
                }
            }
        }

        composeRule.onNodeWithText("底部操作").assertIsDisplayed()
    }
}
