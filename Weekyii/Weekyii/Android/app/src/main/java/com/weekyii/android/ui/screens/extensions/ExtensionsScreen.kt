package com.weekyii.android.ui.screens.extensions

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.BackHandler
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Button
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
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
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.draw.clip
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
import com.weekyii.android.ui.components.WeekyiiBottomSheet
import com.weekyii.android.ui.components.WeekyiiButton
import com.weekyii.android.ui.components.WeekyiiButtonStyle
import com.weekyii.android.ui.components.WeekyiiHeader
import com.weekyii.android.ui.components.WeekyiiTextField
import com.weekyii.android.ui.components.WeekyiiEmptyState
import com.weekyii.android.ui.theme.WeekyiiDimensions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Healing
import androidx.compose.material.icons.outlined.HourglassEmpty
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.CreateNewFolder
import com.weekyii.android.ui.theme.LocalWeekyiiPalette

private enum class ExtensionModule { MIND_STAMPS, SUSPENDED, PROJECTS }

@Composable
fun ExtensionsScreen(viewModel: ExtensionsViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val palette = LocalWeekyiiPalette.current
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
    var showProjectComposer by remember { mutableStateOf(false) }
    var showStampComposer by remember { mutableStateOf(false) }
    var showSuspendedComposer by remember { mutableStateOf(false) }
    var selectedModule by remember { mutableStateOf<ExtensionModule?>(null) }
    BackHandler(enabled = selectedModule != null) { selectedModule = null }
    val today = LocalDate.now()
    val stampImagePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) stampImage = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
    }
    val suspendedAttachmentPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { loadAttachment(context, it) }?.let(suspendedAttachments::add)
    }

    if (selectedModule == null) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(WeekyiiDimensions.screenPadding),
            verticalArrangement = Arrangement.spacedBy(WeekyiiDimensions.listGap)
        ) {
        item {
            WeekyiiHeader()
        }
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ShortcutModuleCard(
                    modifier = Modifier.weight(1f),
                    title = "呆胶布",
                    count = state.mindStamps.size,
                    countLabel = "张呆胶布",
                    icon = Icons.Outlined.Healing,
                    accentColor = palette.accentPink,
                    onClick = { selectedModule = ExtensionModule.MIND_STAMPS }
                )
                ShortcutModuleCard(
                    modifier = Modifier.weight(1f),
                    title = "悬置箱",
                    count = state.suspendedTasks.size,
                    countLabel = "项未决任务",
                    icon = Icons.Outlined.HourglassEmpty,
                    accentColor = palette.accentOrange,
                    onClick = { selectedModule = ExtensionModule.SUSPENDED }
                )
            }
        }
        item {
            WeekyiiCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 260.dp)
                    .clickable { selectedModule = ExtensionModule.PROJECTS }
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Outlined.FolderOpen, contentDescription = null, tint = palette.accentOrange)
                        Text("项目", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        Text(
                            "查看全部 ›",
                            modifier = Modifier.weight(1f).clickable { selectedModule = ExtensionModule.PROJECTS },
                            color = palette.accentOrange,
                            textAlign = TextAlign.End
                        )
                    }
                    Text("管理跨天任务与进度", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (state.projects.isEmpty()) {
                        Column(
                            modifier = Modifier.fillMaxWidth().padding(vertical = WeekyiiDimensions.spacingExtraLarge),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(WeekyiiDimensions.spacingMedium)
                        ) {
                            Icon(
                                Icons.Outlined.CreateNewFolder,
                                contentDescription = null,
                                tint = palette.accentOrange,
                                modifier = Modifier.size(48.dp)
                            )
                            Text("暂无项目", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            WeekyiiButton(
                                text = "新建项目",
                                style = WeekyiiButtonStyle.Primary,
                                onClick = { showProjectComposer = true }
                            )
                        }
                    } else {
                        Text("${state.projects.size} 个项目", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        state.error?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } }
        }
    }

    when (selectedModule) {
        ExtensionModule.MIND_STAMPS -> MindStampsModuleScreen(
            state = state,
            padding = padding,
            onBack = { selectedModule = null },
            onCreate = { showStampComposer = true },
            onDelete = viewModel::deleteMindStamp
        )
        ExtensionModule.SUSPENDED -> SuspendedModuleScreen(
            state = state,
            padding = padding,
            onBack = { selectedModule = null },
            onCreate = { showSuspendedComposer = true },
            onEdit = { editingSuspended = it },
            onAssign = { id, date -> viewModel.assignSuspendedTask(id, date) },
            onExtend = { viewModel.extendSuspendedTask(it, 10) },
            onDelete = { viewModel.deleteSuspendedTask(it) }
        )
        ExtensionModule.PROJECTS -> ProjectsModuleScreen(
            state = state,
            padding = padding,
            viewModel = viewModel,
            onBack = { selectedModule = null },
            onCreate = { showProjectComposer = true }
        )
        null -> Unit
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

    WeekyiiBottomSheet(visible = showProjectComposer, onDismiss = { showProjectComposer = false }) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("新建项目", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text("项目独立于每日任务流，适合持续推进的目标。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            WeekyiiTextField(projectName, { projectName = it }, "项目名称", Modifier.fillMaxWidth(), singleLine = true)
            WeekyiiTextField(projectDescription, { projectDescription = it }, "项目说明", Modifier.fillMaxWidth())
            WeekyiiButton(
                text = "创建项目",
                style = WeekyiiButtonStyle.Primary,
                enabled = projectName.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
                onClick = {
                    viewModel.createProject(projectName, projectDescription, today)
                    projectName = ""
                    projectDescription = ""
                    showProjectComposer = false
                }
            )
        }
    }

    WeekyiiBottomSheet(visible = showStampComposer, onDismiss = { showStampComposer = false }) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("添加 MindStamp", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text("给开始今天留下一个可以回看的锚点。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            WeekyiiTextField(stampText, { stampText = it }, "启动仪式内容", Modifier.fillMaxWidth())
            WeekyiiButton(text = if (stampImage == null) "添加图片" else "更换图片", style = WeekyiiButtonStyle.Outline, onClick = { stampImagePicker.launch(arrayOf("image/*")) })
            WeekyiiButton(
                text = "保存 MindStamp",
                style = WeekyiiButtonStyle.Primary,
                enabled = stampText.isNotBlank() || stampImage != null,
                modifier = Modifier.fillMaxWidth(),
                onClick = {
                    viewModel.createMindStamp(stampText, stampImage)
                    stampText = ""
                    stampImage = null
                    showStampComposer = false
                }
            )
        }
    }

    WeekyiiBottomSheet(visible = showSuspendedComposer, onDismiss = { showSuspendedComposer = false }) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("悬置新任务", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text("先把任务放进悬置箱，到期前再决定安排到哪一天。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            WeekyiiTextField(suspendedTitle, { suspendedTitle = it }, "任务名称", Modifier.fillMaxWidth())
            WeekyiiTextField(suspendedDescription, { suspendedDescription = it }, "备注", Modifier.fillMaxWidth())
            WeekyiiTextField(suspendedStepsText, { suspendedStepsText = it }, "步骤（每行一个）", Modifier.fillMaxWidth())
            ExtensionTaskTypePicker(definitions = state.taskTypeDefinitions, selectedId = state.selectedTaskTypeId, onSelect = viewModel::selectTaskType)
            WeekyiiButton(text = "附件 ${suspendedAttachments.size}", style = WeekyiiButtonStyle.Outline, onClick = { suspendedAttachmentPicker.launch(arrayOf("*/*")) })
            WeekyiiButton(
                text = "悬置 10 天",
                style = WeekyiiButtonStyle.Primary,
                enabled = suspendedTitle.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
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
                    showSuspendedComposer = false
                }
            )
        }
    }
}

@Composable
private fun ShortcutModuleCard(
    modifier: Modifier,
    title: String,
    count: Int,
    countLabel: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    accentColor: androidx.compose.ui.graphics.Color,
    onClick: () -> Unit
) {
    WeekyiiCard(modifier = modifier.aspectRatio(1f).clickable(onClick = onClick)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Top) {
            Icon(
                icon,
                contentDescription = null,
                tint = accentColor,
                modifier = Modifier
                    .size(46.dp)
                    .clip(CircleShape)
                    .background(accentColor.copy(alpha = 0.14f))
                    .padding(11.dp)
            )
            Text("↗", style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Column(modifier = Modifier.padding(top = 24.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Row(verticalAlignment = Alignment.Bottom) {
                Text(count.toString(), style = MaterialTheme.typography.headlineMedium, color = accentColor, fontWeight = FontWeight.Bold)
                Text(" $countLabel", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun ExtensionModuleHeader(
    title: String,
    onBack: () -> Unit,
    onCreate: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
        }
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        TextButton(onClick = onCreate) { Text("新增") }
    }
}

@Composable
private fun MindStampsModuleScreen(
    state: ExtensionsViewModel.UiState,
    padding: PaddingValues,
    onBack: () -> Unit,
    onCreate: () -> Unit,
    onDelete: (java.util.UUID) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item { ExtensionModuleHeader("呆胶布", onBack, onCreate) }
        if (state.mindStamps.isEmpty()) {
            item {
                WeekyiiCard {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Icon(Icons.Outlined.Healing, contentDescription = null, tint = MaterialTheme.colorScheme.secondary, modifier = Modifier.size(42.dp))
                        Text("暂无呆胶布", style = MaterialTheme.typography.titleMedium)
                        Text("右上角点 + 新建呆胶布", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        } else {
            items(state.mindStamps, key = { it.id }) { stamp ->
                WeekyiiCard {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        stamp.imageBlob?.let { bytes ->
                            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { bitmap ->
                                Image(bitmap.asImageBitmap(), "呆胶布图片", modifier = Modifier.size(56.dp), contentScale = ContentScale.Crop)
                            }
                        }
                        Text(stamp.text.ifBlank { "图片呆胶布" }, modifier = Modifier.weight(1f))
                        TextButton(onClick = { onDelete(stamp.id) }) { Text("删除") }
                    }
                }
            }
        }
    }
}

@Composable
private fun SuspendedModuleScreen(
    state: ExtensionsViewModel.UiState,
    padding: PaddingValues,
    onBack: () -> Unit,
    onCreate: () -> Unit,
    onEdit: (SuspendedTaskUi) -> Unit,
    onAssign: (java.util.UUID, LocalDate) -> Unit,
    onExtend: (java.util.UUID) -> Unit,
    onDelete: (java.util.UUID) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item { ExtensionModuleHeader("悬置箱", onBack, onCreate) }
        if (state.suspendedTasks.isEmpty()) {
            item {
                WeekyiiCard {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Icon(Icons.Outlined.HourglassEmpty, contentDescription = null, tint = MaterialTheme.colorScheme.tertiary, modifier = Modifier.size(42.dp))
                        Text("悬置箱为空", style = MaterialTheme.typography.titleMedium)
                        Text("先把暂时无法承诺日期的任务放在这里。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        items(state.suspendedTasks, key = { it.id }) { task ->
            WeekyiiCard {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(task.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(
                        state.taskTypeDefinitions.firstOrNull { it.idRaw == task.taskTypeIdRaw }?.name ?: task.taskType.name,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Text("${task.decisionDeadline.toLocalDate()} 到期 · 已延期 ${task.snoozeCount} 次")
                    if (task.description.isNotBlank()) Text(task.description, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AssignSuspendedButton { date -> onAssign(task.id, date) }
                        OutlinedButton(onClick = { onEdit(task) }) { Text("编辑") }
                        OutlinedButton(onClick = { onExtend(task.id) }) { Text("延长 10 天") }
                        OutlinedButton(onClick = { onDelete(task.id) }) { Text("删除") }
                    }
                }
            }
        }
    }
}

@Composable
private fun ProjectsModuleScreen(
    state: ExtensionsViewModel.UiState,
    padding: PaddingValues,
    viewModel: ExtensionsViewModel,
    onBack: () -> Unit,
    onCreate: () -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item { ExtensionModuleHeader("项目", onBack, onCreate) }
        if (state.projects.isEmpty()) {
            item {
                WeekyiiCard {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Icon(Icons.Outlined.CreateNewFolder, contentDescription = null, tint = MaterialTheme.colorScheme.tertiary, modifier = Modifier.size(48.dp))
                        Text("暂无项目", style = MaterialTheme.typography.titleMedium)
                        WeekyiiButton(text = "新建项目", style = WeekyiiButtonStyle.Primary, onClick = onCreate)
                    }
                }
            }
        }
        itemsIndexed(state.projects, key = { _, project -> project.id }) { index, project ->
            ProjectCard(project, viewModel, index > 0, index < state.projects.lastIndex, onOpen = { viewModel.openProject(project.id) })
        }
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
