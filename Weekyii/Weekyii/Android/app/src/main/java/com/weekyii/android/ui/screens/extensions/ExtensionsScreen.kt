package com.weekyii.android.ui.screens.extensions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.ui.model.ProjectUi
import com.weekyii.android.ui.viewmodel.ExtensionsViewModel
import java.time.LocalDate

@Composable
fun ExtensionsScreen(viewModel: ExtensionsViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    var projectName by remember { mutableStateOf("") }
    var projectDescription by remember { mutableStateOf("") }
    var stampText by remember { mutableStateOf("") }
    var suspendedTitle by remember { mutableStateOf("") }
    val today = LocalDate.now()

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
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("新建项目", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    OutlinedTextField(projectName, { projectName = it }, label = { Text("项目名称") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(projectDescription, { projectDescription = it }, label = { Text("项目说明") }, modifier = Modifier.fillMaxWidth())
                    Button(
                        onClick = {
                            viewModel.createProject(projectName, projectDescription, today, today.plusDays(30))
                            projectName = ""
                            projectDescription = ""
                        },
                        enabled = projectName.isNotBlank()
                    ) { Text("创建项目") }
                }
            }
        }
        item {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("MindStamp", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    OutlinedTextField(stampText, { stampText = it }, label = { Text("启动仪式内容") }, modifier = Modifier.fillMaxWidth())
                    Button(onClick = { viewModel.createMindStamp(stampText); stampText = "" }, enabled = stampText.isNotBlank()) { Text("保存 MindStamp") }
                }
            }
        }
        item {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("悬置任务", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("暂时不安排到某一天，到期前再决定去向。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    OutlinedTextField(suspendedTitle, { suspendedTitle = it }, label = { Text("任务名称") }, modifier = Modifier.fillMaxWidth())
                    Button(
                        onClick = { viewModel.createSuspendedTask(suspendedTitle, 10); suspendedTitle = "" },
                        enabled = suspendedTitle.isNotBlank()
                    ) { Text("悬置 10 天") }
                }
            }
        }
        state.error?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } }
        item { Text("悬置箱", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
        items(state.suspendedTasks, key = { it.id }) { task ->
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(task.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("${task.decisionDeadline.toLocalDate()} 到期 · 已延期 ${task.snoozeCount} 次")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AssignSuspendedButton { date -> viewModel.assignSuspendedTask(task.id, date) }
                        OutlinedButton(onClick = { viewModel.extendSuspendedTask(task.id, 10) }) { Text("延长 10 天") }
                        OutlinedButton(onClick = { viewModel.deleteSuspendedTask(task.id) }) { Text("删除") }
                    }
                }
            }
        }
        item { Text("项目", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
        items(state.projects, key = { it.id }) { project -> ProjectCard(project, viewModel) }
        item { Text("已保存的 MindStamp", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
        items(state.mindStamps, key = { it.id }) { stamp ->
            Card(modifier = Modifier.fillMaxWidth()) {
                Row(modifier = Modifier.padding(14.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(stamp.text.ifBlank { "图片 MindStamp" }, modifier = Modifier.weight(1f))
                    OutlinedButton(onClick = { viewModel.deleteMindStamp(stamp.id) }) { Text("删除") }
                }
            }
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
private fun ProjectCard(project: ProjectUi, viewModel: ExtensionsViewModel) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(project.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(project.description.ifBlank { "无项目说明" }, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("${project.startDate} ~ ${project.endDate}")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (project.status == ProjectStatus.ACTIVE) OutlinedButton(onClick = {}) { Text("进行中") }
                else Button(onClick = { viewModel.updateProjectStatus(project.id, ProjectStatus.ACTIVE) }) { Text("激活") }
                OutlinedButton(onClick = { viewModel.deleteProject(project.id) }) { Text("删除") }
            }
        }
    }
}
