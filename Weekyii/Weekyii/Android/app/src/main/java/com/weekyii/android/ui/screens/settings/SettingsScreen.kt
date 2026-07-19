package com.weekyii.android.ui.screens.settings

import android.Manifest
import android.os.Build
import android.app.TimePickerDialog
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.Label
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Build
import com.weekyii.android.data.db.entities.ExecutionMode
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskTypeDefinitionEntity
import com.weekyii.android.ui.viewmodel.SettingsViewModel
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import com.weekyii.android.ui.components.WeekyiiCard

private enum class SettingsSection(val title: String) {
    APPEARANCE("外观与主题"),
    TODAY("今日节奏"),
    TASK_TYPES("任务管理"),
    FUTURE("未来"),
    PROJECTS("项目"),
    DATA("数据与安全"),
    ABOUT("关于 Weekyii"),
    DEVELOPER("开发者与诊断")
}

private data class SettingsRowSpec(
    val section: SettingsSection,
    val title: String,
    val value: String? = null,
    val icon: ImageVector,
    val tint: Color
)

@Composable
fun SettingsScreen(viewModel: SettingsViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var editingDefinition by remember { mutableStateOf<TaskTypeDefinitionEntity?>(null) }
    var creatingType by remember { mutableStateOf(false) }
    var pendingExportData by remember { mutableStateOf<ByteArray?>(null) }
    var localArchiveMessage by remember { mutableStateOf<String?>(null) }
    var selectedSection by remember { mutableStateOf<SettingsSection?>(null) }
    BackHandler(enabled = selectedSection != null) { selectedSection = null }
    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val data = pendingExportData
        if (uri != null && data != null) {
            runCatching { context.contentResolver.openOutputStream(uri)?.use { it.write(data) } }
                .onSuccess { localArchiveMessage = "归档已保存" }
                .onFailure { localArchiveMessage = "保存失败：${it.message}" }
        }
        pendingExportData = null
    }
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: error("无法读取文件") }
                .onSuccess(viewModel::inspectImport)
                .onFailure { localArchiveMessage = "读取失败：${it.message}" }
        }
    }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    val activeTypes = state.taskTypeDefinitions.filterNot { it.isArchived }.sortedBy { it.sortOrder }
    val archivedTypes = state.taskTypeDefinitions.filter { it.isArchived && !it.isBuiltIn }.sortedBy { it.name }
    val resolvedDefaultId = state.defaultTaskTypeId.takeIf { id -> activeTypes.any { it.idRaw == id } } ?: "regular"

    if (selectedSection == null) {
        SettingsHomeScreen(
            state = state,
            padding = padding,
            onSelect = { selectedSection = it }
        )
    } else {
        LazyColumn(
            modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = { selectedSection = null }) { Text("‹ 返回") }
                Text(
                    selectedSection?.title ?: "设置",
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
            }
        }

        if (selectedSection == SettingsSection.APPEARANCE) item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.primary) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("主题", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("主题只改变 Android 外观，不改变任务逻辑。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(
                            listOf(
                                "amber" to "琥珀", "ocean" to "海蓝", "forest" to "森绿",
                                "rose" to "玫瑰", "lavender" to "薰紫", "graphite" to "石墨",
                                "sunset" to "落日", "mint" to "薄荷", "midnight" to "极夜",
                                "lotr" to "魔戒"
                            )
                        ) { (id, label) ->
                            FilterChip(selected = state.themeId == id, onClick = { viewModel.setTheme(id) }, label = { Text(label) })
                        }
                    }
                    Text("外观模式", style = MaterialTheme.typography.labelLarge)
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(listOf("system" to "跟随系统", "light" to "浅色", "dark" to "深色")) { (id, label) ->
                            FilterChip(selected = state.appearanceMode == id, onClick = { viewModel.setAppearanceMode(id) }, label = { Text(label) })
                        }
                    }
                }
            }
        }

        if (selectedSection == SettingsSection.PROJECTS) item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("项目默认值", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("只影响之后新建的项目。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("默认周期", style = MaterialTheme.typography.labelLarge)
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(listOf(7, 14, 30, 90)) { days ->
                            FilterChip(
                                selected = state.defaultProjectDurationDays == days,
                                onClick = { viewModel.setDefaultProjectDurationDays(days) },
                                label = { Text("$days 天") }
                            )
                        }
                    }
                    Text("默认磁贴尺寸", style = MaterialTheme.typography.labelLarge)
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(listOf("mini" to "迷你", "small" to "小", "medium" to "中", "wide" to "宽")) { (id, label) ->
                            FilterChip(
                                selected = state.defaultProjectTileSizeRaw == id,
                                onClick = { viewModel.setDefaultProjectTileSize(id) },
                                label = { Text(label) }
                            )
                        }
                    }
                }
            }
        }

        if (selectedSection == SettingsSection.TODAY) item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.tertiary) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("通知提醒", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("设置 Kill Time 前的提前提醒；系统仍会在截止时提醒。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(listOf(0, 15, 30, 60, 90, 120)) { minutes ->
                            val label = if (minutes == 0) "不提前" else "提前 $minutes 分钟"
                            FilterChip(
                                selected = state.killTimeReminderMinutes == minutes,
                                onClick = { viewModel.setKillTimeReminderMinutes(minutes) },
                                label = { Text(label) }
                            )
                        }
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("固定时刻提醒", style = MaterialTheme.typography.labelLarge)
                            Text("在每天指定时间补充一次提醒", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(
                            checked = state.fixedReminderEnabled,
                            onCheckedChange = viewModel::setFixedReminderEnabled
                        )
                    }
                    if (state.fixedReminderEnabled) {
                        OutlinedButton(onClick = {
                            TimePickerDialog(
                                context,
                                { _, hour, minute -> viewModel.setFixedReminderTime(hour, minute) },
                                state.fixedReminderHour,
                                state.fixedReminderMinute,
                                true
                            ).show()
                        }) {
                            Text("固定提醒 %02d:%02d".format(state.fixedReminderHour, state.fixedReminderMinute))
                        }
                    }
                    if (Build.VERSION.SDK_INT >= 33) {
                        OutlinedButton(onClick = { notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) }) { Text("请求通知权限") }
                    }
                }
            }
        }

        if (selectedSection == SettingsSection.TODAY) item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
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

        if (selectedSection == SettingsSection.DATA) item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.secondary) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("数据归档", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("导出包含任务、周、项目、MindStamp、悬置箱、任务类型和核心设置。导入会先创建本地恢复点，再替换当前数据。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            viewModel.exportArchive { bytes ->
                                pendingExportData = bytes
                                val stamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmm"))
                                exportLauncher.launch("weekyii-$stamp.json")
                            }
                        }) { Text("导出 JSON") }
                        OutlinedButton(onClick = { importLauncher.launch(arrayOf("application/json", "text/json", "text/plain")) }) {
                            Text("导入归档")
                        }
                    }
                    (state.archiveMessage ?: localArchiveMessage)?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
                }
            }
        }

        if (selectedSection == SettingsSection.TODAY) item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
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

        if (selectedSection == SettingsSection.TASK_TYPES) item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
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

        if (selectedSection == SettingsSection.TASK_TYPES && archivedTypes.isNotEmpty()) {
            item {
                WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
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

        if (selectedSection == SettingsSection.FUTURE) item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.primary) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("未来设置", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("未来周按周一开始，月视图会沿用任务类型的颜色标记。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("当前 Android 版本与 iOS 使用相同的周计算规则。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        if (selectedSection == SettingsSection.ABOUT) item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.secondary) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("关于 Weekyii", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("AI Native 的周粒度任务与 Todo 管理系统。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Android 原生版本 · 逻辑与 iOS 保持一致。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        if (selectedSection == SettingsSection.DEVELOPER) item {
            WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("开发者与诊断", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("用于查看构建和数据归档状态。生产任务逻辑不会因诊断入口改变。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        state.error?.let { message ->
            item { Text(message, color = MaterialTheme.colorScheme.error) }
        }
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

    state.importInspection?.let { inspection ->
        AlertDialog(
            onDismissRequest = viewModel::cancelImport,
            title = { Text("确认替换本地数据") },
            text = {
                Text(
                    "归档包含 ${inspection.weekCount} 周、${inspection.dayCount} 天、${inspection.taskCount} 个任务、${inspection.projectCount} 个项目和 ${inspection.taskTypeCount} 个任务类型。导入前会自动创建恢复点。"
                )
            },
            confirmButton = {
                TextButton(onClick = viewModel::confirmImport, enabled = !state.isImporting) {
                    Text(if (state.isImporting) "正在导入…" else "确认导入")
                }
            },
            dismissButton = { TextButton(onClick = viewModel::cancelImport) { Text("取消") } }
        )
    }
}

@Composable
private fun SettingsHomeScreen(
    state: SettingsViewModel.UiState,
    padding: PaddingValues,
    onSelect: (SettingsSection) -> Unit
) {
    val rows = listOf(
        "个性化" to listOf(
            SettingsRowSpec(SettingsSection.APPEARANCE, "外观与主题", "${themeLabel(state.themeId)} · ${appearanceLabel(state.appearanceMode)}", Icons.Outlined.Palette, Color(0xFFBF32D3))
        ),
        "使用方式" to listOf(
            SettingsRowSpec(SettingsSection.TODAY, "今日节奏", "%02d:%02d".format(state.defaultKillTime.hour, state.defaultKillTime.minute), Icons.Outlined.Timer, Color(0xFFFF8A2A)),
            SettingsRowSpec(SettingsSection.TASK_TYPES, "任务管理", "${state.taskTypeDefinitions.count { !it.isArchived }} 个类型", Icons.Outlined.Label, Color(0xFF13B5C8)),
            SettingsRowSpec(SettingsSection.FUTURE, "未来", "周一开始", Icons.Outlined.CalendarMonth, Color(0xFF237CF2)),
            SettingsRowSpec(SettingsSection.PROJECTS, "项目", "默认 ${state.defaultProjectDurationDays} 天", Icons.Outlined.Folder, Color(0xFFAF8A6C))
        ),
        "数据" to listOf(
            SettingsRowSpec(SettingsSection.DATA, "数据与安全", icon = Icons.Outlined.Lock, tint = Color(0xFF6257E8))
        ),
        "应用" to listOf(
            SettingsRowSpec(SettingsSection.ABOUT, "关于 Weekyii", icon = Icons.Outlined.Info, tint = Color(0xFF11BFAE)),
            SettingsRowSpec(SettingsSection.DEVELOPER, "开发者与诊断", icon = Icons.Outlined.Build, tint = Color(0xFF7B7B82))
        )
    )

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(padding),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        item {
            Text("设置", style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 8.dp))
        }
        rows.forEach { (sectionTitle, sectionRows) ->
            item(key = sectionTitle) {
                SettingsGroup(sectionTitle, sectionRows, onSelect)
            }
        }
    }
}

@Composable
private fun SettingsGroup(
    title: String,
    rows: List<SettingsRowSpec>,
    onSelect: (SettingsSection) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 12.dp))
        val shape = RoundedCornerShape(24.dp)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(MaterialTheme.colorScheme.surface)
                .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.08f), shape)
        ) {
            rows.forEachIndexed { index, row ->
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { onSelect(row.section) }.padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(modifier = Modifier.size(42.dp).clip(RoundedCornerShape(11.dp)).background(row.tint)) {
                        Icon(row.icon, contentDescription = null, tint = Color.White, modifier = Modifier.padding(9.dp))
                    }
                    Column(modifier = Modifier.weight(1f).padding(horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(row.title, style = MaterialTheme.typography.titleMedium)
                        row.value?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                    Text("›", style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.outline)
                }
                if (index < rows.lastIndex) HorizontalDivider(modifier = Modifier.padding(start = 72.dp), color = MaterialTheme.colorScheme.outline.copy(alpha = 0.12f))
            }
        }
    }
}

private fun themeLabel(id: String): String = mapOf(
    "amber" to "琥珀", "ocean" to "海蓝", "forest" to "森绿", "rose" to "玫瑰", "lavender" to "薰紫",
    "graphite" to "石墨", "sunset" to "落日", "mint" to "薄荷", "midnight" to "极夜", "lotr" to "魔戒"
)[id] ?: "琥珀"

private fun appearanceLabel(id: String): String = when (id) {
    "light" -> "浅色"
    "dark" -> "深色"
    else -> "自动"
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
