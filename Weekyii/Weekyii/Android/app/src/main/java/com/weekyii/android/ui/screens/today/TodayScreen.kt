package com.weekyii.android.ui.screens.today

import android.app.TimePickerDialog
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Celebration
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material3.Button
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
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
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.Color
import android.graphics.BitmapFactory
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.ExecutionMode
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.ui.model.TaskUi
import com.weekyii.android.ui.model.TaskAttachmentUi
import com.weekyii.android.ui.viewmodel.TodayViewModel
import com.weekyii.android.ui.viewmodel.WeekViewModel
import com.weekyii.android.ui.screens.week.WeekScreen
import com.weekyii.android.ui.components.WeekyiiCard
import com.weekyii.android.ui.components.WeekyiiButton
import com.weekyii.android.ui.components.WeekyiiButtonStyle
import com.weekyii.android.ui.components.WeekyiiEmptyState
import com.weekyii.android.ui.components.WeekyiiHeader
import com.weekyii.android.ui.components.WeekyiiSegmentedControl
import com.weekyii.android.ui.components.WeekyiiStatusArtwork
import com.weekyii.android.ui.components.WeekyiiTaskRow
import com.weekyii.android.ui.theme.WeekyiiDimensions
import java.time.format.DateTimeFormatter
import java.time.LocalDate

@Composable
fun TodayScreen(viewModel: TodayViewModel, padding: PaddingValues, weekViewModel: WeekViewModel? = null) {
    val state by viewModel.state.collectAsState()
    val daysStartedCount by viewModel.daysStartedCount.collectAsState()
    var showWeek by remember { mutableStateOf(false) }
    var showEmptyComposer by remember { mutableStateOf(false) }
    var newTaskTitle by remember { mutableStateOf("") }
    var executionTaskTitle by remember { mutableStateOf("") }
    var editingTask by remember { mutableStateOf<TaskUi?>(null) }
    var editingTitle by remember { mutableStateOf("") }
    var editingDescription by remember { mutableStateOf("") }
    var editingStepsText by remember { mutableStateOf("") }
    var editingTaskTypeId by remember { mutableStateOf("regular") }
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

    if (showWeek && weekViewModel != null) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
                .padding(padding)
                .padding(horizontal = WeekyiiDimensions.contentHorizontalPadding)
        ) {
            WeekyiiHeader()
            TodayWeekSwitcher(showWeek = true, onChange = { showWeek = it })
            WeekScreen(weekViewModel, modifier = Modifier.weight(1f))
        }
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(padding),
        contentPadding = PaddingValues(
            horizontal = WeekyiiDimensions.contentHorizontalPadding,
            vertical = WeekyiiDimensions.spacingBase
        ),
        verticalArrangement = Arrangement.spacedBy(WeekyiiDimensions.spacingLarge)
    ) {
        item {
            WeekyiiHeader()
        }
        item {
            TodayWeekSwitcher(showWeek = false, onChange = { showWeek = it })
        }
        state.ritualStamp?.let { stamp ->
            item { RitualStampCard(stamp.text, stamp.imageBlob, viewModel::dismissRitual) }
        }
        item {
            val status = day?.status ?: DayStatus.EMPTY
            WeekyiiCard(accentColor = statusAccentColor(status)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.Top
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(WeekyiiDimensions.spacingSmall)) {
                        Text("状态", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        StatusPill(status)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text("已启动天数", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(
                            daysStartedCount.toString(),
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }
                Spacer(Modifier.height(WeekyiiDimensions.spacingBase))
                WeekyiiStatusArtwork(status)
                Spacer(Modifier.height(WeekyiiDimensions.spacingBase))
                Text(
                    state.date.format(DateTimeFormatter.ofPattern("yyyy年M月d日")),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        when (day?.status ?: DayStatus.EMPTY) {
            DayStatus.EMPTY -> {
                item {
                    WeekyiiEmptyState(
                        title = "今日无任务",
                        subtitle = "创建今日任务流以开始。",
                        icon = Icons.Filled.Edit
                    )
                }
                item {
                    WeekyiiButton(
                        text = "创建",
                        icon = Icons.Filled.Add,
                        onClick = { showEmptyComposer = true },
                    )
                }
                if (showEmptyComposer) {
                    item {
                        AddTaskCard(
                            title = newTaskTitle,
                            onTitleChange = { newTaskTitle = it },
                            onAdd = {
                                val title = newTaskTitle.trim()
                                if (title.isNotEmpty()) {
                                    viewModel.createDraft(listOf(title))
                                    newTaskTitle = ""
                                    showEmptyComposer = false
                                }
                            },
                            onStart = viewModel::startDay,
                            canStart = false
                        )
                    }
                }
            }

            DayStatus.DRAFT -> {
                item {
                    SectionHeader("今日草稿", "启动前可以自由调整顺序；启动后任务流即成为承诺。")
                }
                item {
                    ExecutionModePicker(
                        selected = state.startExecutionMode,
                        onSelect = viewModel::selectExecutionMode
                    )
                }
                item {
                    TaskTypePicker(
                        definitions = state.taskTypeDefinitions,
                        selectedId = state.selectedTaskTypeId,
                        onSelect = viewModel::selectTaskType
                    )
                }
                itemsIndexed(state.draft, key = { _, task -> task.id }) { index, task ->
                    DraftTaskCard(
                        task = task,
                        typeLabel = taskTypeLabel(task, state.taskTypeDefinitions),
                        canMoveUp = index > 0,
                        canMoveDown = index < state.draft.lastIndex,
                        onMoveUp = { viewModel.moveDraftTask(index, index - 1) },
                        onMoveDown = { viewModel.moveDraftTask(index, index + 1) },
                        onDelete = { viewModel.deleteDraftTask(task) },
                        onEdit = {
                            editingTask = task
                            editingTitle = task.title
                            editingDescription = task.description
                            editingTaskTypeId = task.taskTypeIdRaw
                            editingStepsText = task.steps.sortedBy { it.sortOrder }.joinToString("\n") { it.title }
                            editingAttachments.clear()
                            editingAttachments.addAll(task.attachments)
                        },
                        onPostpone = { date -> viewModel.postponeTask(task, date) }
                    )
                }
                item {
                    AddTaskCard(
                        title = newTaskTitle,
                        onTitleChange = { newTaskTitle = it },
                        onAdd = {
                            val title = newTaskTitle.trim()
                            if (title.isNotEmpty()) {
                                viewModel.createDraft(listOf(title))
                                newTaskTitle = ""
                            }
                        },
                        onStart = viewModel::startDay,
                        canStart = state.draft.isNotEmpty()
                    )
                }
            }

            DayStatus.EXECUTE -> {
                item { SectionHeader("专注区", "现在只做这一件事。完成后下一项才会解冻。") }
                item {
                    FocusTaskCard(
                        task = state.focus,
                        typeLabel = state.focus?.let { taskTypeLabel(it, state.taskTypeDefinitions) },
                        onComplete = viewModel::doneFocus,
                        onPostpone = { task, date -> viewModel.postponeTask(task, date) }
                    )
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
                            onExchange = viewModel::exchangeFocusWithFirstFrozen,
                            taskTypes = state.taskTypeDefinitions,
                            selectedTaskTypeId = state.selectedTaskTypeId,
                            onTaskTypeSelect = viewModel::selectTaskType
                        )
                    }
                }
                if (state.frozen.isNotEmpty()) {
                    val frozenEditable = day?.executionModeRaw == ExecutionMode.FLEXIBLE.name.lowercase() &&
                        day.isDraftZoneUnlocked
                    item {
                        SectionHeader(
                            "冻结区",
                            if (frozenEditable) "后续 ${state.frozen.size} 项可调整，Focus 仍保持锁定"
                            else "后续 ${state.frozen.size} 项已锁定"
                        )
                    }
                    itemsIndexed(state.frozen, key = { _, task -> task.id }) { index, task ->
                        CompactTaskRow(
                            number = index + 2,
                            task = task,
                            typeLabel = taskTypeLabel(task, state.taskTypeDefinitions),
                            editable = frozenEditable,
                            canMoveUp = index > 0,
                            canMoveDown = index < state.frozen.lastIndex,
                            onMoveUp = { viewModel.moveFrozenTask(index, index - 1) },
                            onMoveDown = { viewModel.moveFrozenTask(index, index + 1) },
                            onDelete = { viewModel.deleteFrozenTask(task) },
                            onEdit = {
                                editingTask = task
                                editingTitle = task.title
                                editingDescription = task.description
                                editingTaskTypeId = task.taskTypeIdRaw
                                editingStepsText = task.steps.sortedBy { it.sortOrder }.joinToString("\n") { it.title }
                                editingAttachments.clear()
                                editingAttachments.addAll(task.attachments)
                            },
                            onPostpone = { date -> viewModel.postponeTask(task, date) }
                        )
                    }
                }
                if (state.complete.isNotEmpty()) {
                    item {
                        CompletedTasksCard(state.complete, state.taskTypeDefinitions)
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
                if (state.complete.isNotEmpty()) {
                    item { CompletedTasksCard(state.complete, state.taskTypeDefinitions) }
                }
            }

            DayStatus.EXPIRED -> {
                item {
                    ExpiredCard(day?.expiredCount ?: 0)
                }
                if (state.complete.isNotEmpty()) {
                    item { CompletedTasksCard(state.complete, state.taskTypeDefinitions) }
                }
            }
        }

        item {
            WeekyiiCard(accentColor = MaterialTheme.colorScheme.tertiary) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Schedule, contentDescription = null, tint = MaterialTheme.colorScheme.tertiary)
                        Text(
                            "截止时间",
                            modifier = Modifier.padding(start = WeekyiiDimensions.spacingSmall),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                    KillTimeButton(
                        hour = day?.killHour ?: 20,
                        minute = day?.killMinute ?: 0,
                        enabled = day?.status !in listOf(DayStatus.COMPLETED, DayStatus.EXPIRED),
                        onChange = viewModel::changeKillTime
                    )
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
                    TaskTypePicker(
                        definitions = state.taskTypeDefinitions,
                        selectedId = editingTaskTypeId,
                        onSelect = { editingTaskTypeId = it }
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
                        if (task.zone.name == "FROZEN") {
                            val definition = state.taskTypeDefinitions.firstOrNull { it.idRaw == editingTaskTypeId }
                            viewModel.updateFrozenTask(
                                task,
                                editingTitle,
                                editingDescription,
                                editingStepsText.lines(),
                                editingAttachments.toList(),
                                taskType = definition?.baseKind ?: task.taskType,
                                taskTypeIdRaw = definition?.idRaw ?: task.taskTypeIdRaw
                            )
                        } else {
                            val definition = state.taskTypeDefinitions.firstOrNull { it.idRaw == editingTaskTypeId }
                            viewModel.updateDraftTask(
                                task,
                                editingTitle,
                                editingDescription,
                                editingStepsText.lines(),
                                editingAttachments.toList(),
                                taskType = definition?.baseKind ?: task.taskType,
                                taskTypeIdRaw = definition?.idRaw ?: task.taskTypeIdRaw
                            )
                        }
                        editingTask = null
                    }
                ) { Text("保存") }
            },
            dismissButton = { TextButton(onClick = { editingTask = null }) { Text("取消") } }
        )
    }
}

@Composable
private fun RitualStampCard(text: String, imageBlob: ByteArray?, onDismiss: () -> Unit) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.tertiary) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("今日 MindStamp", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("把这一刻带进今天。", color = MaterialTheme.colorScheme.onTertiaryContainer)
            if (text.isNotBlank()) Text(text, style = MaterialTheme.typography.bodyLarge)
            imageBlob?.let { bytes ->
                val bitmap = remember(bytes.contentHashCode()) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }
                bitmap?.let { Image(it.asImageBitmap(), contentDescription = "MindStamp 图片", modifier = Modifier.height(140.dp), contentScale = ContentScale.Fit) }
            }
            TextButton(onClick = onDismiss) { Text("收下并开始") }
        }
    }
}

@Composable
private fun TodayWeekSwitcher(showWeek: Boolean, onChange: (Boolean) -> Unit) {
    WeekyiiSegmentedControl(
        items = listOf("当下", "本周"),
        selectedIndex = if (showWeek) 1 else 0,
        onSelectedIndexChange = { onChange(it == 1) },
        icons = listOf(Icons.Filled.WbSunny, Icons.Filled.CalendarMonth)
    )
}

@Composable
private fun StatusPill(status: DayStatus) {
    val label = when (status) {
        DayStatus.EMPTY -> "空"
        DayStatus.DRAFT -> "草稿"
        DayStatus.EXECUTE -> "执行中"
        DayStatus.COMPLETED -> "已完成"
        DayStatus.EXPIRED -> "已过期"
    }
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f),
        shape = MaterialTheme.shapes.extraLarge
    ) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
private fun statusAccentColor(status: DayStatus): Color = when (status) {
    DayStatus.EMPTY -> MaterialTheme.colorScheme.outline
    DayStatus.DRAFT -> MaterialTheme.colorScheme.primary
    DayStatus.EXECUTE -> MaterialTheme.colorScheme.tertiary
    DayStatus.COMPLETED -> MaterialTheme.colorScheme.secondary
    DayStatus.EXPIRED -> MaterialTheme.colorScheme.error
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
    WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
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
    onExchange: () -> Unit,
    taskTypes: List<TaskTypeDefinitionEntity>,
    selectedTaskTypeId: String,
    onTaskTypeSelect: (String) -> Unit
) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
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
                TaskTypePicker(
                    definitions = taskTypes,
                    selectedId = selectedTaskTypeId,
                    onSelect = onTaskTypeSelect
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
private fun TaskTypePicker(
    definitions: List<TaskTypeDefinitionEntity>,
    selectedId: String,
    onSelect: (String) -> Unit
) {
    if (definitions.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("任务类型", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            items(definitions, key = { it.idRaw }) { definition ->
                FilterChip(
                    selected = definition.idRaw == selectedId,
                    onClick = { onSelect(definition.idRaw) },
                    label = { Text(definition.name) }
                )
            }
        }
    }
}

@Composable
private fun DraftTaskCard(
    task: TaskUi,
    typeLabel: String,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDelete: () -> Unit,
    onEdit: () -> Unit,
    onPostpone: (LocalDate) -> Unit
) {
    var menuExpanded by remember { mutableStateOf(false) }
    val context = LocalContext.current
    WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
        WeekyiiTaskRow(
            title = task.title,
            subtitle = "T${task.order.toString().padStart(2, '0')} · $typeLabel",
            trailing = {
                Box {
                    IconButton(onClick = { menuExpanded = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "更多操作")
                    }
                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        DropdownMenuItem(
                            text = { Text("编辑") },
                            leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                            onClick = { menuExpanded = false; onEdit() }
                        )
                        DropdownMenuItem(
                            text = { Text("上移") },
                            leadingIcon = { Icon(Icons.Filled.ArrowUpward, contentDescription = null) },
                            enabled = canMoveUp,
                            onClick = { menuExpanded = false; onMoveUp() }
                        )
                        DropdownMenuItem(
                            text = { Text("下移") },
                            leadingIcon = { Icon(Icons.Filled.ArrowDownward, contentDescription = null) },
                            enabled = canMoveDown,
                            onClick = { menuExpanded = false; onMoveDown() }
                        )
                        DropdownMenuItem(
                            text = { Text("后移到其他日期") },
                            leadingIcon = { Icon(Icons.Filled.Schedule, contentDescription = null) },
                            onClick = {
                                menuExpanded = false
                                TimePickerDateDialog(context, LocalDate.now().plusDays(1), onPostpone)
                            }
                        )
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("删除", color = MaterialTheme.colorScheme.error) },
                            leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                            onClick = { menuExpanded = false; onDelete() }
                        )
                    }
                }
            }
        )
    }
}

@Composable
private fun FocusTaskCard(
    task: TaskUi?,
    typeLabel: String?,
    onComplete: () -> Unit,
    onPostpone: (TaskUi, LocalDate) -> Unit
) {
    val context = LocalContext.current
    WeekyiiCard(modifier = Modifier.fillMaxWidth(), gradient = true) {
        Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Color.White)
                Text("专注区", modifier = Modifier.padding(start = 8.dp), style = MaterialTheme.typography.titleMedium, color = Color.White, fontWeight = FontWeight.SemiBold)
            }
            Text(task?.title ?: "正在加载专注任务", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = Color.White)
            typeLabel?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = Color.White.copy(alpha = 0.85f)) }
            if (!task?.description.isNullOrBlank()) Text(task!!.description, color = Color.White.copy(alpha = 0.9f))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                WeekyiiButton(
                    text = "完成当前任务",
                    icon = Icons.Filled.Check,
                    style = WeekyiiButtonStyle.OnGradient,
                    enabled = task != null,
                    onClick = onComplete,
                    modifier = Modifier.weight(1f)
                )
                if (task != null) {
                    WeekyiiButton(
                        text = "后移",
                        style = WeekyiiButtonStyle.OnGradient,
                        onClick = { val tomorrow = LocalDate.now().plusDays(1); TimePickerDateDialog(context, tomorrow) { onPostpone(task, it) } }
                    )
                }
            }
        }
    }
}

@Composable
private fun CompactTaskRow(
    number: Int,
    task: TaskUi,
    typeLabel: String,
    editable: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDelete: () -> Unit,
    onEdit: () -> Unit,
    onPostpone: (LocalDate) -> Unit
) {
    var menuExpanded by remember { mutableStateOf(false) }
    val context = LocalContext.current
    WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
        WeekyiiTaskRow(
            title = task.title,
            subtitle = "T${number.toString().padStart(2, '0')} · $typeLabel",
            leading = { Icon(Icons.Filled.AcUnit, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
            trailing = {
                Box {
                    IconButton(onClick = { menuExpanded = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "更多操作")
                    }
                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        if (editable) {
                            DropdownMenuItem(
                                text = { Text("编辑") },
                                leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                                onClick = { menuExpanded = false; onEdit() }
                            )
                            DropdownMenuItem(
                                text = { Text("上移") },
                                leadingIcon = { Icon(Icons.Filled.ArrowUpward, contentDescription = null) },
                                enabled = canMoveUp,
                                onClick = { menuExpanded = false; onMoveUp() }
                            )
                            DropdownMenuItem(
                                text = { Text("下移") },
                                leadingIcon = { Icon(Icons.Filled.ArrowDownward, contentDescription = null) },
                                enabled = canMoveDown,
                                onClick = { menuExpanded = false; onMoveDown() }
                            )
                        }
                        DropdownMenuItem(
                            text = { Text("后移到其他日期") },
                            leadingIcon = { Icon(Icons.Filled.Schedule, contentDescription = null) },
                            onClick = {
                                menuExpanded = false
                                TimePickerDateDialog(context, LocalDate.now().plusDays(1), onPostpone)
                            }
                        )
                        if (editable) {
                            HorizontalDivider()
                            DropdownMenuItem(
                                text = { Text("删除", color = MaterialTheme.colorScheme.error) },
                                leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                                onClick = { menuExpanded = false; onDelete() }
                            )
                        }
                    }
                }
            }
        )
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
private fun CompletedTaskRow(number: Int, task: TaskUi, typeLabel: String) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp)) {
        Row(modifier = Modifier.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
            Column(modifier = Modifier.padding(start = 10.dp)) {
                Text("T${number.toString().padStart(2, '0')}  ${task.title}")
                Text(typeLabel, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        HorizontalDivider()
    }
}

@Composable
private fun CompletedTasksCard(tasks: List<TaskUi>, definitions: List<TaskTypeDefinitionEntity>) {
    WeekyiiCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
                Text("已完成", modifier = Modifier.padding(start = 8.dp), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }
            Text(tasks.size.toString(), color = MaterialTheme.colorScheme.secondary, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(8.dp))
        tasks.forEachIndexed { index, task ->
            CompletedTaskRow(index + 1, task, taskTypeLabel(task, definitions))
        }
    }
}

private fun taskTypeLabel(task: TaskUi, definitions: List<TaskTypeDefinitionEntity>): String =
    definitions.firstOrNull { it.idRaw == task.taskTypeIdRaw }?.name
        ?: when (task.taskType) {
            TaskType.REGULAR -> "常规"
            TaskType.DDL -> "DDL"
            TaskType.LEISURE -> "休闲"
        }

@Composable
private fun CompletionCard(title: String, body: String) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth(), gradient = true) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Icon(Icons.Filled.Celebration, contentDescription = null, tint = Color.White, modifier = Modifier.height(44.dp))
            Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = Color.White)
            Text(body, color = Color.White.copy(alpha = 0.9f))
        }
    }
}

@Composable
private fun ExpiredCard(expiredCount: Int) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.error) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            Text("今天已经收口", modifier = Modifier.padding(start = 8.dp), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(10.dp))
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("未完成任务已被遗忘", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(expiredCount.toString(), color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun AddTaskCard(
    title: String,
    onTitleChange: (String) -> Unit,
    onAdd: () -> Unit,
    onStart: () -> Unit,
    canStart: Boolean
) {
    WeekyiiCard {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(
                value = title,
                onValueChange = onTitleChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("添加任务") },
                supportingText = { Text("任务会按当前顺序进入专注区") },
                singleLine = true
            )
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                WeekyiiButton(
                    text = "加入草稿",
                    onClick = onAdd,
                    enabled = title.isNotBlank(),
                    style = WeekyiiButtonStyle.Secondary,
                    modifier = Modifier.weight(1f)
                )
                WeekyiiButton(
                    text = "开始今天",
                    icon = Icons.Filled.PlayArrow,
                    onClick = onStart,
                    enabled = canStart,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}
