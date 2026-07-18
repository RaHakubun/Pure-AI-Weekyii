package com.weekyii.android.ui.screens.week

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.viewmodel.WeekViewModel
import com.weekyii.android.ui.components.WeekyiiCard
import java.time.LocalDate

@Composable
fun WeekScreen(viewModel: WeekViewModel, modifier: Modifier = Modifier, onBackToToday: (() -> Unit)? = null) {
    val state by viewModel.state.collectAsState()
    val week = state.presentWeek
    var newTitle by remember { mutableStateOf("") }
    var newDescription by remember { mutableStateOf("") }
    var newType by remember { mutableStateOf("regular") }
    var editingTask by remember { mutableStateOf<TaskUi?>(null) }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("本周", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                    Text(week?.weekId ?: "正在准备当前周", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (onBackToToday != null) AssistChip(onClick = onBackToToday, label = { Text("回到今天") })
                IconButton(onClick = {}) { Icon(Icons.Filled.Refresh, "刷新") }
            }
        }
        if (week == null) {
            item { Text("当前周尚未准备好，请稍后重试。", color = MaterialTheme.colorScheme.error) }
        } else {
            val summaries = week.days.associate { it.dayId to WeekViewModel.buildDaySummary(it) }
            val completed = week.days.sumOf { summaries[it.dayId]?.completedCount ?: 0 }
            val remaining = week.days.sumOf { summaries[it.dayId]?.remainingCount ?: 0 }
            val forgotten = week.days.sumOf { summaries[it.dayId]?.forgottenCount ?: 0 }
            item {
                WeekStatsCard(week, completed, remaining, forgotten)
            }
            item {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("周视图", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    FilterChip(selected = state.displayMode == WeekViewModel.DisplayMode.CARDS, onClick = { viewModel.setDisplayMode(WeekViewModel.DisplayMode.CARDS) }, label = { Text("卡片") })
                    FilterChip(selected = state.displayMode == WeekViewModel.DisplayMode.STRIPS, onClick = { viewModel.setDisplayMode(WeekViewModel.DisplayMode.STRIPS) }, label = { Text("横条") })
                    FilterChip(selected = state.displayMode == WeekViewModel.DisplayMode.COLLAPSED, onClick = { viewModel.setDisplayMode(WeekViewModel.DisplayMode.COLLAPSED) }, label = { Text("折叠") })
                }
            }
            when (state.displayMode) {
                WeekViewModel.DisplayMode.CARDS -> item {
                    Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        week.days.sortedBy { it.date }.forEach { day ->
                            WeekDayCard(day, summaries.getValue(day.dayId), day.dayId == state.selectedDayId) { viewModel.selectDay(day.dayId) }
                        }
                    }
                }
                WeekViewModel.DisplayMode.STRIPS -> items(week.days.sortedBy { it.date }, key = { it.dayId }) { day ->
                    WeekDayStrip(day, summaries.getValue(day.dayId), day.dayId == state.selectedDayId) { viewModel.selectDay(day.dayId) }
                }
                WeekViewModel.DisplayMode.COLLAPSED -> item {
                    Text("已折叠七日详情，点击上方“卡片”或“横条”展开。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            val selectedDay = week.days.firstOrNull { it.dayId == state.selectedDayId }
            if (selectedDay != null) {
                item {
                    WeekDayDetail(
                        day = selectedDay,
                        currentDate = state.currentDate,
                        typeDefinitions = state.taskTypeDefinitions,
                        newTitle = newTitle,
                        onNewTitle = { newTitle = it },
                        newDescription = newDescription,
                        onNewDescription = { newDescription = it },
                        newType = newType,
                        onNewType = { newType = it },
                        onAdd = {
                            viewModel.addDraftTask(selectedDay.dayId, newTitle, newDescription, newType)
                            newTitle = ""
                            newDescription = ""
                        },
                        onDelete = { viewModel.deleteDraftTask(selectedDay.dayId, it.id) },
                        onEdit = { editingTask = it },
                        onMove = { from, to -> viewModel.moveDraftTask(selectedDay.dayId, from, to) }
                    )
                }
            }
        }
    }

    editingTask?.let { task ->
        val selectedDay = week?.days?.firstOrNull { it.dayId == state.selectedDayId }
        WeekTaskEditorDialog(
            task = task,
            typeIds = if (state.taskTypeDefinitions.isEmpty()) listOf("regular", "ddl", "leisure") else state.taskTypeDefinitions.map { it.idRaw },
            onDismiss = { editingTask = null },
            onSave = { title, description, typeId ->
                selectedDay?.let { viewModel.updateDraftTask(it.dayId, task, title, description, typeId) }
                editingTask = null
            }
        )
    }
}

@Composable
private fun WeekStatsCard(week: com.weekyii.android.ui.model.WeekUi, completed: Int, remaining: Int, forgotten: Int) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.primary) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${week.startDate} ~ ${week.endDate}", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                WeekMetric("完成", completed)
                WeekMetric("剩余", remaining)
                WeekMetric("遗忘", forgotten)
                WeekMetric("启动", week.totalStartedDays)
            }
        }
    }
}

@Composable
private fun WeekMetric(label: String, value: Int) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value.toString(), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun WeekDayCard(day: DayUi, summary: WeekViewModel.DaySummary, selected: Boolean, onClick: () -> Unit) {
    WeekyiiCard(modifier = Modifier.width(184.dp).clickable(onClick = onClick), accentColor = if (selected) MaterialTheme.colorScheme.primary else null, fillWidth = false) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(day.dayOfWeek, style = MaterialTheme.typography.labelMedium)
            Text(day.date.dayOfMonth.toString(), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(day.status.name.lowercase(), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(summary.highlightText, maxLines = 2)
            Text("剩 ${summary.remainingCount} · 成 ${summary.completedCount} · 忘 ${summary.forgottenCount}", style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun WeekDayStrip(day: DayUi, summary: WeekViewModel.DaySummary, selected: Boolean, onClick: () -> Unit) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth().clickable(onClick = onClick), accentColor = if (selected) MaterialTheme.colorScheme.primary else null) {
        Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text("${day.dayOfWeek} ${day.date}", fontWeight = FontWeight.SemiBold)
                Text(summary.highlightText, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text("${summary.remainingCount}/${summary.completedCount}/${summary.forgottenCount}")
        }
    }
}

@Composable
private fun WeekDayDetail(
    day: DayUi,
    currentDate: LocalDate,
    typeDefinitions: List<com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity>,
    newTitle: String,
    onNewTitle: (String) -> Unit,
    newDescription: String,
    onNewDescription: (String) -> Unit,
    newType: String,
    onNewType: (String) -> Unit,
    onAdd: () -> Unit,
    onDelete: (TaskUi) -> Unit,
    onEdit: (TaskUi) -> Unit,
    onMove: (Int, Int) -> Unit
) {
    val editable = day.date >= currentDate && (day.status == DayStatus.EMPTY || day.status == DayStatus.DRAFT)
    WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("日程详情", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("${day.date} · ${if (editable) "草稿可编辑" else "${day.status.name.lowercase()} · 只读"}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            }
            day.tasks.sortedBy { it.order }.forEachIndexed { index, task ->
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("T${task.order.toString().padStart(2, '0')} · ${task.title}", fontWeight = FontWeight.SemiBold)
                        Text(task.taskTypeIdRaw, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                    }
                    if (editable) {
                        IconButton(enabled = index > 0, onClick = { onMove(index, index - 1) }) { Icon(Icons.Filled.KeyboardArrowUp, "上移") }
                        IconButton(enabled = index < day.tasks.lastIndex, onClick = { onMove(index, index + 1) }) { Icon(Icons.Filled.KeyboardArrowDown, "下移") }
                        IconButton(onClick = { onEdit(task) }) { Icon(Icons.Filled.Edit, "编辑") }
                        IconButton(onClick = { onDelete(task) }) { Icon(Icons.Filled.Delete, "删除") }
                    }
                }
            }
            if (editable) {
                OutlinedTextField(value = newTitle, onValueChange = onNewTitle, label = { Text("新增任务") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = newDescription, onValueChange = onNewDescription, label = { Text("备注") }, modifier = Modifier.fillMaxWidth())
                Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    val choices = if (typeDefinitions.isEmpty()) listOf("regular", "ddl", "leisure") else typeDefinitions.map { it.idRaw }
                    choices.forEach { id -> FilterChip(selected = newType == id, onClick = { onNewType(id) }, label = { Text(id) }) }
                }
                Button(onClick = onAdd, enabled = newTitle.isNotBlank(), modifier = Modifier.fillMaxWidth()) { Text("添加到这一天") }
            }
        }
    }
}

@Composable
private fun WeekTaskEditorDialog(task: TaskUi, typeIds: List<String>, onDismiss: () -> Unit, onSave: (String, String, String) -> Unit) {
    var title by remember(task.id) { mutableStateOf(task.title) }
    var description by remember(task.id) { mutableStateOf(task.description) }
    var typeId by remember(task.id) { mutableStateOf(task.taskTypeIdRaw) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("编辑任务") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("标题") })
                OutlinedTextField(value = description, onValueChange = { description = it }, label = { Text("备注") })
                Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    typeIds.forEach { id -> FilterChip(selected = typeId == id, onClick = { typeId = id }, label = { Text(id) }) }
                }
            }
        },
        confirmButton = { TextButton(onClick = { onSave(title, description, typeId) }, enabled = title.isNotBlank()) { Text("保存") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } }
    )
}
