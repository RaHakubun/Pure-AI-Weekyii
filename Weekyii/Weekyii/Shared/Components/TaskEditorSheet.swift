import SwiftUI
import PhotosUI
import SwiftData

struct TaskEditorSheet: View {
    let title: String
    let isReadOnly: Bool
    @State var taskTitle: String
    @State var taskDescription: String
    @State var taskType: TaskType
    @State private var stepDrafts: [TaskStepDraft]
    @State var attachments: [TaskAttachment]
    
    // Config for save callback: returns necessary data
    var onSave: (String, String, TaskType, [TaskStep], [TaskAttachment]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    // Step editing state
    @State private var newStepTitle: String = ""
    @FocusState private var isStepInputFocused: Bool
    
    // Photo picker state
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingStepFullText = false
    @State private var selectedStepFullText = ""
    
    init(
        title: String,
        isReadOnly: Bool = false,
        initialTitle: String = "",
        initialDescription: String = "",
        initialType: TaskType = .regular,
        initialSteps: [TaskStep] = [],
        initialAttachments: [TaskAttachment] = [],
        onSave: @escaping (String, String, TaskType, [TaskStep], [TaskAttachment]) -> Void
    ) {
        self.title = title
        self.isReadOnly = isReadOnly
        _taskTitle = State(initialValue: initialTitle)
        _taskDescription = State(initialValue: initialDescription)
        _taskType = State(initialValue: initialType)
        _stepDrafts = State(initialValue: initialSteps
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }
            .enumerated()
            .map { index, step in
                TaskStepDraft(
                    id: UUID(),
                    title: step.title,
                    isCompleted: step.isCompleted,
                    sortOrder: index
                )
            }
        )
        _attachments = State(initialValue: initialAttachments)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                    WeekCard(accentColor: taskType.color) {
                        sectionHeader(
                            titleKey: "task.basic_info",
                            icon: "text.badge.plus",
                            accent: taskType.color
                        )
                        
                        VStack(alignment: .leading, spacing: WeekSpacing.md) {
                            TextField(String(localized: "task.title.placeholder"), text: $taskTitle)
                                .font(.titleSmall)
                                .padding(WeekSpacing.md)
                                .background(Color.backgroundTertiary)
                                .cornerRadius(WeekRadius.medium)
                                .disabled(isReadOnly)
                                .accessibilityIdentifier("taskEditorTitleField")
                            
                            TextField(String(localized: "task.description.placeholder"), text: $taskDescription, axis: .vertical)
                                .font(.bodyMedium)
                                .lineLimit(3...6)
                                .padding(WeekSpacing.md)
                                .background(Color.backgroundTertiary)
                                .cornerRadius(WeekRadius.medium)
                                .disabled(isReadOnly)
                            
                            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                                Text(String(localized: "task.type"))
                                    .font(.captionBold)
                                    .foregroundColor(.textSecondary)
                                
                                HStack(spacing: WeekSpacing.sm) {
                                    ForEach(TaskType.allCases, id: \.self) { type in
                                        taskTypeChip(for: type)
                                    }
                                }
                            }
                        }
                    }
                    
                    WeekCard {
                        sectionHeader(
                            titleKey: "task.steps",
                            icon: "list.bullet",
                            accent: .accentGreen
                        )
                        
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            if !stepDrafts.isEmpty {
                                VStack(spacing: WeekSpacing.sm) {
                                    ForEach(stepDrafts) { draft in
                                        stepRow(for: draft.id)
                                    }
                                }
                            }
                            
                            Divider()
                                .padding(.vertical, WeekSpacing.xs)
                            if !isReadOnly {
                                HStack(spacing: WeekSpacing.sm) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.accentGreen)
                                    TextField(String(localized: "task.step.add"), text: $newStepTitle)
                                        .focused($isStepInputFocused)
                                        .onSubmit { addNewStep() }
                                    
                                    if !newStepTitle.isEmpty {
                                        Button(String(localized: "action.add")) {
                                            addNewStep()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.accentGreen)
                                    }
                                }
                            }
                        }
                    }
                    
                    WeekCard {
                        sectionHeader(
                            titleKey: "task.attachments",
                            icon: "paperclip",
                            accent: .accentOrange
                        )
                        
                        let columns = [
                            GridItem(.adaptive(minimum: 92), spacing: WeekSpacing.sm)
                        ]

                        LazyVGrid(columns: columns, spacing: WeekSpacing.sm) {
                            ForEach(attachments, id: \.id) { (attachment: TaskAttachment) in
                                attachmentTile(attachment)
                            }
                            if !isReadOnly {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    RoundedRectangle(cornerRadius: WeekRadius.medium)
                                        .fill(Color.accentOrangeLight.opacity(0.22))
                                        .frame(height: 96)
                                        .overlay(
                                            VStack(spacing: 6) {
                                                Image(systemName: "plus.square.fill")
                                                    .font(.title2)
                                                    .foregroundColor(.accentOrange)
                                                Text(String(localized: "action.add"))
                                                    .font(.captionBold)
                                                    .foregroundColor(.accentOrange)
                                            }
                                        )
                                }
                                .onChange(of: selectedPhoto) { _, newItem in
                                    loadPhoto(newItem)
                                }
                            }
                        }
                    }
                }
                .weekPadding(WeekSpacing.base)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isReadOnly {
                        Button(String(localized: "action.ok")) {
                            dismiss()
                        }
                    } else {
                        Button(String(localized: "action.save")) {
                            normalizeStepOrder()
                            let normalizedSteps = stepDrafts
                                .sorted { $0.sortOrder < $1.sortOrder }
                                .map { draft in
                                    TaskStep(
                                        title: draft.title,
                                        isCompleted: draft.isCompleted,
                                        sortOrder: draft.sortOrder
                                    )
                                }
                            onSave(taskTitle, taskDescription, taskType, normalizedSteps, attachments)
                        }
                        .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("taskEditorSaveButton")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("taskEditorCancelButton")
                }
            }
        }
        .alert("步骤全文", isPresented: $showingStepFullText) {
            Button(String(localized: "action.ok"), role: .cancel) { }
        } message: {
            Text(selectedStepFullText)
        }
    }

    private func sectionHeader(titleKey: LocalizedStringKey, icon: String, accent: Color) -> some View {
        HStack(spacing: WeekSpacing.sm) {
            Image(systemName: icon)
                .foregroundColor(accent)
            Text(titleKey)
                .font(.titleSmall)
                .foregroundColor(.textPrimary)
            Spacer()
        }
    }
    
    private func taskTypeChip(for type: TaskType) -> some View {
        let isSelected = taskType == type
        
        return Button(action: { taskType = type }) {
            HStack(spacing: WeekSpacing.xs) {
                Image(systemName: type.iconName)
                Text(type.displayName)
                    .font(.captionBold)
            }
            .foregroundColor(isSelected ? type.color : .textSecondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? type.color.opacity(0.15) : Color.backgroundTertiary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? type.color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    @ViewBuilder
    private func stepRow(for stepID: UUID) -> some View {
        if let index = stepDrafts.firstIndex(where: { $0.id == stepID }) {
            let binding = $stepDrafts[index]

            HStack(spacing: WeekSpacing.sm) {
                if isReadOnly {
                    Image(systemName: binding.isCompleted.wrappedValue ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(binding.isCompleted.wrappedValue ? .accentGreen : .textTertiary)
                } else {
                    Button(action: { binding.isCompleted.wrappedValue.toggle() }) {
                        Image(systemName: binding.isCompleted.wrappedValue ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(binding.isCompleted.wrappedValue ? .accentGreen : .textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                if isReadOnly {
                    Text(binding.title.wrappedValue)
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedStepFullText = binding.title.wrappedValue
                            showingStepFullText = true
                        }
                } else {
                    TextField(String(localized: "Step"), text: binding.title, axis: .vertical)
                        .font(.bodyMedium)
                        .lineLimit(1...8)
                        .disabled(isReadOnly)
                }

                Spacer()

                if !isReadOnly {
                    HStack(spacing: WeekSpacing.xs) {
                        Button(action: {
                            guard index > 0 else { return }
                            stepDrafts.swapAt(index, index - 1)
                            normalizeStepOrder()
                        }) {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(index == 0)

                        Button(action: {
                            guard index < stepDrafts.count - 1 else { return }
                            stepDrafts.swapAt(index, index + 1)
                            normalizeStepOrder()
                        }) {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(index == stepDrafts.count - 1)

                        Button(action: {
                            stepDrafts.remove(at: index)
                            normalizeStepOrder()
                        }) {
                            Image(systemName: "trash")
                        }
                        .foregroundColor(.accentOrange)
                    }
                    .font(.caption)
                }
            }
            .padding(WeekSpacing.sm)
            .background(Color.backgroundTertiary)
            .cornerRadius(WeekRadius.medium)
        }
    }
    
    private func addNewStep() {
        guard !newStepTitle.isEmpty else { return }
        let step = TaskStepDraft(
            id: UUID(),
            title: newStepTitle,
            isCompleted: false,
            sortOrder: stepDrafts.count
        )
        stepDrafts.append(step)
        normalizeStepOrder()
        newStepTitle = ""
        isStepInputFocused = true
    }

    private func normalizeStepOrder() {
        for index in stepDrafts.indices {
            stepDrafts[index].sortOrder = index
        }
    }
    
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        item.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data):
                if let data = data {
                    let attachment = TaskAttachment(data: data, fileName: "image.jpg", fileType: "image/jpeg")
                    DispatchQueue.main.async {
                        self.attachments.append(attachment)
                    }
                }
            case .failure:
                break
            }
        }
    }
    
    private func deleteAttachment(_ attachment: TaskAttachment) {
        if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
            attachments.remove(at: index)
        }
    }

    @ViewBuilder
    private func attachmentTile(_ attachment: TaskAttachment) -> some View {
        let fileLabel = attachment.fileName.isEmpty ? "Attachment" : attachment.fileName

        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: WeekRadius.medium)
                .fill(Color.accentOrangeLight.opacity(0.16))
                .frame(height: 96)
                .overlay(alignment: .bottomLeading) {
                    Text(fileLabel)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(2)
                        .foregroundColor(.textPrimary)
                        .padding(8)
                }

            if let data = attachment.data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium))
                    .overlay(alignment: .bottomLeading) {
                        Rectangle()
                            .fill(.black.opacity(0.32))
                            .frame(height: 26)
                            .overlay(alignment: .leading) {
                                Text(fileLabel)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                            }
                    }
            }

            if !isReadOnly {
                Button(action: {
                    deleteAttachment(attachment)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .offset(x: 6, y: -6)
            }
        }
    }
}

private struct TaskStepDraft: Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
}
