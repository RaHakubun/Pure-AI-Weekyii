package com.weekyii.android.ui.screens.pending

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.weekyii.android.ui.viewmodel.PendingViewModel
import java.time.LocalDate

@Composable
fun PendingScreen(viewModel: PendingViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()

    Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
        Button(onClick = { viewModel.createWeekForDate(LocalDate.now().plusWeeks(1)) }) {
            Text("创建下周")
        }
        state.pendingWeeks.forEach { week ->
            Text(text = "${week.weekId} | ${week.status}")
        }
        state.error?.let { Text(it) }
    }
}
