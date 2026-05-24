import SwiftUI

// MARK: - Card panel modifier

extension View {
    func cardPanel(backgroundOpacity: Double = 0.07) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            )
    }
}

// MARK: - Category chip

struct CategoryChip: View {
    var title: String
    var icon: String
    var color: Color
    var isSelected: Bool
    var darkBackground: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.bold)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? color.opacity(darkBackground ? 0.22 : 0.18)
                        : (darkBackground ? Color.black.opacity(0.46) : Color.white.opacity(0.08)),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? color : .white.opacity(darkBackground ? 0.82 : 0.76))
                .overlay(
                    Capsule().stroke(
                        isSelected ? color.opacity(0.55) : .white.opacity(0.10),
                        lineWidth: darkBackground ? 1 : 0
                    )
                )
        }
        .buttonStyle(.plain)
    }
}
