package com.weekyii.android.ui.screens.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.weekyii.android.ui.viewmodel.TodayViewModel

@Composable
fun TodayScreen(viewModel: TodayViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(text = "今天：${state.date}")
        Text(text = "状态：${state.day?.status ?: "empty"}")
        Text(text = "Focus：${state.focus?.title ?: "无"}")
        Text(text = "Frozen：${state.frozen.joinToString { it.title }}")
        Text(text = "Complete：${state.complete.joinToString { it.title }}")

        Button(onClick = { viewModel.startDay() }) { Text("开始今天") }
        Button(onClick = { viewModel.doneFocus() }) { Text("完成当前") }
        Spacer(Modifier.height(8.dp))
        if (state.error != null) {
            Text(text = state.error!!)
        }
    }
}
