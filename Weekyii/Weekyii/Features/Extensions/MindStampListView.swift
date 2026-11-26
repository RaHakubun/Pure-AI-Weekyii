import SwiftUI

struct MindStampListView: View {
    let viewModel: MindStampViewModel
    @State private var editingItem: MindStampItem?
    @State private var deletingItem: MindStampItem?
    @State private var imagePreviewItem: ImagePreviewItem?
    private let actionButtonSize: CGFloat = 44
    private let actionIconFont: Font = .system(size: 17, weight: .semibold)

    var body: some View {
        Group {
            if viewModel.stamps.isEmpty {
                emptyState
            } else {
                stampList
            }
        }
        .sheet(item: $editingItem, onDismiss: {
            viewModel.refresh()
        }) { item in
            MindStampEditorSheet(viewModel: viewModel, editingItem: item)
        }
        .alert(
            String(localized: "mindstamp.delete.title"),
            isPresented: Binding(get: { deletingItem != nil }, set: { if !$0 { deletingItem = nil } })
        ) {
            Button(String(localized: "mindstamp.delete.confirm"), role: .destructive) {
                if let item = deletingItem {
                    viewModel.deleteStamp(item)
                    deletingItem = nil
                }
            }
            Button(String(localized: "action.cancel"), role: .cancel) {
                deletingItem = nil
            }
        } message: {
            Text(String(localized: "mindstamp.delete.message"))
        }
        .fullScreenCover(item: $imagePreviewItem) { item in
            ImageViewerScreen(image: item.image)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        WeekCard {
            VStack(spacing: WeekSpacing.xl) {
                Image(systemName: "bandage.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.weekyiiGradient)

                VStack(spacing: WeekSpacing.sm) {
                    Text(String(localized: "mindstamp.empty.title"))
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)

                    Text(String(localized: "mindstamp.empty.subtitle"))
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Text("右上角点 + 新建呆胶布")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, WeekSpacing.md)
                    .padding(.vertical, WeekSpacing.xs)
                    .background(Color.backgroundTertiary)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("mindstampEmptyCreateHint")
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
    }

    // MARK: - Stamp List

    private var stampList: some View {
        VStack(spacing: WeekSpacing.md) {
            ForEach(Array(viewModel.stamps.enumerated()), id: \.element.id) { index, stamp in
                stampCard(stamp, index: index)
            }
        }
    }

    private func stampCard(_ stamp: MindStampItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: WeekSpacing.md) {
                HStack(alignment: .top, spacing: WeekSpacing.md) {
                    if let blob = stamp.imageBlob {
                        Button {
                            openImagePreview(blob)
                        } label: {
                            AttachmentThumbnail(data: blob)
                                .frame(width: 72, height: 72)
                                .clipShape(.rect(cornerRadius: WeekRadius.small))
                                .overlay(RoundedRectangle(cornerRadius: WeekRadius.small).stroke(Color.backgroundTertiary, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("预览呆胶布图片")
                        .accessibilityIdentifier("mindstampImagePreviewButton_\(index)")
                    }
                    Button {
                        editingItem = stamp
                    } label: {
                        VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                            if stamp.imageBlob == nil {
                                Image(systemName: "quote.opening")
                                    .font(.headline)
                                    .foregroundStyle(Color.accentPink)
                                    .accessibilityHidden(true)
                            }
                            Text(stamp.text.isEmpty ? "仅图片记录" : stamp.text)
                                .font(.bodyMedium.weight(.medium))
                                .foregroundStyle(stamp.text.isEmpty ? Color.textSecondary : Color.textPrimary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                            Text(stamp.createdAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                                .accessibilityIdentifier("mindstampItemMeta_\(index)")
                            if stamp.imageBlob != nil {
                                Label("含图片", systemImage: "photo")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentPink)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mindstampItemCard_\(index)")
                }
                HStack {
                    Button {
                        editingItem = stamp
                    } label: {
                        Label("编辑", systemImage: "pencil")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mindstampEditButton_\(index)")
                    Spacer()
                    actionButton(
                        systemImage: "trash",
                        foreground: .taskDDL,
                        background: Color.taskDDL.opacity(0.1),
                        accessibilityID: "mindstampDeleteButton_\(index)"
                    ) {
                        deletingItem = stamp
                    }
                }
            }
        .padding(WeekSpacing.lg)
        .extensionAccentSurface(.accentPink, strength: stamp.imageBlob == nil ? 0.65 : 0.30)
    }

    // 看大图时才在后台解码原图
    private func openImagePreview(_ data: Data) {
        Task {
            if let image = await ImageDataDecoder.fullImage(from: data) {
                imagePreviewItem = ImagePreviewItem(image: image)
            }
        }
    }

    private func actionButton(
        systemImage: String,
        foreground: Color,
        background: Color,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(actionIconFont)
                .foregroundColor(foreground)
                .frame(width: actionButtonSize, height: actionButtonSize)
                .background(background)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .buttonStyle(ScaleButtonStyle())
        .accessibilityIdentifier(accessibilityID)
    }

}
