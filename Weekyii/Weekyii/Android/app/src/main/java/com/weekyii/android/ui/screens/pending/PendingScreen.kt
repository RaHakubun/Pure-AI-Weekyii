package com.weekyii.android.ui.screens.pending

import android.app.DatePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.model.WeekUi
import com.weekyii.android.ui.viewmodel.PendingViewModel
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter

@Composable
fun PendingScreen(viewModel: PendingViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val summaries = viewModel.monthDaySummaries()
    val cells = PendingViewModel.buildMonthCells(state.selectedMonth, summaries)
    val selectedWeek = state.pendingWeeks.firstOrNull { it.weekId == state.selectedWeekId }
    val selectedDay = selectedWeek?.days?.firstOrNull { it.dayId == state.selectedDayId }
    var selectedDate by remember { mutableStateOf(LocalDate.now().plusWeeks(1)) }
    var weekId by remember { mutableStateOf(state.nextWeekId) }
    var newTaskTitle by remember { mutableStateOf("") }
    var newTaskDescription by remember { mutableStateOf("") }
    var newTaskType by remember { mutableStateOf("regular") }
    var editingTask by remember { mutableStateOf<TaskUi?>(null) }

    LaunchedEffect(state.nextWeekId) { if (weekId.isBlank()) weekId = state.nextWeekId }
    LaunchedEffect(selectedDay?.dayId) {
        newTaskTitle = ""
        newTaskDescription = ""
        newTaskType = "regular"
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("未来计划", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text("先看整月节奏，再打开某一周编辑未来日。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            MonthCalendar(
                month = state.selectedMonth,
                cells = cells,
                onPrevious = viewModel::selectPreviousMonth,
                onNext = viewModel::selectNextMonth,
                onDateClick = { date ->
                    if (!date.isBefore(state.currentDate)) viewModel.openOrCreateDate(date)
                }
            )
        }
        state.error?.let { message -> item { Text(message, color = MaterialTheme.colorScheme.error) } }
        if (selectedWeek != null) {
            item {
                WeekOutlookCard(
                    week = selectedWeek,
                    snapshot = PendingViewModel.buildWeekOutlook(selectedWeek),
                    onClose = viewModel::closeWeek
                )
            }
            item {
                FutureDayEditor(
                    days = selectedWeek.days,
                    day = selectedDay,
                    definitions = state.taskTypeDefinitions,
                    newTitle = newTaskTitle,
                    onNewTitle = { newTaskTitle = it },
                    newDescription = newTaskDescription,
                    onNewDescription = { newTaskDescription = it },
                    newTypeId = newTaskType,
                    onNewTypeId = { newTaskType = it },
                    onSelectDay = viewModel::selectDay,
                    onAdd = {
                        viewModel.addDraftTask(selectedDay!!.dayId, newTaskTitle, newTaskDescription, newTaskType)
                        newTaskTitle = ""
                        newTaskDescription = ""
                    },
                    onEdit = { editingTask = it },
                    onDelete = { viewModel.deleteDraftTask(selectedDay!!.dayId, it.id) },
                    onMoveUp = { index -> viewModel.moveDraftTask(selectedDay!!.dayId, index, index - 1) },
                    onMoveDown = { index -> viewModel.moveDraftTask(selectedDay!!.dayId, index, index + 1) }
                )
            }
        } else {
            item { Text("点击月历中的未来日期，打开或创建对应周。", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        item {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("创建未来周", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            DatePickerDialog(context, { _, year, month, day ->
                                selectedDate = LocalDate.of(year, month + 1, day)
                                viewModel.createWeekForDate(selectedDate)
                            }, selectedDate.year, selectedDate.monthValue - 1, selectedDate.dayOfMonth).show()
                        }) { Text("按日期创建") }
                        OutlinedButton(onClick = viewModel::createNextWeek) { Text("创建下周") }
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
        item { Text("未来周", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
        if (state.pendingWeeks.isEmpty()) {
            item { Text("还没有预先规划的未来周。", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        } else {
            items(state.pendingWeeks, key = { it.weekId }) { week ->
                FutureWeekRow(week, selected = week.weekId == state.selectedWeekId) { viewModel.openWeek(week.weekId) }
            }
        }
    }

    editingTask?.let { task ->
        DraftTaskEditorDialog(
            task = task,
            definitions = state.taskTypeDefinitions,
            onDismiss = { editingTask = null },
            onSave = { title, description, typeId ->
                selectedDay?.let { day -> viewModel.updateDraftTask(day.dayId, task, title, description, typeId) }
                editingTask = null
            }
        )
    }
}

@Composable
private fun MonthCalendar(
    month: YearMonth,
    cells: List<PendingViewModel.MonthCell>,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onDateClick: (LocalDate) -> Unit
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onPrevious) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "上个月") }
                Text(month.format(DateTimeFormatter.ofPattern("yyyy年M月")), modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                IconButton(onClick = onNext) { Icon(Icons.AutoMirrored.Filled.ArrowForward, "下个月") }
            }
            Row(modifier = Modifier.fillMaxWidth()) {
                listOf("一", "二", "三", "四", "五", "六", "日").forEach { Text(it, modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelMedium) }
            }
            cells.chunked(7).forEach { row ->
                Row(modifier = Modifier.fillMaxWidth()) {
                    row.forEach { cell ->
                        MonthDayCell(cell, Modifier.weight(1f), onDateClick)
                    }
                }
            }
        }
    }
}

@Composable
private fun MonthDayCell(cell: PendingViewModel.MonthCell, modifier: Modifier, onClick: (LocalDate) -> Unit) {
    val summary = cell.summary
    val tint = if (cell.isInSelectedMonth) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = .35f)
    Column(
        modifier = modifier.padding(2.dp).height(58.dp).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = if (summary?.hasAnyRecord == true) .55f else .18f)).clickable { onClick(cell.date) }.padding(4.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(cell.date.dayOfMonth.toString(), color = tint, style = MaterialTheme.typography.labelLarge)
        if (summary != null && summary.taskCount > 0) {
            Text("${summary.regularCount}/${summary.ddlCount}/${summary.leisureCount}", color = tint, style = MaterialTheme.typography.labelSmall)
            if (summary.ddlCount > 0) Text("🔥", style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun WeekOutlookCard(week: WeekUi, snapshot: PendingViewModel.WeekOutlookSnapshot, onClose: () -> Unit) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("${week.weekId} 预报", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("${week.startDate} ~ ${week.endDate}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                TextButton(onClick = onClose) { Text("收起") }
            }
            Text(snapshot.headline, fontWeight = FontWeight.SemiBold)
            Text(snapshot.advice, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("常规 ${snapshot.typeCounts.regular} · DDL ${snapshot.typeCounts.ddl} · 休闲 ${snapshot.typeCounts.leisure}")
            if (snapshot.peakDays.isNotEmpty()) Text("峰值：${snapshot.peakDays.joinToString("、")}")
        }
    }
}

@Composable
private fun FutureWeekRow(week: WeekUi, selected: Boolean, onClick: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth().clickable(onClick = onClick), colors = CardDefaults.cardColors(containerColor = if (selected) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surface)) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(week.weekId, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text("${week.startDate} ~ ${week.endDate}", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("${week.days.count { it.tasks.isNotEmpty() }} 天有任务 · ${week.days.sumOf { it.tasks.size }} 项")
        }
    }
}

@Composable
private fun FutureDayEditor(
    days: List<DayUi>,
    day: DayUi?,
    definitions: List<TaskTypeDefinitionEntity>,
    newTitle: String,
    onNewTitle: (String) -> Unit,
    newDescription: String,
    onNewDescription: (String) -> Unit,
    newTypeId: String,
    onNewTypeId: (String) -> Unit,
    onSelectDay: (String) -> Unit,
    onAdd: () -> Unit,
    onEdit: (TaskUi) -> Unit,
    onDelete: (TaskUi) -> Unit,
    onMoveUp: (Int) -> Unit,
    onMoveDown: (Int) -> Unit
) {
    if (day == null) return
    val editable = day.status == DayStatus.DRAFT || day.status == DayStatus.EMPTY
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("${day.date} ${day.dayOfWeek}", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text(if (editable) "草稿可编辑" else "${day.status.name.lowercase()} · 只读", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                AssistChip(onClick = {}, label = { Text("${day.tasks.size} 项") })
            }
            Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                days.sortedBy { it.date }.forEach { candidate ->
                    FilterChip(
                        selected = candidate.dayId == day.dayId,
                        onClick = { onSelectDay(candidate.dayId) },
                        label = { Text("${candidate.dayOfWeek.take(3)}\n${candidate.date.dayOfMonth}") }
                    )
                }
            }
            if (day.tasks.isEmpty()) Text("这一天还没有任务。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            day.tasks.sortedBy { it.order }.forEachIndexed { index, task ->
                FutureTaskRow(task, editable, index > 0, index < day.tasks.lastIndex, onEdit, onDelete, onMoveUp, onMoveDown)
            }
            if (editable) {
                HorizontalDivider()
                OutlinedTextField(value = newTitle, onValueChange = onNewTitle, label = { Text("添加任务") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = newDescription, onValueChange = onNewDescription, label = { Text("备注（可选）") }, modifier = Modifier.fillMaxWidth())
                TypeChips(definitions, newTypeId, onNewTypeId)
                Button(onClick = onAdd, enabled = newTitle.isNotBlank(), modifier = Modifier.fillMaxWidth()) { Text("加入这一天") }
            }
        }
    }
}

@Composable
private fun FutureTaskRow(task: TaskUi, editable: Boolean, canMoveUp: Boolean, canMoveDown: Boolean, onEdit: (TaskUi) -> Unit, onDelete: (TaskUi) -> Unit, onMoveUp: (Int) -> Unit, onMoveDown: (Int) -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            Text("T${task.order.toString().padStart(2, '0')} · ${task.title}", fontWeight = FontWeight.SemiBold)
            if (task.description.isNotBlank()) Text(task.description, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
            Text(task.taskTypeIdRaw, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelSmall)
        }
        if (editable) {
            IconButton(onClick = { onMoveUp(task.order - 1) }, enabled = canMoveUp) { Icon(Icons.Filled.KeyboardArrowUp, "上移") }
            IconButton(onClick = { onMoveDown(task.order - 1) }, enabled = canMoveDown) { Icon(Icons.Filled.KeyboardArrowDown, "下移") }
            IconButton(onClick = { onEdit(task) }) { Icon(Icons.Filled.Edit, "编辑") }
            IconButton(onClick = { onDelete(task) }) { Icon(Icons.Filled.Delete, "删除") }
        }
    }
}

@Composable
private fun TypeChips(definitions: List<TaskTypeDefinitionEntity>, selectedId: String, onSelected: (String) -> Unit) {
    Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        val options = if (definitions.isEmpty()) {
            listOf("regular" to "常规", "ddl" to "DDL", "leisure" to "空闲")
        } else {
            definitions.map { it.idRaw to it.name }
        }
        options.take(4).forEach { (id, label) ->
            FilterChip(selected = selectedId == id, onClick = { onSelected(id) }, label = { Text(label) })
        }
    }
}

@Composable
private fun DraftTaskEditorDialog(task: TaskUi, definitions: List<TaskTypeDefinitionEntity>, onDismiss: () -> Unit, onSave: (String, String, String) -> Unit) {
    var title by remember(task.id) { mutableStateOf(task.title) }
    var description by remember(task.id) { mutableStateOf(task.description) }
    var typeId by remember(task.id) { mutableStateOf(task.taskTypeIdRaw) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("编辑未来任务") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("标题") }, singleLine = true)
                OutlinedTextField(value = description, onValueChange = { description = it }, label = { Text("备注") })
                TypeChips(definitions, typeId, { typeId = it })
            }
        },
        confirmButton = { TextButton(onClick = { onSave(title, description, typeId) }, enabled = title.isNotBlank()) { Text("保存") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } }
    )
}
