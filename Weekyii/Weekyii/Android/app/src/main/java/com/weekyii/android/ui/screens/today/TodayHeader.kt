package com.weekyii.android.ui.screens.today

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.weekyii.android.ui.components.WeekyiiHeader
import com.weekyii.android.ui.components.WeekyiiSegmentedControl

@Composable
fun TodayHeader(
    showWeek: Boolean,
    onShowWeekChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    androidx.compose.foundation.layout.Column(modifier = modifier) {
        WeekyiiHeader()
        WeekyiiSegmentedControl(
            items = listOf("当下", "本周"),
            selectedIndex = if (showWeek) 1 else 0,
            onSelectedIndexChange = { onShowWeekChange(it == 1) },
            icons = listOf(Icons.Filled.WbSunny, Icons.Filled.CalendarMonth)
        )
    }
}
