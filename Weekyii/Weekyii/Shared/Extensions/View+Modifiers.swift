import SwiftUI

extension View {
    func weekyiiCard() -> some View {
        self
            .padding(12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
