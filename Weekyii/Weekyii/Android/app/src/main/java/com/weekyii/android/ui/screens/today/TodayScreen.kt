package com.weekyii.android.ui.screens.today

import android.app.TimePickerDialog
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.ExecutionMode
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.model.TaskAttachmentUi
import com.weekyii.android.ui.viewmodel.TodayViewModel
import java.time.format.DateTimeFormatter
import java.time.LocalDate

@Composable
fun TodayScreen(viewModel: TodayViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    var newTaskTitle by remember { mutableStateOf("") }
    var executionTaskTitle by remember { mutableStateOf("") }
    var editingTask by remember { mutableStateOf<TaskUi?>(null) }
    var editingTitle by remember { mutableStateOf("") }
    var editingDescription by remember { mutableStateOf("") }
    var editingStepsText by remember { mutableStateOf("") }
    val editingAttachments = remember { mutableStateListOf<TaskAttachmentUi>() }
    val context = LocalContext.current
    val attachmentPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            val name = uri.lastPathSegment?.substringAfterLast('/') ?: "attachment"
            editingAttachments.add(
                TaskAttachmentUi(
                    fileName = name,
                    fileType = context.contentResolver.getType(uri) ?: "application/octet-stream",
                    data = bytes
                )
            )
        }
    }
    val day = state.day

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Weekyii", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text(
                    state.date.format(DateTimeFormatter.ofPattern("yyyy年M月d日 EEEE")),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    StatusPill(day?.status ?: DayStatus.EMPTY)
                    KillTimeButton(
                        hour = day?.killHour ?: 20,
                        minute = day?.killMinute ?: 0,
                        enabled = day?.status !in listOf(DayStatus.COMPLETED, DayStatus.EXPIRED),
                        onChange = viewModel::changeKillTime
                    )
                }
            }
        }

        when (day?.status ?: DayStatus.EMPTY) {
            DayStatus.EMPTY, DayStatus.DRAFT -> {
                item {
                    SectionHeader("今日草稿", "启动前可以自由调整顺序；启动后任务流即成为承诺。")
                }
                if (day?.status == DayStatus.DRAFT) {
                    item {
                        ExecutionModePicker(
                            selected = state.startExecutionMode,
                            onSelect = viewModel::selectExecutionMode
                        )
                    }
                }
                itemsIndexed(state.draft, key = { _, task -> task.id }) { index, task ->
                    DraftTaskCard(
                        task = task,
                        canMoveUp = index > 0,
                        canMoveDown = index < state.draft.lastIndex,
                        onMoveUp = { viewModel.moveDraftTask(index, index - 1) },
                        onMoveDown = { viewModel.moveDraftTask(index, index + 1) },
                        onDelete = { viewModel.deleteDraftTask(task) },
                        onEdit = {
                            editingTask = task
                            editingTitle = task.title
                            editingDescription = task.description
                            editingStepsText = task.steps.sortedBy { it.sortOrder }.joinToString("\n") { it.title }
                            editingAttachments.clear()
                            editingAttachments.addAll(task.attachments)
                        },
                        onPostpone = { date -> viewModel.postponeTask(task, date) }
                    )
                }
                item {
                    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            OutlinedTextField(
                                value = newTaskTitle,
                                onValueChange = { newTaskTitle = it },
                                modifier = Modifier.fillMaxWidth(),
                                label = { Text("添加任务") },
                                supportingText = { Text("任务将按照当前顺序进入专注区") },
                                singleLine = true
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                FilledTonalButton(
                                    onClick = {
                                        val title = newTaskTitle.trim()
                                        if (title.isNotEmpty()) {
                                            viewModel.createDraft(listOf(title))
                                            newTaskTitle = ""
                                        }
                                    },
                                    enabled = newTaskTitle.isNotBlank(),
                                    modifier = Modifier.weight(1f)
                                ) { Text("加入草稿") }
                                Button(
                                    onClick = viewModel::startDay,
                                    enabled = state.draft.isNotEmpty(),
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Icon(Icons.Filled.PlayArrow, contentDescription = null)
                                    Text("开始今天")
                                }
                            }
                        }
                    }
                }
            }

            DayStatus.EXECUTE -> {
                item { SectionHeader("专注区", "现在只做这一件事。完成后下一项才会解冻。") }
                item {
                    FocusTaskCard(task = state.focus, onComplete = viewModel::doneFocus, onPostpone = { task, date -> viewModel.postponeTask(task, date) })
                }
                if (day?.executionModeRaw == ExecutionMode.FLEXIBLE.name.lowercase()) {
                    item {
                        FlexibleExecutionControls(
                            unlocked = day.isDraftZoneUnlocked,
                            title = executionTaskTitle,
                            onTitleChange = { executionTaskTitle = it },
                            onToggleUnlock = { viewModel.setDraftZoneUnlocked(!day.isDraftZoneUnlocked) },
                            onAdd = {
                                viewModel.addExecutionTask(executionTaskTitle.trim())
                                executionTaskTitle = ""
                            },
                            onExchange = viewModel::exchangeFocusWithFirstFrozen
                        )
                    }
                }
                if (state.frozen.isNotEmpty()) {
                    item { SectionHeader("冻结区", "后续 ${state.frozen.size} 项已锁定") }
                    itemsIndexed(state.frozen, key = { _, task -> task.id }) { index, task ->
                        CompactTaskRow(number = index + 2, task = task, onPostpone = { date -> viewModel.postponeTask(task, date) })
                    }
                }
                if (state.complete.isNotEmpty()) {
                    item { SectionHeader("已完成", "今天已经推进 ${state.complete.size} 项") }
                    itemsIndexed(state.complete, key = { _, task -> task.id }) { index, task ->
                        CompletedTaskRow(index + 1, task)
                    }
                }
            }

            DayStatus.COMPLETED -> {
                item {
                    CompletionCard(
                        title = "今天已经完成",
                        body = "${state.complete.size} 项任务全部进入完成区。"
                    )
                }
                itemsIndexed(state.complete, key = { _, task -> task.id }) { index, task ->
                    CompletedTaskRow(index + 1, task)
                }
            }

            DayStatus.EXPIRED -> {
                item {
                    CompletionCard(
                        title = "今天已经收口",
                        body = "完成 ${state.complete.size} 项，过期 ${day?.expiredCount ?: 0} 项。过期详情已被遗忘。"
                    )
                }
                itemsIndexed(state.complete, key = { _, task -> task.id }) { index, task ->
                    CompletedTaskRow(index + 1, task)
                }
            }
        }

        state.error?.let { message ->
            item {
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.medium
                ) {
                    Text(
                        message,
                        modifier = Modifier.padding(14.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }
        }

        item { Spacer(Modifier.height(24.dp)) }
    }

    editingTask?.let { task ->
        AlertDialog(
            onDismissRequest = { editingTask = null },
            title = { Text("编辑任务") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(
                        value = editingTitle,
                        onValueChange = { editingTitle = it },
                        label = { Text("任务名称") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = editingDescription,
                        onValueChange = { editingDescription = it },
                        label = { Text("任务说明") },
                        minLines = 3,
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = editingStepsText,
                        onValueChange = { editingStepsText = it },
                        label = { Text("子任务（每行一项）") },
                        minLines = 3,
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedButton(onClick = { attachmentPicker.launch(arrayOf("*/*")) }) {
                        Text("添加附件 (${editingAttachments.size})")
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = editingTitle.isNotBlank(),
                    onClick = {
                        viewModel.updateDraftTask(
                            task,
                            editingTitle,
                            editingDescription,
                            editingStepsText.lines(),
                            editingAttachments.toList()
                        )
                        editingTask = null
                    }
                ) { Text("保存") }
            },
            dismissButton = { TextButton(onClick = { editingTask = null }) { Text("取消") } }
        )
    }
}

@Composable
private fun StatusPill(status: DayStatus) {
    val label = when (status) {
        DayStatus.EMPTY -> "尚未规划"
        DayStatus.DRAFT -> "草稿"
        DayStatus.EXECUTE -> "执行中"
        DayStatus.COMPLETED -> "已完成"
        DayStatus.EXPIRED -> "已过期"
    }
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = MaterialTheme.shapes.extraLarge) {
        Text(label, modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp), fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun KillTimeButton(hour: Int, minute: Int, enabled: Boolean, onChange: (Int, Int) -> Unit) {
    val context = LocalContext.current
    OutlinedButton(
        enabled = enabled,
        onClick = {
            TimePickerDialog(context, { _, selectedHour, selectedMinute ->
                onChange(selectedHour, selectedMinute)
            }, hour, minute, true).show()
        }
    ) {
        Icon(Icons.Filled.Schedule, contentDescription = null)
        Text(String.format("  %02d:%02d", hour, minute))
    }
}

@Composable
private fun SectionHeader(title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ExecutionModePicker(selected: ExecutionMode, onSelect: (ExecutionMode) -> Unit) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("执行模式", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(
                if (selected == ExecutionMode.STRICT) "严格模式：启动后不能追加或交换任务。"
                else "灵活模式：执行中可解锁队列并调整后续任务。",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterButton("严格", selected == ExecutionMode.STRICT) { onSelect(ExecutionMode.STRICT) }
                FilterButton("灵活", selected == ExecutionMode.FLEXIBLE) { onSelect(ExecutionMode.FLEXIBLE) }
            }
        }
    }
}

@Composable
private fun FilterButton(label: String, selected: Boolean, onClick: () -> Unit) {
    if (selected) FilledTonalButton(onClick = onClick) { Text(label) }
    else OutlinedButton(onClick = onClick) { Text(label) }
}

@Composable
private fun FlexibleExecutionControls(
    unlocked: Boolean,
    title: String,
    onTitleChange: (String) -> Unit,
    onToggleUnlock: () -> Unit,
    onAdd: () -> Unit,
    onExchange: () -> Unit
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("灵活执行", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(
                        if (unlocked) "队列已解锁，可以调整后续任务。" else "队列已锁定，保持当前专注顺序。",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                OutlinedButton(onClick = onToggleUnlock) { Text(if (unlocked) "锁定" else "解锁") }
            }
            if (unlocked) {
                OutlinedTextField(
                    value = title,
                    onValueChange = onTitleChange,
                    label = { Text("追加到冻结区") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilledTonalButton(onClick = onAdd, enabled = title.isNotBlank()) { Text("追加任务") }
                    OutlinedButton(onClick = onExchange) { Text("交换 Focus") }
                }
            }
        }
    }
}

@Composable
private fun DraftTaskCard(
    task: TaskUi,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDelete: () -> Unit,
    onEdit: () -> Unit,
    onPostpone: (LocalDate) -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("T${task.order.toString().padStart(2, '0')}", fontWeight = FontWeight.Bold)
            Text(task.title, modifier = Modifier.weight(1f).padding(horizontal = 12.dp))
            IconButton(onClick = onEdit) { Icon(Icons.Filled.Edit, "编辑") }
            IconButton(onClick = onMoveUp, enabled = canMoveUp) { Icon(Icons.Filled.ArrowUpward, "上移") }
            IconButton(onClick = onMoveDown, enabled = canMoveDown) { Icon(Icons.Filled.ArrowDownward, "下移") }
            IconButton(onClick = onDelete) { Icon(Icons.Filled.Delete, "删除") }
            PostponeButton(onPostpone)
        }
    }
}

@Composable
private fun FocusTaskCard(task: TaskUi?, onComplete: () -> Unit, onPostpone: (TaskUi, LocalDate) -> Unit) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
    ) {
        Column(modifier = Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("FOCUS", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Text(task?.title ?: "正在加载专注任务", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            if (!task?.description.isNullOrBlank()) Text(task!!.description)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                Button(onClick = onComplete, enabled = task != null, modifier = Modifier.weight(1f)) {
                    Icon(Icons.Filled.Check, contentDescription = null)
                    Text("完成")
                }
                if (task != null) PostponeButton { date -> onPostpone(task, date) }
            }
        }
    }
}

@Composable
private fun CompactTaskRow(number: Int, task: TaskUi, onPostpone: (LocalDate) -> Unit) {
    Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("T${number.toString().padStart(2, '0')}", fontWeight = FontWeight.Bold)
            Text(task.title, modifier = Modifier.padding(start = 14.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            PostponeButton(onPostpone)
        }
    }
}

@Composable
private fun PostponeButton(onPostpone: (LocalDate) -> Unit) {
    val context = LocalContext.current
    OutlinedButton(onClick = {
        val tomorrow = LocalDate.now().plusDays(1)
        TimePickerDateDialog(context, tomorrow) { onPostpone(it) }
    }) { Text("后移") }
}

private fun TimePickerDateDialog(
    context: android.content.Context,
    initial: LocalDate,
    onDateSelected: (LocalDate) -> Unit
) {
    android.app.DatePickerDialog(
        context,
        { _, year, month, day -> onDateSelected(LocalDate.of(year, month + 1, day)) },
        initial.year,
        initial.monthValue - 1,
        initial.dayOfMonth
    ).show()
}

@Composable
private fun CompletedTaskRow(number: Int, task: TaskUi) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp)) {
        Row(modifier = Modifier.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
            Text("T${number.toString().padStart(2, '0')}  ${task.title}", modifier = Modifier.padding(start = 10.dp))
        }
        HorizontalDivider()
    }
}

@Composable
private fun CompletionCard(title: String, body: String) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(body, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
