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
                Image(systemName: "seal.fill")
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

                Text("右上角点 + 新建思想钢印")
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
            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                // Header: date + actions
                HStack {
                    Text(stamp.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundColor(.textTertiary)

                    Spacer()

                    actionButton(
                        systemImage: "pencil",
                        foreground: .textSecondary,
                        background: Color.backgroundTertiary,
                        accessibilityID: "mindstampEditButton_\(index)"
                    ) {
                        editingItem = stamp
                    }

                    actionButton(
                        systemImage: "trash",
                        foreground: .taskDDL,
                        background: Color.taskDDL.opacity(0.1),
                        accessibilityID: "mindstampDeleteButton_\(index)"
                    ) {
                        deletingItem = stamp
                    }
                }
                .zIndex(2)

                // Text content
                if !stamp.text.isEmpty {
                    HStack(alignment: .top, spacing: 0) {
                        Text(stamp.text)
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    // Swallow taps on the full text band so they do not fall through to the image preview area.
                    .onTapGesture { }
                }

                // Image
                if let blob = stamp.imageBlob, let uiImage = UIImage(data: blob) {
                    imagePreview(uiImage)
                        .onTapGesture {
                            imagePreviewItem = ImagePreviewItem(image: uiImage)
                        }
                        .zIndex(0)
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

    private func imagePreview(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.small))
            .contentShape(RoundedRectangle(cornerRadius: WeekRadius.small))
    }
}
