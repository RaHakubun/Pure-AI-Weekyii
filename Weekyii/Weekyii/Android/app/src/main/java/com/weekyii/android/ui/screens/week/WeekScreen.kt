package com.weekyii.android.ui.screens.week

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size
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
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.MyLocation
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.viewmodel.WeekViewModel
import com.weekyii.android.ui.components.WeekyiiCard
import com.weekyii.android.ui.components.WeekyiiSegmentedControl
import com.weekyii.android.ui.theme.WeekyiiDimensions
import java.time.LocalDate
import java.time.DayOfWeek

@Composable
fun WeekScreen(viewModel: WeekViewModel, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    val week = state.presentWeek
    var newTitle by remember { mutableStateOf("") }
    var newDescription by remember { mutableStateOf("") }
    var newType by remember { mutableStateOf("regular") }
    var editingTask by remember { mutableStateOf<TaskUi?>(null) }
    var showDayDetail by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = WeekyiiDimensions.screenPadding,
            vertical = WeekyiiDimensions.spacingBase
        ),
        verticalArrangement = Arrangement.spacedBy(WeekyiiDimensions.listGap)
    ) {
        if (week == null) {
            item { Text("当前周尚未准备好，请稍后重试。", color = MaterialTheme.colorScheme.error) }
        } else {
            val summaries = week.days.associate { it.dayId to WeekViewModel.buildDaySummary(it) }
            item {
                WeekStatsCard(week)
            }
            item {
                WeekTopologyCard(week, summaries, state.selectedDayId, onSelect = { dayId ->
                    viewModel.selectDay(dayId)
                    showDayDetail = true
                })
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(WeekyiiDimensions.spacingSmall)) {
                    Text("本周详情", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    val modes = listOf(
                        WeekViewModel.DisplayMode.CARDS,
                        WeekViewModel.DisplayMode.STRIPS,
                        WeekViewModel.DisplayMode.COLLAPSED
                    )
                    WeekyiiSegmentedControl(
                        items = listOf("当前状态", "信息横条", "折叠"),
                        selectedIndex = modes.indexOf(state.displayMode).coerceAtLeast(0),
                        onSelectedIndexChange = { viewModel.setDisplayMode(modes[it]) }
                    )
                }
            }
            when (state.displayMode) {
                WeekViewModel.DisplayMode.CARDS -> item {
                    Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        week.days.sortedBy { it.date }.forEach { day ->
                            WeekDayCard(day, summaries.getValue(day.dayId), day.dayId == state.selectedDayId) { viewModel.selectDay(day.dayId); showDayDetail = true }
                        }
                    }
                }
                WeekViewModel.DisplayMode.STRIPS -> items(week.days.sortedBy { it.date }, key = { it.dayId }) { day ->
                    WeekDayStrip(day, summaries.getValue(day.dayId), day.dayId == state.selectedDayId) { viewModel.selectDay(day.dayId); showDayDetail = true }
                }
                WeekViewModel.DisplayMode.COLLAPSED -> item {
                    Text("已折叠七日详情，点击上方“卡片”或“横条”展开。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            val selectedDay = week.days.firstOrNull { it.dayId == state.selectedDayId }
            if (selectedDay != null && showDayDetail) {
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
private fun WeekStatsCard(week: com.weekyii.android.ui.model.WeekUi) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.CalendarMonth, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("${week.startDate.monthValue}/${week.startDate.dayOfMonth} - ${week.endDate.monthValue}/${week.endDate.dayOfMonth}", modifier = Modifier.padding(start = 10.dp), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            val completedDays = week.days.count { it.status == DayStatus.COMPLETED }
            val completion = completedDays / week.days.size.coerceAtLeast(1).toFloat()
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.SpaceBetween) {
                Column {
                    Text("完成天数", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("$completedDays/${week.days.size}", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.secondary)
                }
                Column(horizontalAlignment = Alignment.End, modifier = Modifier.weight(1f).padding(start = WeekyiiDimensions.spacingExtraLarge)) {
                    Text("${(completion * 100).toInt()}%", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                    Box(
                        modifier = Modifier.fillMaxWidth().height(8.dp).background(MaterialTheme.colorScheme.surfaceVariant, androidx.compose.foundation.shape.RoundedCornerShape(WeekyiiDimensions.radiusSmall))
                    ) {
                        Box(
                            modifier = Modifier.fillMaxWidth(completion).height(8.dp).background(MaterialTheme.colorScheme.primary, androidx.compose.foundation.shape.RoundedCornerShape(WeekyiiDimensions.radiusSmall))
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun WeekTopologyCard(
    week: com.weekyii.android.ui.model.WeekUi,
    summaries: Map<String, WeekViewModel.DaySummary>,
    selectedDayId: String?,
    onSelect: (String) -> Unit
) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
        val sortedDays = week.days.sortedBy { it.date }
        val density = LocalDensity.current
        val outline = MaterialTheme.colorScheme.outline.copy(alpha = 0.34f)
        val surface = MaterialTheme.colorScheme.surface
        val primary = MaterialTheme.colorScheme.tertiary
        val fontScale = density.fontScale.coerceAtLeast(1f)
        val topologyHeight = (286f * fontScale).dp
        val dayStripHeight = (132f * fontScale).dp
        val dayStripWidth = 364.dp
        Column(verticalArrangement = Arrangement.spacedBy(WeekyiiDimensions.spacingMedium)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.MyLocation, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("本周拓扑", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).padding(start = 8.dp))
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(topologyHeight)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.18f), androidx.compose.foundation.shape.RoundedCornerShape(WeekyiiDimensions.radiusMedium))
                    .border(WeekyiiDimensions.hairline, MaterialTheme.colorScheme.surfaceVariant, androidx.compose.foundation.shape.RoundedCornerShape(WeekyiiDimensions.radiusMedium))
                    .padding(horizontal = WeekyiiDimensions.spacingSmall, vertical = WeekyiiDimensions.spacingMedium)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(dayStripHeight)
                        .horizontalScroll(rememberScrollState())
                ) {
                    Box(modifier = Modifier.width(dayStripWidth).height(dayStripHeight)) {
                        Canvas(modifier = Modifier.width(dayStripWidth).height(72.dp)) {
                            val radius = with(density) { 22.dp.toPx() }
                            val innerRadius = with(density) { 10.dp.toPx() }
                            val y = size.height * 0.45f
                            val step = size.width / sortedDays.size
                            drawLine(
                                color = outline,
                                start = Offset(step / 2f, y),
                                end = Offset(size.width - step / 2f, y),
                                strokeWidth = with(density) { 6.dp.toPx() }
                            )
                            sortedDays.forEachIndexed { index, day ->
                                val x = step * index + step / 2f
                                val isToday = day.date == LocalDate.now()
                                drawCircle(surface, radius, Offset(x, y))
                                drawCircle(outline, radius, Offset(x, y), style = Stroke(with(density) { 5.dp.toPx() }))
                                drawCircle(outline, innerRadius, Offset(x, y), style = Stroke(with(density) { 2.dp.toPx() }))
                                if (isToday) {
                                    drawCircle(
                                        primary,
                                        radius + with(density) { 5.dp.toPx() },
                                        Offset(x, y),
                                        style = Stroke(
                                            width = with(density) { 2.dp.toPx() },
                                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 7f))
                                        )
                                    )
                                }
                            }
                        }
                        Row(modifier = Modifier.width(dayStripWidth).height(dayStripHeight)) {
                            sortedDays.forEach { day ->
                                val selected = day.dayId == selectedDayId
                                val summary = summaries[day.dayId]
                                Column(
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(WeekyiiDimensions.spacingExtraSmall),
                                    modifier = Modifier
                                        .width(52.dp)
                                        .heightIn(min = WeekyiiDimensions.minimumTouchTarget)
                                        .clickable { onSelect(day.dayId) }
                                ) {
                                    Spacer(Modifier.height(48.dp))
                                    Text(
                                        "${day.date.dayOfMonth} ${day.date.dayOfWeek.shortChineseName()}",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                        fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
                                        maxLines = 1
                                    )
                                    Text(
                                        if (summary?.highlightKind == WeekViewModel.DayHighlightKind.EMPTY) "空" else "${summary?.completedCount ?: 0}/${summary?.remainingCount ?: 0}",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
                val total = summaries.values.sumOf { it.remainingCount + it.completedCount + it.forgottenCount }
                val completed = summaries.values.sumOf { it.completedCount }
                val remaining = summaries.values.sumOf { it.remainingCount }
                val forgotten = summaries.values.sumOf { it.forgottenCount }
                Column(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surface, androidx.compose.foundation.shape.RoundedCornerShape(WeekyiiDimensions.radiusMedium))
                        .border(WeekyiiDimensions.hairline, MaterialTheme.colorScheme.surfaceVariant, androidx.compose.foundation.shape.RoundedCornerShape(WeekyiiDimensions.radiusMedium))
                        .padding(WeekyiiDimensions.spacingMedium),
                    verticalArrangement = Arrangement.spacedBy(WeekyiiDimensions.spacingSmall)
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(WeekyiiDimensions.spacingExtraSmall)) {
                        Text("整周概览", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                        Text("完成率 ${if (total == 0) 0 else completed * 100 / total}%", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Row(modifier = Modifier.fillMaxWidth()) {
                        WeekMetric("总", total)
                        WeekMetric("剩", remaining)
                        WeekMetric("成", completed)
                        WeekMetric("忘", forgotten)
                    }
                }
            }
        }
    }
}

private fun DayOfWeek.shortChineseName(): String = when (this) {
    DayOfWeek.MONDAY -> "周一"
    DayOfWeek.TUESDAY -> "周二"
    DayOfWeek.WEDNESDAY -> "周三"
    DayOfWeek.THURSDAY -> "周四"
    DayOfWeek.FRIDAY -> "周五"
    DayOfWeek.SATURDAY -> "周六"
    DayOfWeek.SUNDAY -> "周日"
}

@Composable
private fun RowScope.WeekMetric(label: String, value: Int) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.weight(1f)) {
        Text(value.toString(), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
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
