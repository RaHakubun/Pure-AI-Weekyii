import SwiftUI

struct TaskRowView: View {
    enum RenderContext {
        case normalCard
        case reorderList
    }

    let task: TaskItem
    let titleAccessibilityIdentifier: String?
    let showsProjectOrigin: Bool
    let showsHabitOrigin: Bool
    let renderContext: RenderContext
    @Environment(\.taskTypePresentationCatalog) private var taskTypeCatalog
    @Environment(\.themeSkin) private var rowSkin

    private var taskType: TaskTypePresentation {
        taskTypeCatalog.resolve(idRaw: task.taskTypeIdRaw, fallback: task.taskType)
    }

    init(
        task: TaskItem,
        titleAccessibilityIdentifier: String? = nil,
        showsProjectOrigin: Bool = false,
        showsHabitOrigin: Bool = false,
        renderContext: RenderContext = .normalCard
    ) {
        self.task = task
        self.titleAccessibilityIdentifier = titleAccessibilityIdentifier
        self.showsProjectOrigin = showsProjectOrigin
        self.showsHabitOrigin = showsHabitOrigin
        self.renderContext = renderContext
    }

    var body: some View {
        if let row = rowSkin.row {
            // 主题行：不画底框，只在行脚压一条墨线（账本式）。
            rowContent
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .themedSurface(
                    row.surface,
                    tint: row.typeChip && row.rowWashOpacity > 0 ? taskType.color(in: rowSkin) : nil,
                    tintOpacity: row.rowWashOpacity
                )
                .contentShape(Rectangle())
                .compositingGroup()
        } else {
            rowContent
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: WeekRadius.medium)
                        .stroke(
                            borderColor,
                            style: StrokeStyle(lineWidth: 1, lineJoin: .round)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: WeekRadius.medium, style: .continuous))
                .compositingGroup()
        }
    }

    /// The type colour washes the row and the icon sits in a chip (猫猫).
    private var usesTypeChip: Bool { rowSkin.row?.typeChip == true }

    private var rowContent: some View {
        HStack(alignment: usesTypeChip ? .center : .firstTextBaseline, spacing: usesTypeChip ? 10 : WeekSpacing.sm) {
            if usesTypeChip {
                typeChip
            } else {
                // Left Accent Bar.
                RoundedRectangle(cornerRadius: 2)
                    .fill(taskType.color(in: rowSkin))
                    .frame(width: 4, height: 28)
                    .padding(.top, 2)

                typeIcon
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: WeekSpacing.sm) {
                    // Title
                    titleView
                    if showsProjectOrigin, task.project != nil {
                        Spacer(minLength: WeekSpacing.sm)
                        TaskProjectOriginBadge(project: task.project)
                    }
                    if showsHabitOrigin, task.habit != nil {
                        Spacer(minLength: WeekSpacing.sm)
                        TaskHabitOriginBadge(habit: task.habit)
                    }
                }

                // Description
                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            // Steps Indicator
            if !task.steps.isEmpty {
                let completed = task.steps.filter(\.isCompleted).count
                HStack(spacing: 2) {
                    Image(systemName: "checklist")
                    Text("\(completed)/\(task.steps.count)")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }
    
    /// The type icon in a 32 pt rounded chip of the type colour, in place of
    /// the leading bar (猫猫).
    private var typeChip: some View {
        let color = taskType.color(in: rowSkin)
        let row = rowSkin.row
        let size = row?.chipSize ?? 32
        let radius = row?.chipCornerRadius ?? 11
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(color.opacity(row?.chipFillOpacity ?? 0.16))
            if (row?.chipBorderOpacity ?? 0) > 0 {
                shape.strokeBorder(color.opacity(row?.chipBorderOpacity ?? 0), lineWidth: 1)
            }
            if rowSkin.glyphs == .cat,
               let glyph = CatGlyph(builtInType: taskType.baseKind, iconName: taskType.iconName) {
                CatGlyphView(glyph: glyph)
                    .frame(width: 19, height: 19)
            } else if rowSkin.drawsMiddleEarthGlyphs,
                      let glyph = LotrGlyph(builtInType: taskType.baseKind, iconName: taskType.iconName) {
                // 指环王：盖印式方章里压中土纹样。
                LotrGlyphView(glyph: glyph)
                    .frame(width: 17, height: 17)
            } else {
                Image(systemName: taskType.iconName)
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .foregroundColor(color)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Built-in type icons stay on the system symbol for every theme except cat,
    /// which draws its own mark in the same 24 pt slot.
    @ViewBuilder
    private var typeIcon: some View {
        if rowSkin.glyphs == .cat,
           let glyph = CatGlyph(builtInType: taskType.baseKind, iconName: taskType.iconName) {
            CatGlyphView(glyph: glyph)
                .frame(width: 18, height: 18)
                .foregroundColor(taskType.color(in: rowSkin))
                .frame(width: 24)
        } else {
            Image(systemName: taskType.iconName)
                .font(.headline)
                .foregroundColor(taskType.color(in: rowSkin))
                .frame(width: 24)
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if let titleAccessibilityIdentifier {
            Text(task.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .accessibilityIdentifier(titleAccessibilityIdentifier)
        } else {
            Text(task.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
        }
    }

    private var backgroundColor: Color {
        switch renderContext {
        case .normalCard:
            return .backgroundSecondary
        case .reorderList:
            return .backgroundSecondary
        }
    }

    private var borderColor: Color {
        switch renderContext {
        case .normalCard:
            return .backgroundTertiary
        case .reorderList:
            return Color.backgroundTertiary.opacity(0.92)
        }
    }
}

/// Shared chrome of the origin badges. `isOnDarkBackground` marks a badge on the
/// feature panel: classic themes draw it white on the primary gradient, while a
/// personalised skin takes the panel's own ink, which may be dark (brutalist yellow).
private struct TaskOriginBadgeChrome: ViewModifier {
    let isOnDarkBackground: Bool
    @Environment(\.themeSkin) private var skin

    @ViewBuilder
    func body(content: Content) -> some View {
        if isOnDarkBackground, let feature = skin.feature {
            let shape = RoundedRectangle(cornerRadius: min(feature.surface.cornerRadius, 8))
            content
                .foregroundStyle(feature.secondaryInk.color)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(feature.ink.color.opacity(0.10), in: shape)
                .overlay(shape.strokeBorder(feature.secondaryInk.color.opacity(0.5), lineWidth: 1))
        } else {
            content
                .foregroundStyle(isOnDarkBackground ? Color.white.opacity(0.95) : Color.textSecondary)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(isOnDarkBackground ? Color.white.opacity(0.16) : Color.backgroundTertiary, in: Capsule())
        }
    }
}

struct TaskProjectOriginBadge: View {
    let project: ProjectModel?
    var isOnDarkBackground: Bool = false

    var body: some View {
        if let project {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: "folder.fill")
                    .font(.caption2)
                Text(
                    String(
                        format: String(localized: "task.project.origin", defaultValue: "来自 %@"),
                        project.name
                    )
                )
                .lineLimit(1)
            }
            .font(.caption2)
            .modifier(TaskOriginBadgeChrome(isOnDarkBackground: isOnDarkBackground))
            .accessibilityIdentifier("taskProjectOriginBadge")
        }
    }
}

struct TaskHabitOriginBadge: View {
    let habit: HabitModel?
    var isOnDarkBackground: Bool = false

    var body: some View {
        if let habit {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: habit.iconName)
                    .font(.caption2)
                Text(
                    String(
                        format: String(localized: "task.habit.origin", defaultValue: "习惯 · %@"),
                        habit.name
                    )
                )
                .lineLimit(1)
            }
            .font(.caption2)
            .modifier(TaskOriginBadgeChrome(isOnDarkBackground: isOnDarkBackground))
            .accessibilityIdentifier("taskHabitOriginBadge")
        }
    }
}
