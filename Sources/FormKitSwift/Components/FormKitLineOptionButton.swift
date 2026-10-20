import SwiftUI

struct FormKitLineOptionButton: View {
    let choice: FormKitFieldDescriptor.Choice
    let fieldTitle: String
    let identifier: String
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let tint = choice.color.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) } ?? accent
        let selectedText: Color = choice.color.map { $0.usesDarkForeground ? .black : .white } ?? .primary

        Button(action: action) {
            Text(choice.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? selectedText : .primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minWidth: 44, minHeight: 44)
                .background(tint.opacity(isSelected ? (choice.color == nil ? 0.18 : 1) : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(fieldTitle), \(choice.title)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }
}
