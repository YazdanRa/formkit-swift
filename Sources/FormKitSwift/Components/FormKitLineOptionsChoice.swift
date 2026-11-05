import SwiftUI

struct FormKitLineOptionsChoice: View {
    /// Enums outside this range fall back to the standard picker.
    static let supportedChoiceCounts = 2...6
    /// Up to this many choices share one row; more stack vertically.
    static let maxInlineChoices = 3
    /// A label longer than this stacks the segments vertically, so no segment wraps mid-word.
    static let maxInlineTitleLength = 14

    let context: FormKitFieldComponentContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast

    static func stacksVertically(_ choices: [FormKitFieldDescriptor.Choice], isAccessibilitySize: Bool) -> Bool {
        isAccessibilitySize
            || choices.count > maxInlineChoices
            || choices.contains { $0.title.count > maxInlineTitleLength }
    }

    var body: some View {
        let selectedID = context.session.selectedEnumChoiceID(for: context.field)
        let isVertical = Self.stacksVertically(
            context.field.enumOptions,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        let layout = isVertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        let border = context.style.secondaryText.opacity(contrast == .increased ? 0.9 : 0.45)

        layout {
            ForEach(context.field.enumOptions) { choice in
                FormKitLineOptionButton(
                    choice: choice,
                    fieldTitle: context.field.title,
                    identifier: "\(context.field.accessibilityIdentifier)_option_\(choice.id)",
                    accent: context.style.accent,
                    isSelected: selectedID == choice.id,
                    isStacked: isVertical
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
