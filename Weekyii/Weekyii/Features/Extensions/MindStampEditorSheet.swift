import SwiftUI
import PhotosUI

struct MindStampEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: MindStampViewModel
    let editingItem: MindStampItem?

    @State private var text: String
    @State private var imageData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var imagePreviewItem: ImagePreviewItem?

    init(viewModel: MindStampViewModel, editingItem: MindStampItem? = nil) {
        self.viewModel = viewModel
        self.editingItem = editingItem
        _text = State(initialValue: editingItem?.text ?? "")
        _imageData = State(initialValue: editingItem?.imageBlob)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WeekSpacing.lg) {
                    // Text input
                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            Text(String(localized: "mindstamp.editor.text"))
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)

                            TextField(
                                String(localized: "mindstamp.editor.text.placeholder"),
                                text: $text,
                                axis: .vertical
                            )
                            .font(.bodyLarge)
                            .lineLimit(3...8)
                            .padding(WeekSpacing.md)
                            .background(Color.backgroundTertiary)
                            .cornerRadius(WeekRadius.small)
                        }
                    }

                    // Image picker
                    WeekCard {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            HStack {
                                Text(String(localized: "mindstamp.editor.images"))
                                    .font(.bodyMedium)
                                    .foregroundColor(.textSecondary)

                                Spacer()

                                if imageData == nil {
                                    PhotosPicker(
                                        selection: $selectedPhoto,
                                        matching: .images
                                    ) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 14))
                                            Text(String(localized: "mindstamp.editor.add_image"))
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                        .foregroundColor(.weekyiiPrimary)
                                    }
                                }
                            }

                            if let imageData, let uiImage = UIImage(data: imageData) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.small))
                                        .contentShape(RoundedRectangle(cornerRadius: WeekRadius.small))
                                        .onTapGesture {
                                            imagePreviewItem = ImagePreviewItem(image: uiImage)
                                        }

                                    Button {
                                        self.imageData = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.black.opacity(0.5)))
                                    }
                                    .offset(x: -8, y: 8)
                                }
                            }
                        }
                    }
                }
                .weekPadding(WeekSpacing.base)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle(String(localized: editingItem != nil ? "mindstamp.editor.edit_title" : "mindstamp.editor.create_title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.save")) {
                        save()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageData == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let newValue, let data = try? await newValue.loadTransferable(type: Data.self) {
                        imageData = data
                    }
                    selectedPhoto = nil
                }
            }
            .alert(String(localized: "alert.title"), isPresented: Binding(get: {
                errorMessage != nil
            }, set: { newValue in
                if !newValue { errorMessage = nil }
            })) {
                Button(String(localized: "action.ok"), role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .fullScreenCover(item: $imagePreviewItem) { item in
            ImageViewerScreen(image: item.image)
        }
    }

    private func save() {
        if let item = editingItem {
            viewModel.updateStamp(item, text: text, imageBlob: imageData)
        } else {
            viewModel.createStamp(text: text, imageBlob: imageData)
        }

        if viewModel.errorMessage == nil {
            dismiss()
        } else {
            errorMessage = viewModel.errorMessage
        }
    }
}
