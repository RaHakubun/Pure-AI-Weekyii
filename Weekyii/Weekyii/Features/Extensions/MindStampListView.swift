import SwiftUI

struct MindStampListView: View {
    let viewModel: MindStampViewModel
    @State private var editingItem: MindStampItem?
    @State private var deletingItem: MindStampItem?

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
            }
            .frame(maxWidth: .infinity)
            .weekPaddingVertical(WeekSpacing.xl)
        }
    }

    // MARK: - Stamp List

    private var stampList: some View {
        VStack(spacing: WeekSpacing.md) {
            ForEach(viewModel.stamps) { stamp in
                stampCard(stamp)
            }
        }
    }

    private func stampCard(_ stamp: MindStampItem) -> some View {
        WeekCard {
            VStack(alignment: .leading, spacing: WeekSpacing.sm) {
                // Header: date + actions
                HStack {
                    Text(stamp.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundColor(.textTertiary)

                    Spacer()

                    Button {
                        editingItem = stamp
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Color.backgroundTertiary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        deletingItem = stamp
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.taskDDL)
                            .frame(width: 28, height: 28)
                            .background(Color.taskDDL.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Text content
                if !stamp.text.isEmpty {
                    Text(stamp.text)
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)
                }

                // Image
                if let blob = stamp.imageBlob, let uiImage = UIImage(data: blob) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: WeekRadius.small))
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
