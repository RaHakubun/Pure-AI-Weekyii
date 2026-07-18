package com.weekyii.android.ui.screens.past

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.weekyii.android.ui.viewmodel.PastViewModel

@Composable
fun PastScreen(viewModel: PastViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
        Text("过去周")
        state.pastWeeks.forEach { week ->
            Text(text = "${week.weekId} 完成:${week.completedTasksCount} 过期:${week.expiredTasksCount}")
        }
    }
}
