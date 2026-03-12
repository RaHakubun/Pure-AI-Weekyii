import SwiftUI
import SwiftData
import Combine

class TodayViewState: ObservableObject {
    // 视图模型
    @Published var viewModel: TodayViewModel?
    
    // 任务详情
    @Published var selectedTaskForDetail: TaskItem?
    
    // 草稿任务编辑器
    @Published var draftTaskEditorMode: DraftTaskEditorMode?
    
    // 错误消息
    @Published var errorMessage: String?
    
    // 开始流程
    @Published var startFlowCoordinator = TodayStartFlowCoordinator()
    @Published var startFlowStamp: MindStampItem?
    
    // 截止时间
    @Published var pendingTodayKillTimeHour: Int?
    @Published var pendingTodayKillTimeMinute: Int?
    @Published var showingTodayKillTimeConfirm = false
    @Published var todayKillTimeConfirmMode: TodayKillTimeConfirmMode = .normal
    
    // 切换器
    @Published var selectedSection: TodaySection = .today
    
    // 任务后移
    @Published var taskForPostpone: TaskItem?
    @Published fileprivate var pendingPostponeRequest: PendingPostponeRequest?
    @Published var pendingPostponePreview: TodayViewModel.PostponePreview?
    @Published var showingPostponeConfirm = false
    @Published var showingPostponeWeekCreationConfirm = false
    
    // 无参数初始化
    init() {}
    
    // 初始化
    init(modelContext: ModelContext, appState: AppState, userSettings: UserSettings) {
        let model = TodayViewModel(
            modelContext: modelContext,
            timeProvider: TimeProvider(),
            notificationService: NotificationService.shared,
            appState: appState,
            userSettings: userSettings
        )
        viewModel = model
        model.refresh()
        model.seedDraftTasksForUITestsIfNeeded()
    }
    
    // 更新依赖项
    func updateDependencies(modelContext: ModelContext, appState: AppState, userSettings: UserSettings) {
        let model = TodayViewModel(
            modelContext: modelContext,
            timeProvider: TimeProvider(),
            notificationService: NotificationService.shared,
            appState: appState,
            userSettings: userSettings
        )
        viewModel = model
        model.refresh()
        model.seedDraftTasksForUITestsIfNeeded()
    }
    
    // 刷新数据
    func refresh() {
        viewModel?.refresh()
    }
    
    // 截止时间变更确认
    func confirmKillTimeChange() {
        guard let viewModel, let hour = pendingTodayKillTimeHour, let minute = pendingTodayKillTimeMinute else { return }
        do {
            let impact = try viewModel.evaluateKillTimeChangeImpact(hour: hour, minute: minute)
            switch impact {
            case .normal:
                todayKillTimeConfirmMode = .normal
            case .immediateExpire(let expiredCount):
                todayKillTimeConfirmMode = .immediateExpire(expiredCount: expiredCount)
            }
            showingTodayKillTimeConfirm = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // 应用截止时间变更
    func applyPendingTodayKillTime() {
        guard let viewModel, let hour = pendingTodayKillTimeHour, let minute = pendingTodayKillTimeMinute else { return }
        do {
            switch todayKillTimeConfirmMode {
            case .normal:
                try viewModel.changeKillTime(hour: hour, minute: minute, allowImmediateExpire: false)
            case .immediateExpire:
                try viewModel.changeKillTime(hour: hour, minute: minute, allowImmediateExpire: true)
            }
            pendingTodayKillTimeHour = nil
            pendingTodayKillTimeMinute = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // 任务后移相关方法
    func stagePostponeRequest(for task: TaskItem, targetDate: Date) {
        taskForPostpone = nil
        pendingPostponeRequest = PendingPostponeRequest(
            taskID: task.id,
            taskTitle: task.title,
            targetDate: targetDate.startOfDay
        )
        showingPostponeConfirm = true
    }
    
    func confirmPostponeRequest() {
        guard let viewModel, let request = pendingPostponeRequest else { return }
        do {
            let preview = try viewModel.previewPostpone(
                taskID: request.taskID,
                taskTitle: request.taskTitle,
                targetDate: request.targetDate
            )
            pendingPostponePreview = preview
            if preview.requiresWeekCreation {
                showingPostponeWeekCreationConfirm = true
            } else {
                _ = try viewModel.commitPostpone(preview, allowWeekCreation: false)
                clearPendingPostponeContext()
            }
        } catch {
            errorMessage = error.localizedDescription
            clearPendingPostponeContext()
        }
    }
    
    func confirmPostponeWithWeekCreation() {
        guard let viewModel, let preview = pendingPostponePreview else { return }
        do {
            _ = try viewModel.commitPostpone(preview, allowWeekCreation: true)
            clearPendingPostponeContext()
        } catch {
            errorMessage = error.localizedDescription
            clearPendingPostponeContext()
        }
    }
    
    func clearPendingPostponeContext() {
        showingPostponeConfirm = false
        showingPostponeWeekCreationConfirm = false
        taskForPostpone = nil
        pendingPostponeRequest = nil
        pendingPostponePreview = nil
    }
    
    // 格式化日期
    func formatPostponeDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // 截止时间确认标题
    var todayKillTimeConfirmTitle: String {
        switch todayKillTimeConfirmMode {
        case .normal:
            return "确认修改截止时间"
        case .immediateExpire:
            return "新时间会导致今日任务立即过期"
        }
    }
    
    // 截止时间确认消息
    var todayKillTimeConfirmMessage: String {
        switch todayKillTimeConfirmMode {
        case .normal:
            return "确认后将更新今日截止时间。"
        case .immediateExpire(let expiredCount):
            return "确认后今日未完成内容将立即过期（\(expiredCount) 项）。"
        }
    }
    
    // 后移确认消息
    var postponeConfirmMessage: String {
        guard let request = pendingPostponeRequest else { return "确认后移该任务？" }
        return "确认将「\(request.taskTitle)」后移到 \(formatPostponeDate(request.targetDate)) 吗？"
    }
    
    // 创建周确认消息
    var postponeCreateWeekConfirmMessage: String {
        guard let preview = pendingPostponePreview else {
            return "目标周尚未创建，确认后会自动创建并完成任务后移。"
        }
        return "将创建 \(preview.targetWeekId) 后把任务移动到 \(formatPostponeDate(preview.targetDate))。是否继续？"
    }
}

// 枚举和结构体

enum TodayStartFlowStep: Equatable {
    case warning
    case ritual
}

struct TodayStartFlowCoordinator {
    var isPresented = false
    var step: TodayStartFlowStep = .warning

    mutating func present() {
        isPresented = true
        step = .warning
    }

    mutating func chooseDirectEnter() {
        step = .ritual
    }

    mutating func cancel() {
        isPresented = false
        step = .warning
    }
}

fileprivate struct PendingPostponeRequest {
    let taskID: UUID
    let taskTitle: String
    let targetDate: Date
}
