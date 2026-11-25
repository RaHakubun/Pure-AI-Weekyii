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
    /// Screen-sized copy of `imageData` for the editor; the stored data stays the original.
    @State private var previewImage: UIImage?
    @State private var previewFailed = false
    /// Bumped whenever `imageData` is replaced, so the preview is decoded again.
    @State private var imageGeneration = 0
    @State private var isLoadingPhoto = false
    @State private var isOpeningViewer = false

    private static let imageFrameHeight: CGFloat = 220
    /// Enough pixels for a full-width, 220 pt high frame on a 3x screen.
    private static let previewMaxPixelSize: CGFloat = 1400

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
                            .accessibilityIdentifier("mindstampEditorTextField")
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

                                if imageData == nil && !isLoadingPhoto {
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

                            if imageData != nil || isLoadingPhoto {
                                imageFrame
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
                    .disabled(
                        (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageData == nil)
                            || isLoadingPhoto
                    )
                    .accessibilityIdentifier("mindstampEditorSaveButton")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel")) {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                isLoadingPhoto = true
                Task {
                    // The original photo data is stored as-is; only the preview is scaled.
                    if let data = try? await newValue.loadTransferable(type: Data.self) {
                        replaceImageData(with: data)
                    } else {
                        errorMessage = String(
                            localized: "mindstamp.editor.image_load_failed",
                            defaultValue: "图片载入失败，请重试"
                        )
                    }
                    isLoadingPhoto = false
                    selectedPhoto = nil
                }
            }
            .task(id: imageGeneration) {
                await decodePreview()
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

    // 图片框：完整原图居中，空白处用同一张图的模糊版铺满
    private var imageFrame: some View {
        Color.backgroundTertiary
            .overlay {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 24, opaque: true)
                        .overlay(Color.black.opacity(0.12))
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                } else if previewFailed {
                    imageStatus(
                        systemImage: "photo",
                        text: String(localized: "mindstamp.editor.image_unreadable", defaultValue: "无法显示这张图片")
                    )
                } else {
                    VStack(spacing: WeekSpacing.sm) {
                        ProgressView()
                        Text(String(localized: "mindstamp.editor.image_loading", defaultValue: "正在载入图片"))
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.imageFrameHeight)
            .clipShape(.rect(cornerRadius: WeekRadius.small))
            .contentShape(.rect(cornerRadius: WeekRadius.small))
            .onTapGesture {
                openViewer()
            }
            .overlay(alignment: .topTrailing) {
                if imageData != nil && !isLoadingPhoto {
                    removeImageButton
                }
            }
    }

    private var removeImageButton: some View {
        Button {
            replaceImageData(with: nil)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .environment(\.colorScheme, .dark)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "mindstamp.editor.remove_image", defaultValue: "移除图片"))
        .padding(2)
    }

    private func imageStatus(systemImage: String, text: String) -> some View {
        VStack(spacing: WeekSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(Color.textTertiary)
    }

    private func replaceImageData(with data: Data?) {
        imageData = data
        previewImage = nil
        previewFailed = false
        imageGeneration += 1
    }

    private func decodePreview() async {
        guard let data = imageData else {
            previewImage = nil
            previewFailed = false
            return
        }
        let decoded = await ImageDataDecoder.thumbnail(from: data, maxPixelSize: Self.previewMaxPixelSize)
        guard !Task.isCancelled else { return }
        previewImage = decoded
        previewFailed = decoded == nil
    }

    // 看大图时才解码原图
    private func openViewer() {
        guard let data = imageData, !isOpeningViewer else { return }
        isOpeningViewer = true
        Task {
            let image = await ImageDataDecoder.fullImage(from: data)
            isOpeningViewer = false
            if let image {
                imagePreviewItem = ImagePreviewItem(image: image)
            }
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
