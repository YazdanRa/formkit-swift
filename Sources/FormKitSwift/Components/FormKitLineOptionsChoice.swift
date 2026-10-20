import SwiftUI

struct FormKitLineOptionsChoice: View {
    let context: FormKitFieldComponentContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let selectedID = context.session.selectedEnumChoiceID(for: context.field)
        let isVertical = dynamicTypeSize.isAccessibilitySize
        let layout = isVertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        let border = context.style.secondaryText.opacity(contrast == .increased ? 0.9 : 0.45)

        layout {
            ForEach(context.field.enumOptions) { choice in
                FormKitLineOptionButton(
                    choice: choice,
                    fieldTitle: context.field.title,
                    identifier: "\(context.field.accessibilityIdentifier)_option_\(choice.id)",
                    accent: context.style.accent,
                    isSelected: selectedID == choice.id
                ) {
                    select(choice)
                }
                .overlay(alignment: isVertical ? .bottom : .trailing) {
                    if choice.id != context.field.enumOptions.last?.id {
                        Rectangle()
                            .fill(border)
                            .frame(width: isVertical ? nil : 1, height: isVertical ? 1 : nil)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22).strokeBorder(border, lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selectedID)
        .disabled(context.isEditingLocked || context.field.isDisabled)
        .opacity(context.isEditingLocked || context.field.isDisabled ? 0.5 : 1)
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
