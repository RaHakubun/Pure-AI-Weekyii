package com.weekyii.android.ui.screens.past

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.ui.model.WeekUi
import com.weekyii.android.ui.viewmodel.PastViewModel

@Composable
fun PastScreen(viewModel: PastViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("过去记录", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text("过期任务只保留数量，不展示已遗忘的任务详情。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("总体统计", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("完成 ${state.completedTasks} · 过期 ${state.expiredTasks} · 启动天数 ${state.startedDays}")
                    Text("完成率 ${state.completionRate}%", style = MaterialTheme.typography.headlineSmall)
                }
            }
        }
        if (state.pastWeeks.isEmpty()) {
            item { Text("还没有过去周记录。", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        } else {
            items(state.pastWeeks, key = { it.weekId }) { week -> PastWeekCard(week) }
        }
    }
}

@Composable
private fun PastWeekCard(week: WeekUi) {
    var expanded by remember { mutableStateOf(false) }
    Card(modifier = Modifier.fillMaxWidth(), onClick = { expanded = !expanded }) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(week.weekId, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text("${week.completedTasksCount} 完成 / ${week.expiredTasksCount} 过期")
            }
            Text("启动 ${week.totalStartedDays} 天", color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (expanded) {
                week.days.sortedBy { it.date }.forEach { day ->
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("${day.dayOfWeek} ${day.date}")
                        Text(if (day.status.name == "EXPIRED") "过期 ${day.expiredCount} 项" else day.status.name.lowercase())
                    }
                }
            }
        }
    }
}
