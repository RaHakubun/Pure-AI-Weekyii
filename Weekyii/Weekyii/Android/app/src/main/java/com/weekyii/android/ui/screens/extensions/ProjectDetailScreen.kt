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
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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

@Composable
fun ProjectDetailScreen(
    detail: ProjectDetailUi,
    padding: PaddingValues,
    error: String?,
    taskTypeDefinitions: List<TaskTypeDefinitionEntity>,
    onBack: () -> Unit,
    onStatusChange: (ProjectStatus) -> Unit,
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

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton(onClick = onBack) { Text("返回项目列表") }
                Text(project.status.name.lowercase(), color = MaterialTheme.colorScheme.primary)
            }
        }
        error?.let { message ->
            item { Text(message, color = MaterialTheme.colorScheme.error) }
        }
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when (project.status) {
                    ProjectStatus.PLANNING -> Button(onClick = { onStatusChange(ProjectStatus.ACTIVE) }) { Text("激活") }
                    ProjectStatus.ACTIVE -> if (detail.totalCount > 0 && detail.remainingCount == 0) {
                        Button(onClick = { onStatusChange(ProjectStatus.COMPLETED) }) { Text("确认结项") }
                    }
                    ProjectStatus.COMPLETED -> {
                        OutlinedButton(onClick = { onStatusChange(ProjectStatus.ACTIVE) }) { Text("重新打开") }
                        Button(onClick = { onStatusChange(ProjectStatus.ARCHIVED) }) { Text("归档") }
                    }
                    ProjectStatus.ARCHIVED -> OutlinedButton(onClick = { onStatusChange(ProjectStatus.COMPLETED) }) { Text("恢复") }
                }
                if (writable) {
                    OutlinedButton(onClick = { addDialog = true }) { Text("添加项目任务") }
                }
                OutlinedButton(onClick = { deletingProject = true }) { Text("删除项目") }
            }
        }
        item { Text("按日期排列的任务", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
        if (detail.sections.isEmpty()) {
            item { Text("项目暂无任务", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        } else {
            items(detail.sections, key = { it.date.toString() }) { section ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Column(modifier = Modifier.weight(1f)) {
            Text(task.title, fontWeight = FontWeight.SemiBold)
            Text(task.zone.name.lowercase(), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (editable) {
            TextButton(onClick = onEdit) { Text("编辑") }
            TextButton(onClick = onDelete) { Text("删除") }
        }
    }
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
