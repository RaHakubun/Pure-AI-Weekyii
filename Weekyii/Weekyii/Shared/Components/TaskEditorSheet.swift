import SwiftUI
import PhotosUI
import SwiftData

struct TaskEditorSheet: View {
    let title: String
    @State var taskTitle: String
    @State var taskDescription: String
    @State var taskType: TaskType
    @State var steps: [TaskStep]
    @State var attachments: [TaskAttachment]
    
    // Config for save callback: returns necessary data
    var onSave: (String, String, TaskType, [TaskStep], [TaskAttachment]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    // Step editing state
    @State private var newStepTitle: String = ""
    @FocusState private var isStepInputFocused: Bool
    
    // Photo picker state
    @State private var selectedPhoto: PhotosPickerItem?
    
    init(
        title: String,
        initialTitle: String = "",
        initialDescription: String = "",
        initialType: TaskType = .regular,
        initialSteps: [TaskStep] = [],
        initialAttachments: [TaskAttachment] = [],
        onSave: @escaping (String, String, TaskType, [TaskStep], [TaskAttachment]) -> Void
    ) {
        self.title = title
        _taskTitle = State(initialValue: initialTitle)
        _taskDescription = State(initialValue: initialDescription)
        _taskType = State(initialValue: initialType)
        _steps = State(initialValue: initialSteps)
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
                            
                            TextField(String(localized: "task.description.placeholder"), text: $taskDescription, axis: .vertical)
                                .font(.bodyMedium)
                                .lineLimit(3...6)
                                .padding(WeekSpacing.md)
                                .background(Color.backgroundTertiary)
                                .cornerRadius(WeekRadius.medium)
                            
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
                            if steps.isEmpty {
                                Text(String(localized: "task.steps.empty"))
                                    .font(.bodyMedium)
                                    .foregroundColor(.textSecondary)
                                    .padding(.vertical, WeekSpacing.sm)
                            } else {
                                VStack(spacing: WeekSpacing.sm) {
                                    ForEach(steps.indices, id: \.self) { index in
                                        stepRow(for: index)
                                    }
                                }
                            }
                            
                            Divider()
                                .padding(.vertical, WeekSpacing.xs)
                            
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
                    
                    WeekCard {
                        sectionHeader(
                            titleKey: "task.attachments",
                            icon: "paperclip",
                            accent: .accentOrange
                        )
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: WeekSpacing.sm) {
                                ForEach(attachments, id: \.id) { (attachment: TaskAttachment) in
                                    if let data = attachment.data, let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 84, height: 84)
                                            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium))
                                            .overlay(
                                                Button(action: {
                                                    deleteAttachment(attachment)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.red)
                                                        .background(Circle().fill(.white))
                                                }
                                                .offset(x: 32, y: -32)
                                            )
                                    }
                                }
                                
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    RoundedRectangle(cornerRadius: WeekRadius.medium)
                                        .fill(Color.accentOrangeLight.opacity(0.2))
                                        .frame(width: 84, height: 84)
                                        .overlay(
                                            VStack(spacing: 6) {
                                                Image(systemName: "photo.badge.plus")
                                                    .font(.title2)
                                                    .foregroundColor(.accentOrange)
                                                Text(String(localized: "action.add"))
                                                    .font(.caption)
                                                    .foregroundColor(.accentOrange)
                                            }
                                        )
                                }
                                .onChange(of: selectedPhoto) { _, newItem in
                                    loadPhoto(newItem)
                                }
                            }
                            .padding(.vertical, WeekSpacing.xs)
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
                    Button(String(localized: "action.save")) {
                        onSave(taskTitle, taskDescription, taskType, steps, attachments)
                    }
                    .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) {
                        dismiss()
                    }
                }
            }
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
    
    private func stepRow(for index: Int) -> some View {
        let binding = $steps[index]
        
        return HStack(spacing: WeekSpacing.sm) {
            Button(action: { binding.isCompleted.wrappedValue.toggle() }) {
                Image(systemName: binding.isCompleted.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(binding.isCompleted.wrappedValue ? .accentGreen : .textTertiary)
            }
            .buttonStyle(.plain)
            
            TextField(String(localized: "Step"), text: binding.title)
                .font(.bodyMedium)
            
            Spacer()
            
            HStack(spacing: WeekSpacing.xs) {
                Button(action: {
                    guard index > 0 else { return }
                    steps.swapAt(index, index - 1)
                }) {
                    Image(systemName: "arrow.up")
                }
                .disabled(index == 0)
                
                Button(action: {
                    guard index < steps.count - 1 else { return }
                    steps.swapAt(index, index + 1)
                }) {
                    Image(systemName: "arrow.down")
                }
                .disabled(index == steps.count - 1)
                
                Button(action: { steps.remove(at: index) }) {
                    Image(systemName: "trash")
                }
                .foregroundColor(.accentOrange)
            }
            .font(.caption)
        }
        .padding(WeekSpacing.sm)
        .background(Color.backgroundTertiary)
        .cornerRadius(WeekRadius.medium)
    }
    
    private func addNewStep() {
        guard !newStepTitle.isEmpty else { return }
        let step = TaskStep(title: newStepTitle)
        steps.append(step)
        newStepTitle = ""
        isStepInputFocused = true
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
            case .failure(let error):
                print("Error loading image: \(error)")
            }
        }
    }
    
    private func deleteAttachment(_ attachment: TaskAttachment) {
        if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
            attachments.remove(at: index)
        }
    }
}
