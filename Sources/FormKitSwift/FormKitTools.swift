import Foundation

public struct FormKitToolContext: Equatable, Sendable {
    public let revision: Int
    public let title: String
    public let summary: String
    public let fields: [FormKitToolField]
    public let currentValues: [String: FormKitJSONValue]

    public init(
        revision: Int,
        title: String,
        summary: String,
        fields: [FormKitToolField],
        currentValues: [String: FormKitJSONValue]
    ) {
        self.revision = revision
        self.title = title
        self.summary = summary
        self.fields = fields
        self.currentValues = currentValues
    }
}

public struct FormKitToolField: Equatable, Sendable {
    public let pointer: String
    public let title: String
    public let type: String
    public let isRequired: Bool
    public let description: String?
    public let enumOptions: [String]
    public let isLocked: Bool
    public let validationMessages: [String]

    public init(
        pointer: String,
        title: String,
        type: String,
        isRequired: Bool,
        description: String? = nil,
        enumOptions: [String] = [],
        isLocked: Bool = false,
        validationMessages: [String] = []
    ) {
        self.pointer = pointer
        self.title = title
        self.type = type
        self.isRequired = isRequired
        self.description = description
        self.enumOptions = enumOptions
        self.isLocked = isLocked
        self.validationMessages = validationMessages
    }
}

public struct FormKitToolEdit: Equatable, Sendable {
    public enum Operation: String, Equatable, Sendable {
        case set
        case clear
    }

    public let pointer: String
    public let operation: Operation
    public let value: FormKitJSONValue?

    public init(pointer: String, operation: Operation, value: FormKitJSONValue? = nil) {
        self.pointer = pointer
        self.operation = operation
        self.value = value
    }
}

public struct FormKitToolEditResult: Equatable, Sendable {
    public let revision: Int
    public let summary: String?
    public let appliedEdits: [FormKitToolEdit]
    public let rejectedEdits: [FormKitRejectedEdit]
    public let validationMessages: [String]
    public let context: FormKitToolContext

    public init(
        revision: Int,
        summary: String? = nil,
        appliedEdits: [FormKitToolEdit],
        rejectedEdits: [FormKitRejectedEdit] = [],
        validationMessages: [String] = [],
        context: FormKitToolContext
    ) {
        self.revision = revision
        self.summary = summary
        self.appliedEdits = appliedEdits
        self.rejectedEdits = rejectedEdits
        self.validationMessages = validationMessages
        self.context = context
    }
}

public struct FormKitRejectedEdit: Equatable, Sendable {
    public let pointer: String
    public let reason: String
    public let message: String

    public init(pointer: String, reason: String, message: String) {
        self.pointer = pointer
        self.reason = reason
        self.message = message
    }
}

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
                isRequired: field.isRequired,
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
            guard let field = field(forToolPointer: edit.pointer) else {
                rejectedEdits.append(
                    FormKitRejectedEdit(
                        pointer: edit.pointer,
                        reason: "field_not_found",
                        message: "The requested field does not exist in the visible form."
                    )
                )
                continue
            }

            guard field.isVisible, field.isDisabled == false else {
                rejectedEdits.append(
                    FormKitRejectedEdit(
                        pointer: edit.pointer,
                        reason: "field_not_visible",
                        message: "The requested field is not currently visible or editable."
                    )
                )
                continue
            }

            let publicPointer = publicToolPointer(for: field.pointer)
            guard !normalizedLockedPointers.contains(normalizedToolPointer(publicPointer)) else {
                rejectedEdits.append(
                    FormKitRejectedEdit(
                        pointer: edit.pointer,
                        reason: "field_locked",
                        message: "The requested field is locked."
                    )
                )
                continue
            }

            switch applyToolEdit(edit, to: field, publicPointer: publicPointer) {
            case .applied(let appliedEdit):
                appliedEdits.append(appliedEdit)
            case .rejected(let rejectedEdit):
                rejectedEdits.append(rejectedEdit)
            }
        }

        return FormKitToolEditResult(
            revision: revision,
            summary: appliedEdits.isEmpty ? "No edits were applied." : "Applied \(appliedEdits.count) edit\(appliedEdits.count == 1 ? "" : "s").",
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
        to field: FormKitFieldDescriptor,
        publicPointer: String
    ) -> ToolEditApplicationOutcome {
        switch edit.operation {
        case .clear:
            if field.isEnum {
                let hadValue = selectedEnumChoiceID(for: field) != nil
                guard hadValue else {
                    return .rejected(FormKitRejectedEdit(pointer: edit.pointer, reason: "no_change", message: "The field is already empty."))
                }

                setSelectedEnumChoiceID(nil, for: field)
                return .applied(FormKitToolEdit(pointer: publicPointer, operation: .clear))
            }

            let hadValue = primitiveValue(for: field) != nil
            guard hadValue else {
                return .rejected(FormKitRejectedEdit(pointer: edit.pointer, reason: "no_change", message: "The field is already empty."))
            }

            clearValue(for: field)
            return .applied(FormKitToolEdit(pointer: publicPointer, operation: .clear))

        case .set:
            guard let value = edit.value else {
                return .rejected(FormKitRejectedEdit(pointer: edit.pointer, reason: "missing_value", message: "A set operation requires a value."))
            }

            if field.isEnum {
                guard case .string(let rawChoice) = value else {
                    return .rejected(FormKitRejectedEdit(pointer: edit.pointer, reason: "type_mismatch", message: "Enum fields require a string value."))
                }
                guard let choice = field.enumOptions.first(where: { option in
                    option.title.caseInsensitiveCompare(rawChoice) == .orderedSame
                        || primitiveTitle(option.value).caseInsensitiveCompare(rawChoice) == .orderedSame
                }) else {
                    return .rejected(FormKitRejectedEdit(pointer: edit.pointer, reason: "invalid_choice", message: "The supplied value is not a valid option for this field."))
                }
                setSelectedEnumChoiceID(choice.id, for: field)
                return .applied(FormKitToolEdit(pointer: publicPointer, operation: .set, value: toolValue(from: choice.value)))
            }

            switch field.scalarType {
            case .string, .email, .uri, .date, .dateTime:
                guard case .string(let text) = value else {
                    return .rejected(FormKitRejectedEdit(pointer: edit.pointer, reason: "type_mismatch", message: "This field requires a string value."))
                }
                setStringValue(text, for: field)
                return .applied(FormKitToolEdit(pointer: publicPointer, operation: .set, value: .string(text)))

            case .integer, .number:
                switch value {
                case .integer(let number):
                    setStringValue(String(number), for: field)
                    return .applied(FormKitToolEdit(pointer: publicPointer, operation: .set, value: .integer(number)))
                case .number(let number):
                    setStringValue(number.rounded(.towardZero) == number ? String(Int(number)) : String(number), for: field)
                    return .applied(FormKitToolEdit(pointer: publicPointer, operation: .set, value: .number(number)))
                case .string(let text):
                    setStringValue(text, for: field)
                    return .applied(FormKitToolEdit(pointer: publicPointer, operation: .set, value: .string(text)))
                default:
                    return .rejected(FormKitRejectedEdit(pointer: edit.pointer, reason: "type_mismatch", message: "This field requires a numeric value."))
                }

            case .boolean:
                guard case .boolean(let boolValue) = value else {
                    return .rejected(FormKitRejectedEdit(pointer: edit.pointer, reason: "type_mismatch", message: "This field requires a boolean value."))
                }
                setBooleanValue(boolValue, for: field)
                return .applied(FormKitToolEdit(pointer: publicPointer, operation: .set, value: .boolean(boolValue)))
            }
        }
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
        if case .string(let text) = primitive,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return nil
        }
        return toolValue(from: primitive)
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
            guard field.isRequired, currentValues[field.pointer] == nil else {
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
