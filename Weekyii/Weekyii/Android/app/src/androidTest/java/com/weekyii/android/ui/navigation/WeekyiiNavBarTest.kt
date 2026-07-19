package com.weekyii.android.ui.navigation

import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.weekyii.android.ui.theme.WeekyiiTheme
import org.junit.Rule
import org.junit.Test

class WeekyiiNavBarTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun selectedDestinationUsesWeekyiiPillAndKeepsAccessibleNavigation() {
        var route = NavItem.Today.route
        composeRule.setContent {
            WeekyiiTheme {
                WeekyiiNavBar(
                    items = NavItem.items,
                    currentRoute = route,
                    onClick = { route = it },
                    modifier = Modifier.testTag("weekyii-nav")
                )
            }
        }

        composeRule.onNodeWithText("当下").assertIsDisplayed().assertIsSelected()
        composeRule.onNodeWithText("未来").performClick()
    }
}
