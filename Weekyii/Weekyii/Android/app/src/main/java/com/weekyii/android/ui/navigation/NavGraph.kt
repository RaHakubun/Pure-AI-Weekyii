package com.weekyii.android.ui.navigation

import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Extension
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.shape.RoundedCornerShape
import com.weekyii.android.ui.theme.WeekyiiDimensions

sealed class NavItem(val route: String, val label: String, val icon: ImageVector) {
    object Today : NavItem("today", "当下", Icons.Filled.WbSunny)
    object Pending : NavItem("pending", "未来", Icons.Filled.CalendarMonth)
    object Past : NavItem("past", "过去", Icons.Filled.History)
    object Extensions : NavItem("extensions", "扩展", Icons.Filled.Extension)
    object Settings : NavItem("settings", "我的", Icons.Filled.Settings)

    companion object {
        val items: List<NavItem>
            get() = listOf(Past, Today, Pending, Extensions, Settings)
    }
}

@Composable
fun WeekyiiNavBar(
    items: List<NavItem>,
    currentRoute: String?,
    modifier: Modifier = Modifier,
    onClick: (String) -> Unit
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(
                horizontal = WeekyiiDimensions.spacingMedium,
                vertical = WeekyiiDimensions.spacingSmall
            )
    ) {
        Surface(
            shape = RoundedCornerShape(WeekyiiDimensions.radiusExtraLarge),
            color = MaterialTheme.colorScheme.surface,
            shadowElevation = WeekyiiDimensions.floatingElevation,
            tonalElevation = WeekyiiDimensions.cardElevation
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(WeekyiiDimensions.bottomNavigationHeight)
                    .padding(WeekyiiDimensions.segmentedInset),
                verticalAlignment = Alignment.CenterVertically
            ) {
                items.forEach { item ->
                    val isSelected = currentRoute == item.route
                    val contentColor = if (isSelected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(WeekyiiDimensions.radiusFull))
                            .background(
                                if (isSelected) MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.76f)
                                else androidx.compose.ui.graphics.Color.Transparent
                            )
                            .semantics { selected = isSelected }
                            .clickable(role = Role.Tab) { onClick(item.route) }
                            .padding(vertical = WeekyiiDimensions.spacingSmall),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(
                            item.icon,
                            contentDescription = item.label,
                            tint = contentColor,
                            modifier = Modifier.size(WeekyiiDimensions.bottomNavigationIconSize)
                        )
                        Text(
                            item.label,
                            color = contentColor,
                            style = MaterialTheme.typography.labelMedium
                        )
                    }
                }
            }
        }
    }
}
