package com.weekyii.android.ui.screens.extensions

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Button
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.data.repository.TaskAttachmentDraft
import com.weekyii.android.ui.model.ProjectUi
import com.weekyii.android.ui.model.SuspendedTaskUi
import com.weekyii.android.ui.model.TaskAttachmentUi
import com.weekyii.android.ui.viewmodel.ExtensionsViewModel
import java.time.LocalDate
import com.weekyii.android.ui.components.WeekyiiCard

@Composable
fun ExtensionsScreen(viewModel: ExtensionsViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    state.projectDetail?.let { detail ->
        LaunchedEffect(state.selectedProjectId) { viewModel.refreshSelectedProject() }
        ProjectDetailScreen(
            detail = detail,
            padding = padding,
            error = state.error,
            taskTypeDefinitions = state.taskTypeDefinitions,
            onBack = viewModel::closeProject,
            onStatusChange = { status -> viewModel.updateProjectStatus(detail.project.id, status) },
            onUpdateProject = { name, description, startDate, endDate, color, icon, tileSize ->
                viewModel.updateProjectMetadata(detail.project.id, name, description, startDate, endDate, color, icon, tileSize)
            },
            onAddTasks = { title, description, taskType, taskTypeIdRaw, dates ->
                viewModel.addProjectTask(
                    projectId = detail.project.id,
                    title = title,
                    description = description,
                    taskType = taskType,
                    taskTypeIdRaw = taskTypeIdRaw,
                    dates = dates
                )
            },
            onUpdateTask = { task, title, description ->
                viewModel.updateProjectTask(
                    projectId = detail.project.id,
                    taskId = task.id,
                    title = title,
                    description = description,
                    taskType = task.taskType,
                    taskTypeIdRaw = task.taskTypeIdRaw
                )
            },
            onDeleteTask = { task -> viewModel.deleteProjectTask(detail.project.id, task.id) },
            onDeleteProject = { includeTasks -> viewModel.deleteProject(detail.project.id, includeTasks) }
        )
        return
    }
    var projectName by remember { mutableStateOf("") }
    var projectDescription by remember { mutableStateOf("") }
    var stampText by remember { mutableStateOf("") }
    var suspendedTitle by remember { mutableStateOf("") }
    var suspendedDescription by remember { mutableStateOf("") }
    var suspendedStepsText by remember { mutableStateOf("") }
    val suspendedAttachments = remember { mutableStateListOf<TaskAttachmentUi>() }
    var stampImage by remember { mutableStateOf<ByteArray?>(null) }
    var editingSuspended by remember { mutableStateOf<SuspendedTaskUi?>(null) }
    val today = LocalDate.now()
    val stampImagePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) stampImage = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
    }
    val suspendedAttachmentPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { loadAttachment(context, it) }?.let(suspendedAttachments::add)
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("拓展", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text("项目和 MindStamp 独立于每日任务流，但可以作为长期上下文。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.primary) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("新建项目", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    OutlinedTextField(projectName, { projectName = it }, label = { Text("项目名称") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(projectDescription, { projectDescription = it }, label = { Text("项目说明") }, modifier = Modifier.fillMaxWidth())
                    Button(
                        onClick = {
                            viewModel.createProject(projectName, projectDescription, today)
                            projectName = ""
                            projectDescription = ""
                        },
                        enabled = projectName.isNotBlank()
                    ) { Text("创建项目") }
                }
            }
        }
        item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.tertiary) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("MindStamp", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    OutlinedTextField(stampText, { stampText = it }, label = { Text("启动仪式内容") }, modifier = Modifier.fillMaxWidth())
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { stampImagePicker.launch(arrayOf("image/*")) }) { Text(if (stampImage == null) "添加图片" else "更换图片") }
                        Button(onClick = { viewModel.createMindStamp(stampText, stampImage); stampText = ""; stampImage = null }, enabled = stampText.isNotBlank() || stampImage != null) { Text("保存 MindStamp") }
                    }
                }
            }
        }
        item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.secondary) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("悬置任务", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("暂时不安排到某一天，到期前再决定去向。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    OutlinedTextField(suspendedTitle, { suspendedTitle = it }, label = { Text("任务名称") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(suspendedDescription, { suspendedDescription = it }, label = { Text("备注") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(
                        suspendedStepsText,
                        { suspendedStepsText = it },
                        label = { Text("步骤（每行一个）") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    ExtensionTaskTypePicker(
                        definitions = state.taskTypeDefinitions,
                        selectedId = state.selectedTaskTypeId,
                        onSelect = viewModel::selectTaskType
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        OutlinedButton(onClick = { suspendedAttachmentPicker.launch(arrayOf("*/*")) }) {
                            Text("附件 ${suspendedAttachments.size}")
                        }
                        Button(
                            onClick = {
                                viewModel.createSuspendedTask(
                                    title = suspendedTitle,
                                    countdownDays = 10,
                                    description = suspendedDescription,
                                    stepTitles = suspendedStepsText.lines(),
                                    attachments = suspendedAttachments.map { TaskAttachmentDraft(it.fileName, it.fileType, it.data) }
                                )
                                suspendedTitle = ""
                                suspendedDescription = ""
                                suspendedStepsText = ""
                                suspendedAttachments.clear()
                            },
                            enabled = suspendedTitle.isNotBlank()
                        ) { Text("悬置 10 天") }
                    }
                    suspendedAttachments.forEachIndexed { index, attachment ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(attachment.fileName, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                            TextButton(onClick = { suspendedAttachments.removeAt(index) }) { Text("移除") }
                        }
                    }
                }
            }
        }
        state.error?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } }
        item { Text("悬置箱", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
        items(state.suspendedTasks, key = { it.id }) { task ->
            WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(task.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(
                        state.taskTypeDefinitions.firstOrNull { it.idRaw == task.taskTypeIdRaw }?.name ?: task.taskType.name,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Text("${task.decisionDeadline.toLocalDate()} 到期 · 已延期 ${task.snoozeCount} 次")
                    if (task.description.isNotBlank()) Text(task.description, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (task.steps.isNotEmpty() || task.attachments.isNotEmpty()) {
                        Text("${task.steps.size} 个步骤 · ${task.attachments.size} 个附件", style = MaterialTheme.typography.labelMedium)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AssignSuspendedButton { date -> viewModel.assignSuspendedTask(task.id, date) }
                        OutlinedButton(onClick = { editingSuspended = task }) { Text("编辑") }
                        OutlinedButton(onClick = { viewModel.extendSuspendedTask(task.id, 10) }) { Text("延长 10 天") }
                        OutlinedButton(onClick = { viewModel.deleteSuspendedTask(task.id) }) { Text("删除") }
                    }
                }
            }
        }
        item { Text("项目", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
        itemsIndexed(state.projects, key = { _, project -> project.id }) { index, project ->
            ProjectCard(project, viewModel, index > 0, index < state.projects.lastIndex, onOpen = { viewModel.openProject(project.id) })
        }
        item { Text("已保存的 MindStamp", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
        items(state.mindStamps, key = { it.id }) { stamp ->
            WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    stamp.imageBlob?.let { bytes ->
                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { bitmap -> Image(bitmap.asImageBitmap(), "MindStamp 图片", modifier = Modifier.size(56.dp), contentScale = ContentScale.Crop) }
                    }
                    Text(stamp.text.ifBlank { "图片 MindStamp" }, modifier = Modifier.weight(1f))
                    OutlinedButton(onClick = { viewModel.deleteMindStamp(stamp.id) }) { Text("删除") }
                }
            }
        }
    }

    editingSuspended?.let { task ->
        SuspendedTaskEditorDialog(
            task = task,
            definitions = state.taskTypeDefinitions,
            onDismiss = { editingSuspended = null },
            onSave = { title, description, typeId, days, steps, attachments ->
                viewModel.updateSuspendedTask(task.id, title, description, typeId, days, steps, attachments)
                editingSuspended = null
            }
        )
    }
}

@Composable
private fun SuspendedTaskEditorDialog(
    task: SuspendedTaskUi,
    definitions: List<TaskTypeDefinitionEntity>,
    onDismiss: () -> Unit,
    onSave: (String, String, String, Int, List<String>, List<TaskAttachmentDraft>) -> Unit
) {
    var title by remember(task.id) { mutableStateOf(task.title) }
    var description by remember(task.id) { mutableStateOf(task.description) }
    var typeId by remember(task.id) { mutableStateOf(task.taskTypeIdRaw) }
    var daysText by remember(task.id) { mutableStateOf(task.preferredCountdownDays.toString()) }
    var stepsText by remember(task.id) { mutableStateOf(task.steps.sortedBy { it.sortOrder }.joinToString("\n") { it.title }) }
    val attachments = remember(task.id) { mutableStateListOf<TaskAttachmentUi>().apply { addAll(task.attachments) } }
    val context = LocalContext.current
    val attachmentPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { loadAttachment(context, it) }?.let(attachments::add)
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("编辑悬置任务") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(title, { title = it }, label = { Text("标题") }, singleLine = true)
                OutlinedTextField(description, { description = it }, label = { Text("备注") })
                OutlinedTextField(stepsText, { stepsText = it }, label = { Text("步骤（每行一个）") })
                OutlinedTextField(daysText, { daysText = it.filter(Char::isDigit) }, label = { Text("倒计时天数") }, singleLine = true)
                androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(if (definitions.isEmpty()) listOf("regular", "ddl", "leisure") else definitions.map { it.idRaw }) { id ->
                        FilterChip(selected = typeId == id, onClick = { typeId = id }, label = { Text(id) })
                    }
                }
                OutlinedButton(onClick = { attachmentPicker.launch(arrayOf("*/*")) }) { Text("添加附件（${attachments.size}）") }
                attachments.forEachIndexed { index, attachment ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(attachment.fileName, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                        TextButton(onClick = { attachments.removeAt(index) }) { Text("移除") }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onSave(
                        title,
                        description,
                        typeId,
                        daysText.toIntOrNull() ?: 0,
                        stepsText.lines(),
                        attachments.map { TaskAttachmentDraft(it.fileName, it.fileType, it.data) }
                    )
                },
                enabled = title.isNotBlank() && (daysText.toIntOrNull() ?: 0) > 0
            ) { Text("保存") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } }
    )
}

@Composable
private fun ExtensionTaskTypePicker(
    definitions: List<TaskTypeDefinitionEntity>,
    selectedId: String,
    onSelect: (String) -> Unit
) {
    if (definitions.isEmpty()) return
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

@Composable
private fun AssignSuspendedButton(onAssign: (LocalDate) -> Unit) {
    val context = LocalContext.current
    OutlinedButton(onClick = {
        val tomorrow = LocalDate.now().plusDays(1)
        android.app.DatePickerDialog(
            context,
            { _, year, month, day -> onAssign(LocalDate.of(year, month + 1, day)) },
            tomorrow.year,
            tomorrow.monthValue - 1,
            tomorrow.dayOfMonth
        ).show()
    }) { Text("指派") }
}

@Composable
private fun ProjectCard(project: ProjectUi, viewModel: ExtensionsViewModel, canMoveUp: Boolean, canMoveDown: Boolean, onOpen: () -> Unit) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(project.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(project.description.ifBlank { "无项目说明" }, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("${project.startDate} ~ ${project.endDate}")
            Text("磁贴：${project.tileSizeRaw}", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(enabled = canMoveUp, onClick = { viewModel.moveProject(project.id, -1) }) { Text("上移") }
                OutlinedButton(enabled = canMoveDown, onClick = { viewModel.moveProject(project.id, 1) }) { Text("下移") }
                if (project.status == ProjectStatus.ACTIVE) OutlinedButton(onClick = {}) { Text("进行中") }
                else Button(onClick = { viewModel.updateProjectStatus(project.id, ProjectStatus.ACTIVE) }) { Text("激活") }
                OutlinedButton(onClick = { viewModel.deleteProject(project.id) }) { Text("删除") }
            }
        }
    }
}

private fun loadAttachment(context: Context, uri: Uri): TaskAttachmentUi? {
    val data = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return null
    val fileName = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
    } ?: uri.lastPathSegment?.substringAfterLast('/') ?: "attachment"
    return TaskAttachmentUi(
        fileName = fileName,
        fileType = context.contentResolver.getType(uri) ?: "application/octet-stream",
        data = data
    )
}
