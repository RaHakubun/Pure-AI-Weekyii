package com.weekyii.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.weekyii.android.ui.theme.WeekyiiDimensions
import androidx.compose.material3.Icon
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.layout.Arrangement

@Composable
fun WeekyiiSegmentedControl(
    items: List<String>,
    selectedIndex: Int,
    onSelectedIndexChange: (Int) -> Unit,
    icons: List<ImageVector?> = emptyList(),
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(WeekyiiDimensions.radiusFull)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .border(WeekyiiDimensions.hairline, MaterialTheme.colorScheme.outline.copy(alpha = 0.18f), shape)
            .background(MaterialTheme.colorScheme.surface, shape)
            .padding(WeekyiiDimensions.segmentedInset),
        verticalAlignment = Alignment.CenterVertically
    ) {
        items.forEachIndexed { index, item ->
            val selected = index == selectedIndex
            Box(
                modifier = Modifier
                    .weight(1f)
                    .semantics { this.selected = selected }
                    .background(
                        if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surface,
                        RoundedCornerShape(WeekyiiDimensions.radiusFull)
                    )
                    .clickable(role = Role.Tab, onClick = { onSelectedIndexChange(index) })
                    .padding(vertical = WeekyiiDimensions.segmentedVerticalPadding),
                contentAlignment = Alignment.Center
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    icons.getOrNull(index)?.let { icon ->
                        Icon(
                            icon,
                            contentDescription = null,
                            tint = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Text(
                        item,
                        color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.titleMedium
                    )
                }
            }
        }
    }
}
