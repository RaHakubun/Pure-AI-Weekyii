package com.weekyii.android.ui.screens.pending

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.ui.model.WeekUi
import com.weekyii.android.ui.viewmodel.PendingViewModel
import java.time.LocalDate

@Composable
fun PendingScreen(viewModel: PendingViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var selectedDate by remember { mutableStateOf(LocalDate.now().plusWeeks(1)) }
    var weekId by remember { mutableStateOf(state.nextWeekId) }
    LaunchedEffect(state.nextWeekId) {
        if (weekId.isBlank()) weekId = state.nextWeekId
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("未来计划", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text("提前创建某个日期所属的整周，进入当前周后会自动晋级为首页。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("创建未来周", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            DatePickerDialog(
                                context,
                                { _, year, month, day ->
                                    selectedDate = LocalDate.of(year, month + 1, day)
                                    viewModel.createWeekForDate(selectedDate)
                                },
                                selectedDate.year,
                                selectedDate.monthValue - 1,
                                selectedDate.dayOfMonth
                            ).show()
                        }) { Text("按日期创建") }
                        OutlinedButton(onClick = { viewModel.createNextWeek() }) { Text("创建下周") }
                    }
                    OutlinedTextField(
                        value = weekId,
                        onValueChange = { weekId = it },
                        label = { Text("周编号，例如 2026-W31") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Button(onClick = { viewModel.createWeekById(weekId.trim()) }, enabled = weekId.isNotBlank()) {
                        Text("按周编号创建")
                    }
                }
            }
        }
        state.error?.let { message -> item { Text(message, color = MaterialTheme.colorScheme.error) } }
        if (state.pendingWeeks.isEmpty()) {
            item { Text("还没有预先规划的未来周。", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        } else {
            items(state.pendingWeeks, key = { it.weekId }) { week -> PendingWeekCard(week) }
        }
    }
}

@Composable
private fun PendingWeekCard(week: WeekUi) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(week.weekId, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("${week.startDate} ~ ${week.endDate}", color = MaterialTheme.colorScheme.onSurfaceVariant)
            week.days.sortedBy { it.date }.forEach { day ->
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("${day.dayOfWeek} ${day.date}")
                    Text(day.status.name.lowercase())
                }
            }
        }
    }
}
