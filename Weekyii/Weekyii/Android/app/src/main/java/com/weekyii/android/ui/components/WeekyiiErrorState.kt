package com.weekyii.android.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.weekyii.android.ui.theme.WeekyiiDimensions

@Composable
fun WeekyiiErrorState(
    message: String,
    modifier: Modifier = Modifier
) {
    WeekyiiCard(modifier = modifier, accentColor = MaterialTheme.colorScheme.error) {
        Row(
            modifier = Modifier.padding(vertical = WeekyiiDimensions.spacingSmall),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(WeekyiiDimensions.spacingSmall)
        ) {
            Icon(Icons.Filled.ErrorOutline, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            Text(message, color = MaterialTheme.colorScheme.onSurface)
        }
    }
}
