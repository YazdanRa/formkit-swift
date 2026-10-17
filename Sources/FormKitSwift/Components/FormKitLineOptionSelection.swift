import SwiftUI

struct FormKitLineOptionSelection: View {
    let style: FormKitStyle
    let isInteractive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(iOS 26, macOS 26, visionOS 26, *), !reduceTransparency {
            RoundedRectangle(cornerRadius: 18)
                .fill(.clear)
                .glassEffect(
                    .regular.tint(style.accent.opacity(0.18)).interactive(isInteractive),
                    in: .rect(cornerRadius: 18)
                )
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(style.fieldBackground)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(style.accent.opacity(0.3), lineWidth: 1)
                }
        }
    }
}
