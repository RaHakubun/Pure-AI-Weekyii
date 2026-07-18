package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.ProjectDao
import com.weekyii.android.data.db.dao.DayDao
import com.weekyii.android.data.db.dao.TaskDao
import com.weekyii.android.data.db.dao.WeekDao
import com.weekyii.android.data.db.AppDatabase
import androidx.room.withTransaction
import com.weekyii.android.data.db.entities.DayEntity
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.ProjectEntity
import com.weekyii.android.data.db.entities.ProjectStatus
import com.weekyii.android.data.db.entities.TaskEntity
import com.weekyii.android.data.db.entities.TaskType
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.data.db.entities.WeekEntity
import com.weekyii.android.data.db.entities.WeekStatus
import com.weekyii.android.domain.TimeProvider
import com.weekyii.android.ui.model.ProjectUi
import com.weekyii.android.ui.model.ProjectDetailSectionUi
import com.weekyii.android.ui.model.ProjectDetailUi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.LocalDate
import java.time.ZoneId
import java.util.Date
import java.util.UUID

class ProjectRepository(
    private val projectDao: ProjectDao,
    private val timeProvider: TimeProvider,
    private val zoneId: ZoneId = ZoneId.systemDefault(),
    private val weekDao: WeekDao? = null,
    private val dayDao: DayDao? = null,
    private val taskDao: TaskDao? = null,
    private val weekCalculator: WeekCalculator = WeekCalculator(),
    private val database: AppDatabase? = null
) {
    fun observeProjects(): Flow<List<ProjectUi>> = projectDao.observeAll()
        .map { projects -> projects.sortedBy { it.tileOrder }.map { it.toUi(zoneId) } }

    suspend fun createProject(
        name: String,
        description: String,
        startDate: LocalDate,
        endDate: LocalDate
    ): UUID {
        require(name.isNotBlank()) { "Project name cannot be empty" }
        require(!startDate.isBefore(timeProvider.today)) { "Project cannot start in the past" }
        require(!endDate.isBefore(startDate)) { "Project end date must not precede start date" }
        val project = ProjectEntity(
            name = name.trim(),
            description = description.trim(),
            startDate = startDate.asDate(zoneId),
            endDate = endDate.asDate(zoneId),
            tileOrder = (projectDao.maxTileOrder() ?: -1) + 1
        )
        projectDao.upsert(project)
        return project.projectId
    }

    suspend fun updateStatus(id: UUID, status: ProjectStatus) = inTransaction {
        updateStatusInternal(id, status)
    }

    private suspend fun updateStatusInternal(id: UUID, status: ProjectStatus) {
        val project = projectDao.findById(id) ?: return
        val allowed = when (project.status to status) {
            ProjectStatus.PLANNING to ProjectStatus.ACTIVE,
            ProjectStatus.ACTIVE to ProjectStatus.COMPLETED,
            ProjectStatus.COMPLETED to ProjectStatus.ARCHIVED,
            ProjectStatus.COMPLETED to ProjectStatus.ACTIVE,
            ProjectStatus.ARCHIVED to ProjectStatus.COMPLETED -> true
            else -> project.status == status
        }
        require(allowed) { "当前项目状态不能执行该操作。" }
        if (status == ProjectStatus.COMPLETED) {
            val projectTasks = taskDao?.allTasks()?.orEmpty()?.filter { it.projectOwnerId == id }.orEmpty()
            require(projectTasks.isNotEmpty() && projectTasks.all { it.zone == TaskZone.COMPLETE }) {
                "项目仍有未完成任务。"
            }
        }
        projectDao.upsert(project.copy(status = status))
    }

    suspend fun updateProject(id: UUID, name: String, description: String) = inTransaction {
        updateProjectInternal(id, name, description)
    }

    private suspend fun updateProjectInternal(id: UUID, name: String, description: String) {
        require(name.isNotBlank()) { "Project name cannot be empty" }
        val project = projectDao.findById(id) ?: return
        require(project.status == ProjectStatus.PLANNING || project.status == ProjectStatus.ACTIVE) {
            "项目已完成或归档，无法编辑。"
        }
        projectDao.upsert(project.copy(name = name.trim(), description = description.trim()))
    }

    suspend fun updateProjectMetadata(
        id: UUID,
        name: String,
        description: String,
        startDate: LocalDate,
        endDate: LocalDate,
        color: String,
        icon: String,
        tileSizeRaw: String
    ) = inTransaction {
        require(name.isNotBlank()) { "Project name cannot be empty" }
        require(!startDate.isBefore(timeProvider.today)) { "Project cannot start in the past" }
        require(!endDate.isBefore(startDate)) { "Project end date must not precede start date" }
        require(tileSizeRaw in setOf("mini", "small", "medium", "wide")) { "Unknown project tile size" }
        val project = projectDao.findById(id) ?: return@inTransaction
        require(project.status == ProjectStatus.PLANNING || project.status == ProjectStatus.ACTIVE) { "项目已完成或归档，无法编辑。" }
        val days = dayDao?.allDays()?.associateBy { it.dayId }.orEmpty()
        val projectTasks = taskDao?.allTasks()?.filter { it.projectOwnerId == id }.orEmpty()
        require(projectTasks.all { task ->
            val date = days[task.dayOwnerId]?.date?.toInstant()?.atZone(zoneId)?.toLocalDate()
            date != null && !date.isBefore(startDate) && !date.isAfter(endDate)
        }) { "新的日期范围不能排除已有项目任务。" }
        projectDao.upsert(project.copy(
            name = name.trim(),
            description = description.trim(),
            startDate = startDate.asDate(zoneId),
            endDate = endDate.asDate(zoneId),
            color = color,
            icon = icon,
            tileSizeRaw = tileSizeRaw
        ))
    }

    suspend fun moveProject(id: UUID, direction: Int) = inTransaction {
        val ordered = projectDao.allProjects().sortedBy { it.tileOrder }.toMutableList()
        val index = ordered.indexOfFirst { it.projectId == id }
        if (index < 0) return@inTransaction
        val target = (index + direction).coerceIn(0, ordered.lastIndex)
        if (target == index) return@inTransaction
        val item = ordered.removeAt(index)
        ordered.add(target, item)
        ordered.forEachIndexed { order, project -> projectDao.upsert(project.copy(tileOrder = order)) }
    }

    suspend fun addTask(
        projectId: UUID,
        title: String,
        description: String = "",
        taskType: TaskType = TaskType.REGULAR,
        taskTypeIdRaw: String = taskType.name.lowercase(),
        targetDate: LocalDate
    ): UUID = inTransaction {
        addTaskInternal(projectId, title, description, taskType, taskTypeIdRaw, targetDate)
    }

    private suspend fun addTaskInternal(
        projectId: UUID,
        title: String,
        description: String,
        taskType: TaskType,
        taskTypeIdRaw: String,
        targetDate: LocalDate
    ): UUID {
        require(title.isNotBlank()) { "项目任务名称不能为空。" }
        val project = projectDao.findById(projectId) ?: error("Project not found")
        require(project.status == ProjectStatus.PLANNING || project.status == ProjectStatus.ACTIVE) {
            "项目已完成或归档，无法添加任务。"
        }
        val projectStart = project.startDate.toInstant().atZone(zoneId).toLocalDate()
        val projectEnd = project.endDate.toInstant().atZone(zoneId).toLocalDate()
        require(!targetDate.isBefore(projectStart) && !targetDate.isAfter(projectEnd)) {
            "任务日期必须位于项目日期范围内。"
        }
        require(!targetDate.isBefore(timeProvider.today)) { "不能向已过期日期添加项目任务。" }

        val resolvedDayDao = requireNotNull(dayDao) { "Project task storage is unavailable" }
        val resolvedTaskDao = requireNotNull(taskDao) { "Project task storage is unavailable" }
        ensureWeekAndDays(targetDate)
        val day = resolvedDayDao.findWithTasks(targetDate.toString()) ?: error("Target day not found")
        require(day.day.status == DayStatus.EMPTY || day.day.status == DayStatus.DRAFT) {
            "目标日期任务流已锁定。"
        }

        val task = TaskEntity(
            title = title.trim(),
            description = description.trim(),
            taskType = taskType,
            taskTypeIdRaw = taskTypeIdRaw,
            order = (day.tasks.maxOfOrNull { it.order } ?: 0) + 1,
            zone = TaskZone.DRAFT,
            dayOwnerId = targetDate.toString(),
            projectOwnerId = projectId
        )
        resolvedTaskDao.upsert(task)
        if (day.day.status == DayStatus.EMPTY) {
            resolvedDayDao.upsert(day.day.copy(status = DayStatus.DRAFT))
        }
        if (project.status == ProjectStatus.PLANNING) {
            projectDao.upsert(project.copy(status = ProjectStatus.ACTIVE))
        }
        return task.id
    }

    suspend fun addTasks(
        projectId: UUID,
        title: String,
        description: String = "",
        taskType: TaskType = TaskType.REGULAR,
        taskTypeIdRaw: String = taskType.name.lowercase(),
        targetDates: List<LocalDate>
    ): List<UUID> {
        val dates = targetDates.distinct().sorted()
        require(dates.isNotEmpty()) { "至少选择一个任务日期。" }
        dates.forEach { validateTaskPlacement(projectId, it) }
        suspend fun writeAll(): List<UUID> = dates.map {
            addTaskInternal(projectId, title, description, taskType, taskTypeIdRaw, it)
        }
        return inTransaction { writeAll() }
    }

    suspend fun validateTaskPlacement(projectId: UUID, targetDate: LocalDate) {
        val project = projectDao.findById(projectId) ?: error("Project not found")
        require(project.status == ProjectStatus.PLANNING || project.status == ProjectStatus.ACTIVE) {
            "项目已完成或归档，无法添加任务。"
        }
        val projectStart = project.startDate.toInstant().atZone(zoneId).toLocalDate()
        val projectEnd = project.endDate.toInstant().atZone(zoneId).toLocalDate()
        require(!targetDate.isBefore(projectStart) && !targetDate.isAfter(projectEnd)) {
            "任务日期必须位于项目日期范围内。"
        }
        require(!targetDate.isBefore(timeProvider.today)) { "不能向已过期日期添加项目任务。" }
        val existingDay = dayDao?.findById(targetDate.toString())
        if (existingDay != null) {
            require(existingDay.status == DayStatus.EMPTY || existingDay.status == DayStatus.DRAFT) {
                "目标日期任务流已锁定。"
            }
        }
    }

    suspend fun updateTask(
        projectId: UUID,
        taskId: UUID,
        title: String,
        description: String = "",
        taskType: TaskType = TaskType.REGULAR,
        taskTypeIdRaw: String = taskType.name.lowercase()
    ) = inTransaction {
        updateTaskInternal(projectId, taskId, title, description, taskType, taskTypeIdRaw)
    }

    private suspend fun updateTaskInternal(
        projectId: UUID,
        taskId: UUID,
        title: String,
        description: String,
        taskType: TaskType,
        taskTypeIdRaw: String
    ) {
        require(title.isNotBlank()) { "项目任务名称不能为空。" }
        val project = projectDao.findById(projectId) ?: return
        require(project.status == ProjectStatus.PLANNING || project.status == ProjectStatus.ACTIVE) {
            "项目已完成或归档，无法编辑任务。"
        }
        val resolvedTaskDao = requireNotNull(taskDao) { "Project task storage is unavailable" }
        val resolvedDayDao = requireNotNull(dayDao) { "Project task storage is unavailable" }
        val task = resolvedTaskDao.findById(taskId) ?: return
        require(task.projectOwnerId == projectId && task.zone == TaskZone.DRAFT) {
            "只有未启动的项目草稿任务可以编辑。"
        }
        val day = resolvedDayDao.findById(task.dayOwnerId) ?: error("Task day not found")
        require(day.status == DayStatus.EMPTY || day.status == DayStatus.DRAFT) {
            "任务所在日期已锁定。"
        }
        resolvedTaskDao.upsert(
            task.copy(
                title = title.trim(),
                description = description.trim(),
                taskType = taskType,
                taskTypeIdRaw = taskTypeIdRaw
            )
        )
    }

    suspend fun deleteTask(projectId: UUID, taskId: UUID) = inTransaction {
        deleteTaskInternal(projectId, taskId)
    }

    private suspend fun deleteTaskInternal(projectId: UUID, taskId: UUID) {
        val project = projectDao.findById(projectId) ?: return
        require(project.status == ProjectStatus.PLANNING || project.status == ProjectStatus.ACTIVE) {
            "项目已完成或归档，无法删除任务。"
        }
        val resolvedTaskDao = requireNotNull(taskDao) { "Project task storage is unavailable" }
        val resolvedDayDao = requireNotNull(dayDao) { "Project task storage is unavailable" }
        val task = resolvedTaskDao.findById(taskId) ?: return
        require(task.projectOwnerId == projectId && task.zone == TaskZone.DRAFT) {
            "只有未启动的项目草稿任务可以删除。"
        }
        val day = resolvedDayDao.findById(task.dayOwnerId) ?: error("Task day not found")
        require(day.status == DayStatus.EMPTY || day.status == DayStatus.DRAFT) {
            "任务所在日期已锁定。"
        }
        resolvedTaskDao.delete(task)
        val remainingDraft = resolvedDayDao.findWithTasks(task.dayOwnerId)?.tasks
            ?.filter { it.zone == TaskZone.DRAFT }
            ?.sortedBy { it.order }
            .orEmpty()
        remainingDraft.forEachIndexed { index, remaining ->
            resolvedTaskDao.upsert(remaining.copy(order = index + 1))
        }
        if (remainingDraft.isEmpty() && day.status == DayStatus.DRAFT) {
            resolvedDayDao.upsert(day.copy(status = DayStatus.EMPTY))
        }
    }

    suspend fun projectDetail(
        projectId: UUID,
        referenceDate: LocalDate = timeProvider.today
    ): ProjectDetailUi? {
        val project = projectDao.findById(projectId) ?: return null
        val resolvedTaskDao = taskDao ?: return null
        val resolvedDayDao = dayDao ?: return null
        val daysById = resolvedDayDao.allDays().associateBy { it.dayId }
        val projectTasks = resolvedTaskDao.allTasks().filter { it.projectOwnerId == projectId }
        val sortedPending = projectTasks
            .filter { it.zone != TaskZone.COMPLETE }
            .sortedWith(
                compareBy<TaskEntity> { daysById[it.dayOwnerId]?.date?.toInstant()?.atZone(zoneId)?.toLocalDate() ?: LocalDate.MAX }
                    .thenBy { it.order }
                    .thenBy { it.id.toString() }
            )
        val nextTask = sortedPending.firstOrNull { task ->
            val date = daysById[task.dayOwnerId]?.date?.toInstant()?.atZone(zoneId)?.toLocalDate()
            date != null && !date.isBefore(referenceDate)
        } ?: sortedPending.firstOrNull()
        val completedCount = projectTasks.count { it.zone == TaskZone.COMPLETE }
        val sections = projectTasks
            .groupBy { task ->
                daysById[task.dayOwnerId]?.date?.toInstant()?.atZone(zoneId)?.toLocalDate() ?: referenceDate
            }
            .map { (date, tasks) ->
                ProjectDetailSectionUi(
                    date = date,
                    tasks = tasks.sortedWith(compareBy<TaskEntity> { it.order }.thenBy { it.id.toString() }).map { it.toUi() },
                    isExpandedByDefault = !date.isBefore(referenceDate)
                )
            }
            .sortedBy { it.date }
        return ProjectDetailUi(
            project = project.toUi(zoneId),
            progress = if (projectTasks.isEmpty()) 0.0 else completedCount.toDouble() / projectTasks.size,
            totalCount = projectTasks.size,
            completedCount = completedCount,
            remainingCount = projectTasks.size - completedCount,
            expiredCount = projectTasks.count { task ->
                val date = daysById[task.dayOwnerId]?.date?.toInstant()?.atZone(zoneId)?.toLocalDate()
                date != null && date.isBefore(referenceDate) && task.zone != TaskZone.COMPLETE
            },
            nextTaskTitle = nextTask?.title,
            nextTaskDate = nextTask?.let { daysById[it.dayOwnerId]?.date?.toInstant()?.atZone(zoneId)?.toLocalDate() },
            sections = sections
        )
    }

    suspend fun deleteProject(id: UUID, includeTasks: Boolean = false) = inTransaction {
        deleteProjectInternal(id, includeTasks)
    }

    private suspend fun deleteProjectInternal(id: UUID, includeTasks: Boolean) {
        val project = projectDao.findById(id) ?: return
        val resolvedTaskDao = taskDao
        val resolvedDayDao = dayDao
        val projectTasks = resolvedTaskDao?.allTasks()?.filter { it.projectOwnerId == id }.orEmpty()
        if (includeTasks) {
            require(resolvedTaskDao != null && resolvedDayDao != null) { "Project task storage is unavailable" }
            val editable = projectTasks.all { task ->
                val dayStatus = resolvedDayDao.findById(task.dayOwnerId)?.status
                task.zone == TaskZone.DRAFT && (dayStatus == DayStatus.EMPTY || dayStatus == DayStatus.DRAFT)
            }
            require(editable) { "项目包含已启动或已完成任务，请仅删除项目并保留任务记录。" }
            val affectedDayIds = projectTasks.mapTo(linkedSetOf()) { it.dayOwnerId }
            projectTasks.forEach { resolvedTaskDao.delete(it) }
            affectedDayIds.forEach { dayId ->
                val day = resolvedDayDao.findById(dayId) ?: return@forEach
                val remaining = resolvedDayDao.findWithTasks(dayId)?.tasks
                    ?.filter { it.zone == TaskZone.DRAFT }
                    ?.sortedBy { it.order }
                    .orEmpty()
                remaining.forEachIndexed { index, task -> resolvedTaskDao.upsert(task.copy(order = index + 1)) }
                if (remaining.isEmpty() && day.status == DayStatus.DRAFT) {
                    resolvedDayDao.upsert(day.copy(status = DayStatus.EMPTY))
                }
            }
        } else if (resolvedTaskDao != null) {
            projectTasks.forEach { resolvedTaskDao.upsert(it.copy(projectOwnerId = null)) }
        }
        projectDao.delete(project)
    }

    private suspend fun <T> inTransaction(block: suspend () -> T): T =
        database?.withTransaction { block() } ?: block()

    private suspend fun ensureWeekAndDays(date: LocalDate) {
        val resolvedWeekDao = requireNotNull(weekDao) { "Project task storage is unavailable" }
        val resolvedDayDao = requireNotNull(dayDao) { "Project task storage is unavailable" }
        val weekId = weekCalculator.weekId(date)
        val (start, end) = weekCalculator.weekRange(date)
        val week = resolvedWeekDao.findById(weekId) ?: WeekEntity(
            weekId = weekId,
            startDate = start.asDate(zoneId),
            endDate = end.asDate(zoneId),
            status = if (weekId == timeProvider.currentWeekId) WeekStatus.PRESENT else WeekStatus.PENDING
        ).also { resolvedWeekDao.upsert(it) }
        val existing = resolvedDayDao.listByWeek(week.weekId).mapTo(hashSetOf()) { it.dayId }
        repeat(7) { offset ->
            val dayDate = start.plusDays(offset.toLong())
            if (dayDate.toString() !in existing) {
                resolvedDayDao.upsert(
                    DayEntity(
                        dayId = dayDate.toString(),
                        date = dayDate.asDate(zoneId),
                        dayOfWeek = dayDate.dayOfWeek.name.take(3),
                        status = DayStatus.EMPTY,
                        weekOwnerId = week.weekId
                    )
                )
            }
        }
    }
}

private fun ProjectEntity.toUi(zoneId: ZoneId) = ProjectUi(
    id = projectId,
    name = name,
    description = description,
    color = color,
    icon = icon,
    status = status,
    startDate = startDate.toInstant().atZone(zoneId).toLocalDate(),
    endDate = endDate.toInstant().atZone(zoneId).toLocalDate(),
    createdAt = createdAt.toInstant().atZone(zoneId).toLocalDateTime(),
    tileSizeRaw = tileSizeRaw,
    tileOrder = tileOrder
)

private fun LocalDate.asDate(zoneId: ZoneId): Date = Date.from(atStartOfDay(zoneId).toInstant())
