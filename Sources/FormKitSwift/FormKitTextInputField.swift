import SwiftUI

struct FormKitDebouncedTextInputField: View {
    let fieldID: String
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let prompt: String
    let canonicalText: String
    let submitLabel: SubmitLabel
    let focusedFieldID: FocusState<String?>.Binding
    let inputTraits: FormKitTextInputTraits
    let isEditingLocked: Bool
    let onDraftChange: (String?) -> Void
    let onSubmit: () -> Void
    let onCommit: (String) -> Void

    @State private var draftText: String

    init(
        fieldID: String,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        prompt: String,
        canonicalText: String,
        submitLabel: SubmitLabel,
        focusedFieldID: FocusState<String?>.Binding,
        inputTraits: FormKitTextInputTraits,
        isEditingLocked: Bool,
        onDraftChange: @escaping (String?) -> Void,
        onSubmit: @escaping () -> Void,
        onCommit: @escaping (String) -> Void
    ) {
        self.fieldID = fieldID
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.prompt = prompt
        self.canonicalText = canonicalText
        self.submitLabel = submitLabel
        self.focusedFieldID = focusedFieldID
        self.inputTraits = inputTraits
        self.isEditingLocked = isEditingLocked
        self.onDraftChange = onDraftChange
        self.onSubmit = onSubmit
        self.onCommit = onCommit
        _draftText = State(initialValue: canonicalText)
    }

    var body: some View {
        textField
            .formKitTextInputTraits(inputTraits)
    }

    private var textField: some View {
        TextField(
            prompt,
            text: Binding(
                get: { draftText },
                set: { newValue in
                    draftText = newValue
                    onDraftChange(newValue == canonicalText ? nil : newValue)
                }
            ),
            axis: inputTraits.supportsVerticalExpansion ? .vertical : .horizontal
        )
        .lineLimit(1...)
        .submitLabel(inputTraits.supportsVerticalExpansion ? .return : submitLabel)
        .focused(focusedFieldID, equals: fieldID)
        .disabled(isEditingLocked)
        .onChange(of: canonicalText) { _, newValue in
            guard draftText != newValue else {
                return
            }
            draftText = newValue
            onDraftChange(nil)
        }
        .onChange(of: focusedFieldID.wrappedValue) { _, newValue in
            if newValue != fieldID {
                commitIfNeeded()
            }
        }
        .onSubmit {
            commitIfNeeded()
            onSubmit()
        }
        .onDisappear {
            commitIfNeeded()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
    }

    private func commitIfNeeded() {
        guard draftText != canonicalText else {
            return
        }
        onCommit(draftText)
    }
}
