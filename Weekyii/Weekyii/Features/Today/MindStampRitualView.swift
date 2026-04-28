import SwiftUI

struct MindStampRitualView: View {
    let stamp: MindStampItem
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var showContent = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(appeared ? 0.6 : 0)
                .ignoresSafeArea()
                .onTapGesture { }

            // Card
            VStack(spacing: WeekSpacing.xl) {
                // Seal icon
                Image(systemName: "seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.orangeGradient)
                    .scaleEffect(showContent ? 1 : 0.5)
                    .opacity(showContent ? 1 : 0)

                Text(String(localized: "mindstamp.ritual.title"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .opacity(showContent ? 1 : 0)

                // Stamp content
                VStack(spacing: WeekSpacing.md) {
                    if !stamp.text.isEmpty {
                        Text(stamp.text)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, WeekSpacing.md)
                    }

                    if let blob = stamp.imageBlob, let uiImage = UIImage(data: blob) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.medium))
                    }
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

                // Dismiss button
                Button {
                    withAnimation(.easeOut(duration: 0.3)) {
                        appeared = false
                        showContent = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onDismiss()
                    }
                } label: {
                    Text(String(localized: "mindstamp.ritual.dismiss"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WeekSpacing.md)
                        .background(Color.weekyiiGradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                .opacity(showContent ? 1 : 0)
            }
            .padding(WeekSpacing.xl)
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: WeekRadius.xlarge, style: .continuous))
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
            .padding(.horizontal, WeekSpacing.xl)
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    showContent = true
                }
            }
        }
    }
}
