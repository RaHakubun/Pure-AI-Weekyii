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
        WeekCard {
            HStack(alignment: .center, spacing: WeekSpacing.md) {
                if let blob = stamp.imageBlob, let uiImage = UIImage(data: blob) {
                    Button {
                        imagePreviewItem = ImagePreviewItem(image: uiImage)
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(.rect(cornerRadius: WeekRadius.small))
                            .overlay {
                                RoundedRectangle(cornerRadius: WeekRadius.small)
                                    .stroke(Color.backgroundTertiary, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("预览呆胶布图片")
                    .accessibilityIdentifier("mindstampImagePreviewButton_\(index)")
                } else {
                    Image(systemName: "note.text")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.accentPink)
                        .frame(width: 56, height: 56)
                        .background(Color.accentPink.opacity(0.1), in: RoundedRectangle(cornerRadius: WeekRadius.small))
                }

                Button {
                    editingItem = stamp
                } label: {
                    VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                        Text(stamp.text.isEmpty ? "仅图片记录" : stamp.text)
                            .font(.bodyMedium)
                            .foregroundStyle(stamp.text.isEmpty ? Color.textSecondary : Color.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: WeekSpacing.sm) {
                            Text(stamp.createdAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                                .accessibilityIdentifier("mindstampItemMeta_\(index)")

                            if stamp.imageBlob != nil {
                                Label("含图片", systemImage: "photo")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentPink)
                                    .labelStyle(.titleAndIcon)
                            }

                            Spacer(minLength: 0)

                            Label("编辑", systemImage: "pencil")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.weekyiiPrimary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mindstampItemCard_\(index)")

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
