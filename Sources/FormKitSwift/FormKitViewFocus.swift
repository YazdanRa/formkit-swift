import SwiftUI

extension FormKitContainerView {
    func focusFirstField(in sectionID: String, renderIndex: FormKitRenderIndex) {
        guard let arrayDescriptor = renderIndex.section(sectionID)?.arrayDescriptor,
              let row = arrayDescriptor.rows.last
        else {
            return
        }

        if let field = renderIndex.firstFocusableField(in: row) {
            focusedFieldID = field.id
        }
    }

    @discardableResult
    func commitFocusedTextDraft() -> Bool {
        guard let focusedFieldID,
              let draft = pendingTextDrafts.removeValue(forKey: focusedFieldID),
              let field = session.renderPlan.fields.first(where: { $0.id == focusedFieldID })
        else {
            return false
        }

        session.setStringValue(draft, for: field)
        return true
    }

    func advanceFocus(after fieldID: String) {
        commitFocusedTextDraft()
        let focusableIDs = FormKitFocusSupport.resolvedComponents(
            session: session,
            options: options
        ).focusableFieldIDs
        let renderIndex = FormKitRenderIndex(
            renderPlan: session.renderPlan,
            focusableFieldIDs: focusableIDs
        )
        focusedFieldID = renderIndex.nextFocusableFieldID(after: fieldID)
    }

    func borderColor(
        for field: FormKitFieldDescriptor,
        state: FormKitFieldVisualState,
        hasErrors: Bool
    ) -> Color {
        if hasErrors {
            return options.style.destructive
        }
        if focusedFieldID == field.id {
            return options.style.accent
        }
        switch state {
        case .changed:
            return options.style.accent
        case .locked:
            return options.style.secondaryText
        case .normal:
            return options.style.secondaryText.opacity(0.25)
        }
    }

    func fieldPrompt(for field: FormKitFieldDescriptor) -> String {
        switch field.scalarType {
        case .email:
            return "name@example.com"
        case .uri:
            return "https://example.com"
        case .integer:
            return "0"
        case .number:
            return "0.0"
        default:
            return ""
        }
    }

    func nullableBooleanSelection(for field: FormKitFieldDescriptor) -> NullableBooleanSelection {
        switch session.primitiveValue(for: field) {
        case .boolean(let value):
            return .boolean(value)
        case .null:
            return .null
        case nil:
            return .absent
        default:
            return field.isRequired ? .null : .absent
        }
    }

    func nullableValueSelection(for field: FormKitFieldDescriptor) -> NullableValueSelection {
        if session.isConcreteValuePending(for: field) {
            return .value
        }

        switch session.primitiveValue(for: field) {
        case .string, .integer, .number:
            return .value
        case .null:
            return .null
        case nil:
            return .absent
        default:
            return field.isRequired ? .null : .absent
        }
    }

    func fieldIdentifier(for field: FormKitFieldDescriptor) -> String {
        FormKitAccessibility.fieldIdentifier(for: field)
    }
}

enum NullableBooleanSelection: Hashable {
    case absent
    case null
    case boolean(Bool)
}

struct FormKitMessageRow: View {
    let message: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(color)
                .multilineTextAlignment(.leading)
        }
    }
}
