import Foundation
import SwiftData

struct HabitSyncOutcome: Equatable {
    var createdCount: Int = 0
    var skippedExistingCount: Int = 0
    var blockedCount: Int = 0
    var failedCount: Int = 0
    var missedRecordCount: Int = 0
    var saveFailed: Bool = false
    /// 需要写库（含水位线推进）；不等于需要刷新 UI。
    fileprivate var needsSave: Bool = false

    /// 本次 sync 是否产生了新任务或补记（供测试与调用方判断；视图刷新由 stateTransitionRevision 承担）。
    var didChange: Bool { createdCount > 0 || missedRecordCount > 0 }
}

enum HabitAssignOutcome: Equatable {
    case created
    case alreadyExists
    case dayLocked
    case pastKillTime
    case notScheduledToday
    case failed(String)
}

/// 习惯记录暂存：在调用方事务内修改，不 save；保证与任务完成同一次落盘。
@MainActor
enum HabitRecordService {
    static func stageCompletion(for task: TaskItem, at date: Date) {
        guard let habit = task.habit,
              let dayId = task.day?.dayId,
              !dayId.isEmpty else { return }

        if let existing = habit.records.first(where: { $0.dayId == dayId }) {
            existing.status = .completed
            existing.completedAt = date
        } else {
            let record = HabitDayRecord(dayId: dayId, createdAt: date)
            record.status = .completed
            record.completedAt = date
            record.habit = habit
            habit.records.append(record)
        }
    }
}

/// 仅今日物化 + 过期记录补记。语义见计划 §2.1 / §2.2 / §2.3。
@MainActor
struct HabitTaskMaterializer {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 统一入口：补记过期 pending → 物化今日。单次 save。
    @discardableResult
    func sync(today: Date = Date(), now: Date = Date()) -> HabitSyncOutcome {
        var outcome = HabitSyncOutcome()
        let todayStart = today.startOfDay
        let todayKey = todayStart.dayId

        let descriptor = FetchDescriptor<HabitModel>(sortBy: [SortDescriptor(\.sortOrder)])
        let habits = (try? modelContext.fetch(descriptor)) ?? []

        outcome.missedRecordCount = sweepPendingRecords(habits: habits, todayKey: todayKey)
        if outcome.missedRecordCount > 0 { outcome.needsSave = true }

        for habit in habits where habit.isActive {
            materializeToday(habit: habit, todayStart: todayStart, todayKey: todayKey, now: now, outcome: &outcome)
        }

        if outcome.needsSave {
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                outcome.saveFailed = true
                outcome.createdCount = 0
                outcome.missedRecordCount = 0
            }
        }
        return outcome
    }

    /// 手动加入今日（绕过水位线；成功后水位线推进到今天）。语义见 §2.9。
    @discardableResult
    func assignToday(habit: HabitModel, today: Date = Date(), now: Date = Date()) -> HabitAssignOutcome {
        guard habit.isActive else { return .failed(HabitError.saveFailed.localizedDescription) }
        let todayStart = today.startOfDay
        let todayKey = todayStart.dayId
        guard habit.isScheduled(on: todayStart) else { return .notScheduledToday }

        do {
            let day = try WeekDataStore(modelContext: modelContext)
                .resolveDay(on: todayStart, weekStatus: .present).day

            if day.tasks.contains(where: { $0.habit?.id == habit.id }) {
                return .alreadyExists
            }
            guard day.status == .empty || day.status == .draft else { return .dayLocked }
            guard now < killDate(for: day) else { return .pastKillTime }

            try createHabitTask(habit: habit, in: day, todayKey: todayKey, now: now)
            habit.generatedThroughDayId = max(habit.generatedThroughDayId, todayKey)
            try modelContext.save()
            return .created
        } catch {
            modelContext.rollback()
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - 内部

    private func sweepPendingRecords(habits: [HabitModel], todayKey: String) -> Int {
        var missed = 0
        for habit in habits {
            for record in habit.records
            where record.statusRaw == HabitDayRecordStatus.pending.rawValue && record.dayId < todayKey {
                record.statusRaw = HabitDayRecordStatus.missed.rawValue
                missed += 1
            }
        }
        return missed
    }

    private func materializeToday(
        habit: HabitModel,
        todayStart: Date,
        todayKey: String,
        now: Date,
        outcome: inout HabitSyncOutcome
    ) {
        guard habit.hasSchedule else { return }
        guard habit.startDayId <= todayKey else { return }               // 尚未生效：不写水位线
        guard habit.generatedThroughDayId < todayKey else { return }     // 今日已处理（删除不复活）

        guard habit.isScheduled(on: todayStart) else {
            advanceWatermark(habit, to: todayKey, outcome: &outcome)
            return
        }

        do {
            let day = try WeekDataStore(modelContext: modelContext)
                .resolveDay(on: todayStart, weekStatus: .present).day

            if day.tasks.contains(where: { $0.habit?.id == habit.id }) {
                outcome.skippedExistingCount += 1
                advanceWatermark(habit, to: todayKey, outcome: &outcome)
                return
            }
            guard day.status == .empty || day.status == .draft, now < killDate(for: day) else {
                outcome.blockedCount += 1
                advanceWatermark(habit, to: todayKey, outcome: &outcome)
                return
            }

            try createHabitTask(habit: habit, in: day, todayKey: todayKey, now: now)
            advanceWatermark(habit, to: todayKey, outcome: &outcome)
            outcome.createdCount += 1
        } catch {
            outcome.failedCount += 1      // 水位线不动，下次重试
        }
    }

    private func createHabitTask(habit: HabitModel, in day: DayModel, todayKey: String, now: Date) throws {
        let payload = TaskDraftPayload(
            title: habit.name,
            description: "",
            type: .regular,
            taskTypeIdRaw: nil,
            steps: [],
            attachments: []
        )
        let task = try TaskMutationService(modelContext: modelContext)
            .createTask(in: day, payload: payload, zone: .draft, project: nil)
        task.habit = habit

        let record = HabitDayRecord(dayId: todayKey, createdAt: now)
        record.habit = habit
        habit.records.append(record)
    }

    private func advanceWatermark(_ habit: HabitModel, to todayKey: String, outcome: inout HabitSyncOutcome) {
        guard habit.generatedThroughDayId < todayKey else { return }
        habit.generatedThroughDayId = todayKey
        outcome.needsSave = true
    }

    private func killDate(for day: DayModel) -> Date {
        let calendar = Calendar(identifier: .iso8601)
        var components = calendar.dateComponents([.year, .month, .day], from: day.date)
        components.hour = day.killTimeHour
        components.minute = day.killTimeMinute
        components.second = 0
        return calendar.date(from: components) ?? .distantFuture
    }
}
