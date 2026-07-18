package com.weekyii.android.ui.screens.settings

import android.app.TimePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.ExecutionMode
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.ui.viewmodel.SettingsViewModel

@Composable
fun SettingsScreen(viewModel: SettingsViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var editingDefinition by remember { mutableStateOf<TaskTypeDefinitionEntity?>(null) }
    var creatingType by remember { mutableStateOf(false) }
    val activeTypes = state.taskTypeDefinitions.filterNot { it.isArchived }.sortedBy { it.sortOrder }
    val archivedTypes = state.taskTypeDefinitions.filter { it.isArchived && !it.isBuiltIn }.sortedBy { it.name }
    val resolvedDefaultId = state.defaultTaskTypeId.takeIf { id -> activeTypes.any { it.idRaw == id } } ?: "regular"

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text("设置", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text("默认设置只影响新任务和新的一天。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("默认 Kill Time", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    OutlinedButton(onClick = {
                        TimePickerDialog(
                            context,
                            { _, hour, minute -> viewModel.setDefaultKillTime(java.time.LocalTime.of(hour, minute)) },
                            state.defaultKillTime.hour,
                            state.defaultKillTime.minute,
                            true
                        ).show()
                    }) { Text(String.format("%02d:%02d", state.defaultKillTime.hour, state.defaultKillTime.minute)) }
                }
            }
        }

        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("默认执行模式", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (state.defaultExecutionMode == ExecutionMode.STRICT) FilledTonalButton(onClick = {}) { Text("严格") }
                        else OutlinedButton(onClick = { viewModel.setDefaultExecutionMode(ExecutionMode.STRICT) }) { Text("严格") }
                        if (state.defaultExecutionMode == ExecutionMode.FLEXIBLE) FilledTonalButton(onClick = {}) { Text("灵活") }
                        else OutlinedButton(onClick = { viewModel.setDefaultExecutionMode(ExecutionMode.FLEXIBLE) }) { Text("灵活") }
                    }
                }
            }
        }

        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("任务类型", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("自定义名称、颜色与图标；基础行为决定提醒和统计归类。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    activeTypes.forEachIndexed { index, definition ->
                        TaskTypeRow(
                            definition = definition,
                            isDefault = definition.idRaw == resolvedDefaultId,
                            onSetDefault = { viewModel.setDefaultTaskType(definition.idRaw) },
                            onEdit = { editingDefinition = definition },
                            onArchive = { viewModel.archiveTaskType(definition.idRaw) }
                        )
                        if (index < activeTypes.lastIndex) HorizontalDivider()
                    }
                    Button(onClick = { creatingType = true }, modifier = Modifier.fillMaxWidth()) {
                        Text("新增任务类型")
                    }
                }
            }
        }

        if (archivedTypes.isNotEmpty()) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("已归档类型", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        archivedTypes.forEach { definition ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(definition.name, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                TextButton(onClick = { viewModel.restoreTaskType(definition.idRaw) }) { Text("恢复") }
                            }
                        }
                    }
                }
            }
        }

        state.error?.let { message ->
            item { Text(message, color = MaterialTheme.colorScheme.error) }
        }
    }

    if (creatingType) {
        TaskTypeEditorDialog(
            definition = null,
            onDismiss = { creatingType = false },
            onSave = { name, icon, color, baseKind ->
                viewModel.createTaskType(name, icon, color, baseKind)
                creatingType = false
            }
        )
    }

    editingDefinition?.let { definition ->
        TaskTypeEditorDialog(
            definition = definition,
            onDismiss = { editingDefinition = null },
            onSave = { name, icon, color, baseKind ->
                viewModel.updateTaskType(definition.idRaw, name, icon, color, baseKind)
                editingDefinition = null
            }
        )
    }
}

@Composable
private fun TaskTypeRow(
    definition: TaskTypeDefinitionEntity,
    isDefault: Boolean,
    onSetDefault: () -> Unit,
    onEdit: () -> Unit,
    onArchive: () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(32.dp).background(parseColor(definition.colorHex), MaterialTheme.shapes.small)
            )
            Column(modifier = Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(definition.name, fontWeight = FontWeight.SemiBold)
                Text(
                    "${if (definition.isBuiltIn) "系统类型" else "自定义类型"} · ${definition.baseKind.displayName()}行为",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (isDefault) Text("默认", color = parseColor(definition.colorHex), fontWeight = FontWeight.SemiBold)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!isDefault) TextButton(onClick = onSetDefault) { Text("设为默认") }
            if (!definition.isBuiltIn) {
                TextButton(onClick = onEdit) { Text("编辑") }
                TextButton(onClick = onArchive) { Text("归档", color = MaterialTheme.colorScheme.error) }
            }
        }
    }
}

@Composable
private fun TaskTypeEditorDialog(
    definition: TaskTypeDefinitionEntity?,
    onDismiss: () -> Unit,
    onSave: (String, String, String, TaskType) -> Unit
) {
    var name by remember(definition?.idRaw) { mutableStateOf(definition?.name.orEmpty()) }
    var iconName by remember(definition?.idRaw) { mutableStateOf(definition?.iconName ?: "tag") }
    var colorHex by remember(definition?.idRaw) { mutableStateOf(definition?.colorHex ?: "#4D9DE0") }
    var baseKind by remember(definition?.idRaw) { mutableStateOf(definition?.baseKind ?: TaskType.REGULAR) }
    val valid = name.isNotBlank() && iconName.isNotBlank() && Regex("^#[0-9A-Fa-f]{6}$").matches(colorHex)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (definition == null) "新增任务类型" else "编辑任务类型") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text("名称") }, singleLine = true)
                OutlinedTextField(iconName, { iconName = it }, label = { Text("Material 图标名称") }, singleLine = true)
                OutlinedTextField(colorHex, { colorHex = it }, label = { Text("颜色 #RRGGBB") }, singleLine = true)
                Text("任务行为", fontWeight = FontWeight.SemiBold)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    TaskType.entries.forEach { type ->
                        FilterChip(
                            selected = baseKind == type,
                            onClick = { baseKind = type },
                            label = { Text(type.displayName()) }
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(name.trim(), iconName.trim(), colorHex, baseKind) }, enabled = valid) {
                Text("保存")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } }
    )
}

private fun TaskType.displayName(): String = when (this) {
    TaskType.REGULAR -> "常规"
    TaskType.DDL -> "DDL"
    TaskType.LEISURE -> "休闲"
}

private fun parseColor(hex: String): Color = runCatching { Color(android.graphics.Color.parseColor(hex)) }
    .getOrDefault(Color(0xFF4A90A4))
