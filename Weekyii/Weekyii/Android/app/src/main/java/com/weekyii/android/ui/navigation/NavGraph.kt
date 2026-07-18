package com.weekyii.android.ui.navigation

import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Upcoming
import androidx.compose.material.icons.filled.Extension

sealed class NavItem(val route: String, val label: String, val icon: ImageVector) {
    object Today : NavItem("today", "今天", Icons.Filled.CalendarToday)
    object Pending : NavItem("pending", "未来", Icons.Filled.Upcoming)
    object Past : NavItem("past", "过去", Icons.Filled.History)
    object Extensions : NavItem("extensions", "拓展", Icons.Filled.Extension)
    object Settings : NavItem("settings", "设置", Icons.Filled.Settings)

    companion object {
        val items = listOf(Today, Pending, Past, Extensions, Settings)
    }
}

@Composable
fun WeekyiiNavBar(items: List<NavItem>, currentRoute: String?, onClick: (String) -> Unit) {
    NavigationBar {
        items.forEach { item ->
            NavigationBarItem(
                selected = currentRoute == item.route,
                onClick = { onClick(item.route) },
                icon = { Icon(item.icon, contentDescription = item.label) },
                label = { Text(item.label) }
            )
        }
    }
}
