package com.weekyii.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
fun StatusBadge(
    text: String,
    color: Color,
    contentColor: Color = Color.White,
    contentPadding: PaddingValues = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
) {
    Text(
        text = text,
        color = contentColor,
        fontWeight = FontWeight.Medium,
        modifier = Modifier
            .background(color, RoundedCornerShape(12.dp))
            .padding(contentPadding)
    )
}
