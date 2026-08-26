import Foundation
import JSONSchema

public extension FormKitSession {
    var currentInstanceJSON: String {
        if let cachedCurrentInstanceJSON {
            return cachedCurrentInstanceJSON
        }

        let instanceJSON = Self.prettyJSONString(from: makeInstanceJSONValue())
        cachedCurrentInstanceJSON = instanceJSON
        return instanceJSON
    }

    func errorMessages(for field: FormKitFieldDescriptor) -> [String] {
        fieldErrors[field.id] ?? []
    }

    func errorMessages(for section: FormKitRenderPlan.SectionDescriptor) -> [String] {
        arrayErrors[section.id] ?? []
    }

    func primitiveValue(for field: FormKitFieldDescriptor) -> FormKitFieldDescriptor.PrimitiveValue? {
        if let explicitValue = fieldValues[field.id] {
            return explicitValue
        }

        if touchedFieldIDs.contains(field.id) {
            return nil
        }

        return seededValue(for: field)
    }

    internal func toolValueSource(for field: FormKitFieldDescriptor) -> FormKitToolValueSource? {
        guard primitiveValue(for: field) != nil else {
            return nil
        }

        if touchedFieldIDs.contains(field.id) {
            return .sessionEdit
        }

        if let source = toolValueSourceOverrides[field.pointer] {
            return source
        }

        guard let initialInstance,
              let initialValue = initialInstance.value(at: JSONPointer(from: field.pointer)),
              primitiveValue(
                from: initialValue,
                scalarType: field.scalarType,
                allowsNull: field.allowsNull,
                normalizesEmptyText: !field.enumOptions.contains {
                    jsonValue(from: $0.value) == initialValue
                }
              ) != nil
        else {
            return .defaultValue
        }

        return .initialInstance
    }

    func isNullSelected(for field: FormKitFieldDescriptor) -> Bool {
        primitiveValue(for: field) == .null
    }

    internal func isConcreteValuePending(for field: FormKitFieldDescriptor) -> Bool {
        pendingConcreteFieldIDs.contains(field.id)
    }

    func setNullSelection(_ isNullSelected: Bool, for field: FormKitFieldDescriptor) {
        guard field.isInteractive, field.allowsNull else {
            return
        }

        if isNullSelected {
            pendingConcreteFieldIDs.remove(field.id)
            setPrimitiveValue(.null, for: field)
        } else if let concreteValue = restoreConcreteValue(for: field) {
            pendingConcreteFieldIDs.remove(field.id)
            setPrimitiveValue(concreteValue, for: field)
        } else {
            pendingConcreteFieldIDs.insert(field.id)
        }
        handleFieldEdit(for: field)
    }

    func stringValue(for field: FormKitFieldDescriptor) -> String {
        guard let value = primitiveValue(for: field) else {
            return ""
        }

        switch value {
        case .string(let text):
            return text
        case .integer(let number):
            return String(number)
        case .number(let number):
            return Self.numberFormatter.string(from: NSNumber(value: number)) ?? String(number)
        case .boolean(let isEnabled):
            return isEnabled ? "true" : "false"
        case .null:
            return ""
        }
    }

    func setStringValue(_ text: String, for field: FormKitFieldDescriptor) {
        guard field.isInteractive else {
            return
        }

        pendingConcreteFieldIDs.remove(field.id)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, field.scalarType != .boolean {
            setPrimitiveValue(field.allowsNull ? .null : .string(text), for: field)
            handleFieldEdit(for: field)
            return
        }

        switch field.scalarType {
        case .string, .email, .uri, .date, .time, .dateTime:
            setPrimitiveValue(.string(text), for: field)
        case .integer:
            if let value = Int(trimmed) {
                setPrimitiveValue(.integer(value), for: field)
            } else {
                setPrimitiveValue(.string(text), for: field)
            }
        case .number:
            if let value = Double(trimmed) {
                setPrimitiveValue(.number(value), for: field)
            } else {
                setPrimitiveValue(.string(text), for: field)
            }
        case .boolean:
            if let value = Bool(trimmed) {
                setPrimitiveValue(.boolean(value), for: field)
            }
        }

        handleFieldEdit(for: field)
    }

    func booleanValue(for field: FormKitFieldDescriptor) -> Bool {
        if case .boolean(let value) = primitiveValue(for: field) {
            return value
        }

        if let defaultValue = field.defaultValue,
           case .boolean(let value) = defaultValue
        {
            return value
        }

        return false
    }

    func setBooleanValue(_ isOn: Bool, for field: FormKitFieldDescriptor) {
        guard field.isInteractive else {
            return
        }

        pendingConcreteFieldIDs.remove(field.id)
        setPrimitiveValue(.boolean(isOn), for: field)
        handleFieldEdit(for: field)
    }

    /// Replaces an untouched initial value with the field's current schema or control default.
    @discardableResult
    func rematerializeDefaultValue(for suppliedField: FormKitFieldDescriptor) -> Bool {
        guard let field = fieldsByID[suppliedField.id],
              field == suppliedField,
              field.isVisible,
              field.isInteractive,
              toolValueSource(for: field) == .initialInstance,
              let defaultValue = seededValue(for: field, preferInitialInstance: false),
              primitiveValue(for: field) != defaultValue
        else {
            return false
        }

        fieldValues[field.id] = defaultValue
        toolValueSourceOverrides[field.pointer] = .defaultValue
        handleFieldEdit(for: field)
        return true
    }

    func selectedEnumChoiceID(for field: FormKitFieldDescriptor) -> String? {
        guard let value = primitiveValue(for: field) else {
            return nil
        }
        return field.enumOptions.first(where: { $0.value == value })?.id
    }

    func setSelectedEnumChoiceID(_ choiceID: String?, for field: FormKitFieldDescriptor) {
        guard field.isInteractive else {
            return
        }

        pendingConcreteFieldIDs.remove(field.id)
        guard let choiceID else {
            setPrimitiveValue(nil, for: field)
            handleFieldEdit(for: field)
            return
        }

        setPrimitiveValue(
            field.enumOptions.first(where: { $0.id == choiceID })?.value,
            for: field
        )
        handleFieldEdit(for: field)
    }

    func dateValue(for field: FormKitFieldDescriptor) -> Date {
        guard let value = primitiveValue(for: field) else {
            return fallbackDate(for: field)
        }

        switch value {
        case .string(let rawValue):
            switch field.scalarType {
            case .date:
                return FormKitRenderer.dateFormatter.date(from: rawValue) ?? fallbackDate(for: field)
            case .time:
                return FormKitRenderer.reanchoredTime(from: rawValue)
                    ?? fallbackDate(for: field)
            case .dateTime:
                return FormKitRenderer.dateTimeFormatter.date(from: rawValue)
                    ?? FormKitRenderer.dateTimeFallbackFormatter.date(from: rawValue)
                    ?? fallbackDate(for: field)
            default:
                return fallbackDate(for: field)
            }
        default:
            return fallbackDate(for: field)
        }
    }

    func setDateValue(_ date: Date, for field: FormKitFieldDescriptor) {
        guard field.isInteractive else {
            return
        }

        pendingConcreteFieldIDs.remove(field.id)
        switch field.scalarType {
        case .date:
            setPrimitiveValue(.string(FormKitRenderer.dateFormatter.string(from: date)), for: field)
        case .time:
            setPrimitiveValue(.string(FormKitRenderer.timeFormatter.string(from: date)), for: field)
        case .dateTime:
            setPrimitiveValue(.string(FormKitRenderer.dateTimeFormatter.string(from: date)), for: field)
        default:
            return
        }

        handleFieldEdit(for: field)
    }

    internal func clearValue(for field: FormKitFieldDescriptor) {
        guard field.isInteractive else {
            return
        }

        pendingConcreteFieldIDs.remove(field.id)
        if field.allowsNull {
            setPrimitiveValue(.null, for: field)
        } else if field.isEnum || field.scalarType == .boolean {
            setPrimitiveValue(nil, for: field)
        } else {
            setPrimitiveValue(.string(""), for: field)
        }
        handleFieldEdit(for: field)
    }

    internal func unsetValue(for field: FormKitFieldDescriptor) {
        guard field.isInteractive, !field.isRequired else {
            return
        }

        pendingConcreteFieldIDs.remove(field.id)
        setPrimitiveValue(nil, for: field)
        handleFieldEdit(for: field)
    }

    private func handleFieldEdit(for field: FormKitFieldDescriptor) {
        revision += 1
        fieldErrors[field.id] = nil
        if fieldErrors[field.id]?.isEmpty == true {
            fieldErrors.removeValue(forKey: field.id)
        }

        if formErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            formErrorMessage = nil
        }

        if refreshesRenderPlanOnFieldEdit {
            refreshRenderPlan()
        }
        invalidateCurrentInstanceJSON()
        if hasAttemptedValidation, validationBehavior == .revalidateAfterFirstAttempt {
            _ = validate()
        } else if validationBehavior == .onDemandOnly {
            validationStatusMessage = nil
        }
    }
}
