import SwiftUI

struct FormKitLineOptionsChoice: View {
    let context: FormKitFieldComponentContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selectedID = context.session.selectedEnumChoiceID(for: context.field)

        HStack(spacing: 4) {
            ForEach(context.field.enumOptions) { choice in
                let isSelected = selectedID == choice.id

                Button {
                    select(choice)
                } label: {
                    Text(choice.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSelected ? context.style.accent : .primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if isSelected {
                        FormKitLineOptionSelection(
                            style: context.style,
                            isInteractive: !context.isEditingLocked && !context.field.isDisabled
                        )
                    }
                }
                .accessibilityLabel("\(context.field.title), \(choice.title)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityIdentifier("\(context.field.accessibilityIdentifier)_option_\(choice.id)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(4)
        .background(context.style.secondaryText.opacity(0.08))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selectedID)
        .disabled(context.isEditingLocked || context.field.isDisabled)
    }

    func select(_ choice: FormKitFieldDescriptor.Choice) {
        guard !context.isEditingLocked, !context.field.isDisabled else {
            return
        }
        let isSelected = context.session.selectedEnumChoiceID(for: context.field) == choice.id
        guard !isSelected || !context.field.isRequired else {
            return
        }
        context.session.setSelectedEnumChoiceID(isSelected ? nil : choice.id, for: context.field)
    }
}
