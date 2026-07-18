package com.weekyii.android.ui.screens.extensions

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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.TaskAlt
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.ui.model.ProjectDetailUi
import com.weekyii.android.ui.model.TaskUi
import java.time.LocalDate
import com.weekyii.android.ui.components.WeekyiiCard
import com.weekyii.android.ui.components.WeekyiiButton
import com.weekyii.android.ui.components.WeekyiiButtonStyle
import com.weekyii.android.ui.components.WeekyiiEmptyState
import com.weekyii.android.ui.components.WeekyiiErrorState
import com.weekyii.android.ui.components.StatusBadge
import com.weekyii.android.ui.components.WeekyiiTaskRow

@Composable
fun ProjectDetailScreen(
    detail: ProjectDetailUi,
    padding: PaddingValues,
    error: String?,
    taskTypeDefinitions: List<TaskTypeDefinitionEntity>,
    onBack: () -> Unit,
    onStatusChange: (ProjectStatus) -> Unit,
    onUpdateProject: (String, String, LocalDate, LocalDate, String, String, String) -> Unit,
    onAddTasks: (title: String, description: String, taskType: TaskType, taskTypeIdRaw: String, dates: List<LocalDate>) -> Unit,
    onUpdateTask: (task: TaskUi, title: String, description: String) -> Unit,
    onDeleteTask: (TaskUi) -> Unit,
    onDeleteProject: (includeTasks: Boolean) -> Unit
) {
    val project = detail.project
    val writable = project.status == ProjectStatus.PLANNING || project.status == ProjectStatus.ACTIVE
    var addDialog by remember { mutableStateOf(false) }
    var editingTask by remember { mutableStateOf<TaskUi?>(null) }
    var deletingTask by remember { mutableStateOf<TaskUi?>(null) }
    var deletingProject by remember { mutableStateOf(false) }
    var editingProject by remember { mutableStateOf(false) }
    var projectMenuExpanded by remember { mutableStateOf(false) }
    val statusLabel = when (project.status) {
        ProjectStatus.PLANNING -> "规划中"
        ProjectStatus.ACTIVE -> "进行中"
        ProjectStatus.COMPLETED -> "已完成"
        ProjectStatus.ARCHIVED -> "已归档"
    }
    val primaryActionLabel = when (project.status) {
        ProjectStatus.PLANNING -> "激活项目"
        ProjectStatus.ACTIVE -> if (detail.totalCount > 0 && detail.remainingCount == 0) "确认结项" else null
        ProjectStatus.COMPLETED -> "重新打开"
        ProjectStatus.ARCHIVED -> "恢复项目"
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回项目列表")
                    }
                    Text("项目详情", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                }
                StatusBadge(
                    text = statusLabel,
                    color = MaterialTheme.colorScheme.primaryContainer,
                    contentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
        }
        error?.let { message ->
            item { WeekyiiErrorState(message) }
        }
        item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.primary) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(project.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    Text(project.description.ifBlank { "无项目说明" }, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("${project.startDate} ~ ${project.endDate}")
                    Text("进度 ${(detail.progress * 100).toInt()}% · 已完成 ${detail.completedCount} / ${detail.totalCount}")
                    Text("剩余 ${detail.remainingCount} · 过期 ${detail.expiredCount}")
                    detail.nextTaskTitle?.let { Text("下一步：$it", color = MaterialTheme.colorScheme.primary) }
                }
            }
        }
        item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.tertiary) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("项目操作", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                    ) {
                        primaryActionLabel?.let { label ->
                            WeekyiiButton(
                                text = label,
                                style = WeekyiiButtonStyle.Primary,
                                modifier = Modifier.weight(1f),
                                onClick = {
                                    when (project.status) {
                                        ProjectStatus.PLANNING -> onStatusChange(ProjectStatus.ACTIVE)
                                        ProjectStatus.ACTIVE -> onStatusChange(ProjectStatus.COMPLETED)
                                        ProjectStatus.COMPLETED -> onStatusChange(ProjectStatus.ACTIVE)
                                        ProjectStatus.ARCHIVED -> onStatusChange(ProjectStatus.COMPLETED)
                                    }
                                }
                            )
                        }
                        if (writable) {
                            WeekyiiButton(
                                text = "添加任务",
                                style = WeekyiiButtonStyle.Secondary,
                                modifier = Modifier.weight(1f),
                                onClick = { addDialog = true }
                            )
                        }
                        androidx.compose.foundation.layout.Box {
                            IconButton(onClick = { projectMenuExpanded = true }) {
                                Icon(Icons.Filled.MoreVert, contentDescription = "更多项目操作")
                            }
                            DropdownMenu(
                                expanded = projectMenuExpanded,
                                onDismissRequest = { projectMenuExpanded = false }
                            ) {
                                if (writable) {
                                    DropdownMenuItem(
                                        text = { Text("编辑项目资料") },
                                        onClick = { projectMenuExpanded = false; editingProject = true }
                                    )
                                }
                                if (project.status == ProjectStatus.COMPLETED) {
                                    DropdownMenuItem(
                                        text = { Text("归档项目") },
                                        onClick = { projectMenuExpanded = false; onStatusChange(ProjectStatus.ARCHIVED) }
                                    )
                                }
                                DropdownMenuItem(
                                    text = { Text("删除项目") },
                                    onClick = { projectMenuExpanded = false; deletingProject = true }
                                )
                            }
                        }
                    }
                }
            }
        }
        item { Text("按日期排列的任务", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
        if (detail.sections.isEmpty()) {
            item {
                WeekyiiEmptyState(
                    title = "项目暂无任务",
                    subtitle = if (writable) "添加项目任务，让工作台开始积累进度。" else "当前项目没有可展示的任务。",
                    icon = Icons.Outlined.TaskAlt
                )
            }
        } else {
            items(detail.sections, key = { it.date.toString() }) { section ->
            WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("${section.date} · ${section.tasks.size} 项", style = MaterialTheme.typography.titleMedium)
                        section.tasks.forEach { task ->
                            ProjectTaskRow(
                                task = task,
                                editable = writable && task.zone == TaskZone.DRAFT,
                                onEdit = { editingTask = task },
                                onDelete = { deletingTask = task }
                            )
                        }
                    }
                }
            }
        }
    }

    if (addDialog) {
        AddProjectTasksDialog(
            startDate = project.startDate,
            endDate = project.endDate,
            definitions = taskTypeDefinitions,
            onDismiss = { addDialog = false },
            onCreate = { title, description, taskType, taskTypeIdRaw, dates ->
                onAddTasks(title, description, taskType, taskTypeIdRaw, dates)
                addDialog = false
            }
        )
    }
    if (editingProject) {
        EditProjectMetadataDialog(
            project = project,
            onDismiss = { editingProject = false },
            onSave = { name, description, startDate, endDate, color, icon, tileSize ->
                onUpdateProject(name, description, startDate, endDate, color, icon, tileSize)
                editingProject = false
            }
        )
    }
    editingTask?.let { task ->
        EditProjectTaskDialog(
            task = task,
            onDismiss = { editingTask = null },
            onSave = { title, description ->
                onUpdateTask(task, title, description)
                editingTask = null
            }
        )
    }
    deletingTask?.let { task ->
        AlertDialog(
            onDismissRequest = { deletingTask = null },
            title = { Text("删除项目任务？") },
            text = { Text("仅允许删除尚未启动的草稿任务。") },
            confirmButton = { TextButton(onClick = { onDeleteTask(task); deletingTask = null }) { Text("删除") } },
            dismissButton = { TextButton(onClick = { deletingTask = null }) { Text("取消") } }
        )
    }
    if (deletingProject) {
        AlertDialog(
            onDismissRequest = { deletingProject = false },
            title = { Text("删除项目") },
            text = { Text("可以只删除项目并保留任务，也可以连同未启动的草稿任务一起删除。") },
            confirmButton = {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(onClick = { onDeleteProject(false); deletingProject = false }) { Text("仅删除项目") }
                    TextButton(onClick = { onDeleteProject(true); deletingProject = false }) { Text("项目和任务") }
                }
            },
            dismissButton = { TextButton(onClick = { deletingProject = false }) { Text("取消") } }
        )
    }
}

@Composable
private fun ProjectTaskRow(task: TaskUi, editable: Boolean, onEdit: () -> Unit, onDelete: () -> Unit) {
    var menuExpanded by remember(task.id) { mutableStateOf(false) }
    WeekyiiTaskRow(
        title = task.title,
        subtitle = task.zone.name.lowercase(),
        trailing = {
            if (editable) {
                androidx.compose.foundation.layout.Box {
                    IconButton(onClick = { menuExpanded = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "任务操作")
                    }
                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        DropdownMenuItem(text = { Text("编辑") }, onClick = { menuExpanded = false; onEdit() })
                        DropdownMenuItem(text = { Text("删除") }, onClick = { menuExpanded = false; onDelete() })
                    }
                }
            } else {
                StatusBadge(
                    text = when (task.zone) {
                        TaskZone.DRAFT -> "草稿"
                        TaskZone.COMPLETE -> "完成"
                        TaskZone.FOCUS -> "专注"
                        TaskZone.FROZEN -> "冻结"
                    },
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    )
}

@Composable
private fun AddProjectTasksDialog(
    startDate: LocalDate,
    endDate: LocalDate,
    definitions: List<TaskTypeDefinitionEntity>,
    onDismiss: () -> Unit,
    onCreate: (String, String, TaskType, String, List<LocalDate>) -> Unit
) {
    val context = LocalContext.current
    var title by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var dates by remember { mutableStateOf(emptySet<LocalDate>()) }
    var selectedTypeId by remember { mutableStateOf(definitions.firstOrNull()?.idRaw ?: "regular") }
    val selectedDefinition = definitions.firstOrNull { it.idRaw == selectedTypeId }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("添加项目任务") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(title, { title = it }, label = { Text("任务名称") }, singleLine = true)
                OutlinedTextField(description, { description = it }, label = { Text("说明") })
                if (definitions.isNotEmpty()) {
                    Text("任务类型", style = MaterialTheme.typography.labelLarge)
                    definitions.forEach { definition ->
                        FilterChip(
                            selected = definition.idRaw == selectedTypeId,
                            onClick = { selectedTypeId = definition.idRaw },
                            label = { Text(definition.name) }
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        val initial = dates.firstOrNull() ?: maxOf(startDate, LocalDate.now())
                        DatePickerDialog(context, { _, year, month, day ->
                            val picked = LocalDate.of(year, month + 1, day)
                            if (picked in startDate..endDate) dates = dates + picked
                        }, initial.year, initial.monthValue - 1, initial.dayOfMonth).show()
                    }) { Text("选择日期") }
                    Text(if (dates.isEmpty()) "未选日期" else dates.sorted().joinToString())
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = title.isNotBlank() && dates.isNotEmpty(),
                onClick = {
                    onCreate(
                        title,
                        description,
                        selectedDefinition?.baseKind ?: TaskType.REGULAR,
                        selectedDefinition?.idRaw ?: "regular",
                        dates.sorted()
                    )
                }
            ) { Text("添加") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } }
    )
}

@Composable
private fun EditProjectTaskDialog(task: TaskUi, onDismiss: () -> Unit, onSave: (String, String) -> Unit) {
    var title by remember(task.id) { mutableStateOf(task.title) }
    var description by remember(task.id) { mutableStateOf(task.description) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("编辑项目任务") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(title, { title = it }, label = { Text("任务名称") }, singleLine = true)
                OutlinedTextField(description, { description = it }, label = { Text("说明") })
            }
        },
        confirmButton = { TextButton(enabled = title.isNotBlank(), onClick = { onSave(title, description) }) { Text("保存") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } }
    )
}

@Composable
private fun EditProjectMetadataDialog(
    project: com.weekyii.android.ui.model.ProjectUi,
    onDismiss: () -> Unit,
    onSave: (String, String, LocalDate, LocalDate, String, String, String) -> Unit
) {
    val context = LocalContext.current
    var name by remember(project.id) { mutableStateOf(project.name) }
    var description by remember(project.id) { mutableStateOf(project.description) }
    var startDate by remember(project.id) { mutableStateOf(project.startDate) }
    var endDate by remember(project.id) { mutableStateOf(project.endDate) }
    var color by remember(project.id) { mutableStateOf(project.color) }
    var icon by remember(project.id) { mutableStateOf(project.icon) }
    var tileSize by remember(project.id) { mutableStateOf(project.tileSizeRaw) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("编辑项目资料") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text("名称") }, singleLine = true)
                OutlinedTextField(description, { description = it }, label = { Text("说明") })
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    OutlinedButton(onClick = { DatePickerDialog(context, { _, y, m, d -> startDate = LocalDate.of(y, m + 1, d) }, startDate.year, startDate.monthValue - 1, startDate.dayOfMonth).show() }) { Text("开始 ${startDate}") }
                    OutlinedButton(onClick = { DatePickerDialog(context, { _, y, m, d -> endDate = LocalDate.of(y, m + 1, d) }, endDate.year, endDate.monthValue - 1, endDate.dayOfMonth).show() }) { Text("结束 ${endDate}") }
                }
                OutlinedTextField(color, { color = it }, label = { Text("颜色 #RRGGBB") }, singleLine = true)
                OutlinedTextField(icon, { icon = it }, label = { Text("图标名称") }, singleLine = true)
                Text("磁贴大小", style = MaterialTheme.typography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) { listOf("mini", "small", "medium", "wide").forEach { value -> FilterChip(selected = tileSize == value, onClick = { tileSize = value }, label = { Text(value) }) } }
            }
        },
        confirmButton = { TextButton(enabled = name.isNotBlank() && !endDate.isBefore(startDate), onClick = { onSave(name, description, startDate, endDate, color, icon, tileSize) }) { Text("保存") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } }
    )
}
