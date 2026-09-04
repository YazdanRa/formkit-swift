import Foundation

public extension FormKitSession {
    private enum ToolEditApplicationOutcome {
        case applied(FormKitToolEdit)
        case rejected(FormKitRejectedEdit)
    }

    func makeToolContext(focusedPointers: Set<String> = []) -> FormKitToolContext {
        let normalizedFocusedPointers = Set(focusedPointers.map(normalizedToolPointer))
        let visibleFields = renderPlan.fieldOrder.compactMap { fieldID in
            renderPlan.fields.first(where: { $0.id == fieldID && $0.isVisible })
        }

        let fields = visibleFields.map { field in
            let pointer = publicToolPointer(for: field.pointer)
            return FormKitToolField(
                pointer: pointer,
                title: field.title,
                type: field.isEnum ? "enum" : field.scalarType.rawValue,
                valueFormat: FormKitRenderer.toolValueFormat(for: field.scalarType),
                isRequired: field.isRequired,
                valueSource: toolValueSource(for: field),
                description: field.description,
                enumOptions: field.enumOptions.map(\.title),
                isLocked: normalizedFocusedPointers.contains(normalizedToolPointer(pointer)),
                validationMessages: errorMessages(for: field)
            )
        }

        let currentValues: [String: FormKitJSONValue] = Dictionary(
            uniqueKeysWithValues: visibleFields.compactMap { field in
                guard let value = toolValue(for: field) else {
                    return nil
                }
                return (publicToolPointer(for: field.pointer), value)
            }
        )

        return FormKitToolContext(
            revision: revision,
            title: renderPlan.title,
            summary: toolSummary(for: fields, currentValues: currentValues),
            fields: fields,
            currentValues: currentValues
        )
    }

    func applyToolEdits(
        _ edits: [FormKitToolEdit],
        baseRevision: Int? = nil,
        lockedPointers: Set<String> = []
    ) -> FormKitToolEditResult {
        let contextBeforeApply = makeToolContext()
        if let baseRevision, baseRevision != revision {
            return FormKitToolEditResult(
                revision: revision,
                summary: "Skipped edits because the form changed while edits were being prepared.",
                appliedEdits: [],
                rejectedEdits: edits.map {
                    FormKitRejectedEdit(
                        pointer: $0.pointer,
                        reason: "revision_conflict",
                        message: "Expected revision \(baseRevision), but the current revision is \(revision)."
                    )
                },
                validationMessages: validationMessagesForToolUse(),
                context: contextBeforeApply
            )
        }

        let normalizedLockedPointers = Set(lockedPointers.map(normalizedToolPointer))
        var appliedEdits: [FormKitToolEdit] = []
        var rejectedEdits: [FormKitRejectedEdit] = []

        for edit in edits {
            switch applyToolEdit(edit, lockedPointers: normalizedLockedPointers) {
            case .applied(let appliedEdit):
                appliedEdits.append(appliedEdit)
            case .rejected(let rejectedEdit):
                rejectedEdits.append(rejectedEdit)
            }
        }

        return FormKitToolEditResult(
            revision: revision,
            summary: toolEditSummary(appliedCount: appliedEdits.count),
            appliedEdits: appliedEdits,
            rejectedEdits: rejectedEdits,
            validationMessages: validationMessagesForToolUse(),
            context: makeToolContext()
        )
    }

    func toolValidationMessages() -> [String] {
        validationMessagesForToolUse()
    }

    private func applyToolEdit(
        _ edit: FormKitToolEdit,
        lockedPointers: Set<String>
    ) -> ToolEditApplicationOutcome {
        guard let field = field(forToolPointer: edit.pointer) else {
            return rejected(
                edit,
                reason: "field_not_found",
                message: "The requested field does not exist in the visible form."
            )
        }

        guard field.isVisible, field.isDisabled == false else {
            return rejected(
                edit,
                reason: "field_not_visible",
                message: "The requested field is not currently visible or editable."
            )
        }

        let publicPointer = publicToolPointer(for: field.pointer)
        guard !lockedPointers.contains(normalizedToolPointer(publicPointer)) else {
            return rejected(edit, reason: "field_locked", message: "The requested field is locked.")
        }

        return applyToolEdit(edit, to: field, publicPointer: publicPointer)
    }

    private func applyToolEdit(
        _ edit: FormKitToolEdit,
        to field: FormKitFieldDescriptor,
        publicPointer: String
    ) -> ToolEditApplicationOutcome {
        switch edit.operation {
        case .clear:
            return applyClearToolEdit(edit, to: field, publicPointer: publicPointer)
        case .set:
            guard let value = edit.value else {
                return rejected(edit, reason: "missing_value", message: "A set operation requires a value.")
            }

            if field.isEnum {
                return applyEnumSetToolEdit(edit, value: value, to: field, publicPointer: publicPointer)
            }

            return applyScalarSetToolEdit(edit, value: value, to: field, publicPointer: publicPointer)
        }
    }

    private func applyClearToolEdit(
        _ edit: FormKitToolEdit,
        to field: FormKitFieldDescriptor,
        publicPointer: String
    ) -> ToolEditApplicationOutcome {
        if field.allowsNull {
            guard primitiveValue(for: field) != .null else {
                return rejected(edit, reason: "no_change", message: "The field is already empty.")
            }

            clearValue(for: field)
            return .applied(FormKitToolEdit(pointer: publicPointer, operation: .clear))
        }

        if field.isEnum {
            guard selectedEnumChoiceID(for: field) != nil else {
                return rejected(edit, reason: "no_change", message: "The field is already empty.")
            }

            setSelectedEnumChoiceID(nil, for: field)
            return .applied(FormKitToolEdit(pointer: publicPointer, operation: .clear))
        }

        guard primitiveValue(for: field).map(hasConcreteToolValue) == true else {
            return rejected(edit, reason: "no_change", message: "The field is already empty.")
        }

        clearValue(for: field)
        return .applied(FormKitToolEdit(pointer: publicPointer, operation: .clear))
    }

    private func applyEnumSetToolEdit(
        _ edit: FormKitToolEdit,
        value: FormKitJSONValue,
        to field: FormKitFieldDescriptor,
        publicPointer: String
    ) -> ToolEditApplicationOutcome {
        guard case .string(let rawChoice) = value else {
            return rejected(edit, reason: "type_mismatch", message: "Enum fields require a string value.")
        }
        guard let choice = field.enumOptions.first(where: { option in
            option.title.caseInsensitiveCompare(rawChoice) == .orderedSame
                || primitiveTitle(option.value).caseInsensitiveCompare(rawChoice) == .orderedSame
        }) else {
            return rejected(
                edit,
                reason: "invalid_choice",
                message: "The supplied value is not a valid option for this field."
            )
        }

        setSelectedEnumChoiceID(choice.id, for: field)
        return appliedSetEdit(for: field, pointer: publicPointer)
    }

    private func applyScalarSetToolEdit(
        _ edit: FormKitToolEdit,
        value: FormKitJSONValue,
        to field: FormKitFieldDescriptor,
        publicPointer: String
    ) -> ToolEditApplicationOutcome {
        switch field.scalarType {
        case .string, .email, .uri:
            guard case .string(let text) = value else {
                return rejected(edit, reason: "type_mismatch", message: "This field requires a string value.")
            }
            setStringValue(text, for: field)
        case .date, .time, .dateTime:
            guard case .string(let text) = value else {
                return rejected(edit, reason: "type_mismatch", message: "This field requires a string value.")
            }
            guard let normalizedValue = FormKitRenderer.normalizedToolTemporalValue(
                from: text,
                type: field.scalarType
            ) else {
                let format = FormKitRenderer.toolValueFormat(for: field.scalarType) ?? "the field's required format"
                return rejected(
                    edit,
                    reason: "invalid_format",
                    message: "Use \(format)."
                )
            }
            setStringValue(normalizedValue, for: field)
        case .integer, .number:
            return applyNumericSetToolEdit(edit, value: value, to: field, publicPointer: publicPointer)
        case .boolean:
            guard case .boolean(let boolValue) = value else {
                return rejected(edit, reason: "type_mismatch", message: "This field requires a boolean value.")
            }
            setBooleanValue(boolValue, for: field)
        }

        return appliedSetEdit(for: field, pointer: publicPointer)
    }

    private func applyNumericSetToolEdit(
        _ edit: FormKitToolEdit,
        value: FormKitJSONValue,
        to field: FormKitFieldDescriptor,
        publicPointer: String
    ) -> ToolEditApplicationOutcome {
        switch value {
        case .integer(let number):
            setStringValue(String(number), for: field)
        case .number(let number):
            let text = number.rounded(.towardZero) == number
                ? String(Int(number))
                : String(number)
            setStringValue(text, for: field)
        case .string(let text):
            setStringValue(text, for: field)
        default:
            return rejected(edit, reason: "type_mismatch", message: "This field requires a numeric value.")
        }

        return appliedSetEdit(for: field, pointer: publicPointer)
    }

    private func rejected(
        _ edit: FormKitToolEdit,
        reason: String,
        message: String
    ) -> ToolEditApplicationOutcome {
        .rejected(FormKitRejectedEdit(pointer: edit.pointer, reason: reason, message: message))
    }

    private func toolEditSummary(appliedCount: Int) -> String {
        appliedCount == 0
            ? "No edits were applied."
            : "Applied \(appliedCount) edit\(appliedCount == 1 ? "" : "s")."
    }

    private func appliedSetEdit(
        for field: FormKitFieldDescriptor,
        pointer: String
    ) -> ToolEditApplicationOutcome {
        .applied(
            FormKitToolEdit(
                pointer: pointer,
                operation: .set,
                value: toolValue(for: field)
            )
        )
    }

    private func field(forToolPointer pointer: String) -> FormKitFieldDescriptor? {
        let normalizedPointer = normalizedToolPointer(pointer)
        return renderPlan.fields.first {
            $0.isVisible && normalizedToolPointer($0.pointer) == normalizedPointer
        }
    }

    private func toolValue(for field: FormKitFieldDescriptor) -> FormKitJSONValue? {
        guard let primitive = primitiveValue(for: field) else {
            return nil
        }
        return toolValue(from: primitive)
    }

    private func hasConcreteToolValue(_ primitive: FormKitFieldDescriptor.PrimitiveValue) -> Bool {
        switch primitive {
        case .null:
            return false
        case .string(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    private func toolValue(from primitive: FormKitFieldDescriptor.PrimitiveValue) -> FormKitJSONValue {
        switch primitive {
        case .string(let text):
            return .string(text)
        case .integer(let number):
            return .integer(number)
        case .number(let number):
            return .number(number)
        case .boolean(let value):
            return .boolean(value)
        case .null:
            return .null
        }
    }

    private func validationMessagesForToolUse() -> [String] {
        var messages: [String] = []
        if let validationStatusMessage {
            messages.append(validationStatusMessage)
        }
        if let formErrorMessage {
            messages.append(formErrorMessage)
        }
        for field in renderPlan.fields where field.isVisible {
            messages.append(contentsOf: errorMessages(for: field))
        }
        return Array(NSOrderedSet(array: messages)) as? [String] ?? messages
    }

    private func toolSummary(
        for fields: [FormKitToolField],
        currentValues: [String: FormKitJSONValue]
    ) -> String {
        let missingRequiredTitles = fields.compactMap { field -> String? in
            guard field.isRequired else {
                return nil
            }
            if case .string(let value) = currentValues[field.pointer],
               value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return field.title
            }
            guard currentValues[field.pointer] == nil else {
                return nil
            }
            return field.title
        }
        return missingRequiredTitles.isEmpty
            ? "All currently visible required fields are filled."
            : "Missing required fields: \(missingRequiredTitles.joined(separator: ", "))."
    }

    private func publicToolPointer(for pointer: String) -> String {
        normalizedToolPointer(pointer)
    }

    private func normalizedToolPointer(_ pointer: String) -> String {
        let trimmed = pointer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private func primitiveTitle(_ value: FormKitFieldDescriptor.PrimitiveValue) -> String {
        switch value {
        case .string(let text):
            return text
        case .integer(let number):
            return String(number)
        case .number(let number):
            return String(number)
        case .boolean(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }
}
