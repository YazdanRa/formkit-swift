import Foundation
import JSONSchema

extension FormKitSession {
    func restoreConcreteValue(for field: FormKitFieldDescriptor) -> FormKitFieldDescriptor.PrimitiveValue? {
        if let seededValue = seededValue(for: field, preferInitialInstance: false, usesNullFallback: false),
           seededValue != .null,
           !seededValue.isBlankString
        {
            return seededValue
        }
        switch field.scalarType {
        case .integer:
            return .integer(0)
        case .number:
            return .number(0)
        default:
            return nil
        }
    }

    func shouldSerialize(_ field: FormKitFieldDescriptor) -> Bool {
        field.shouldSerialize || (includesHiddenToolFields && !field.isVisible
            && (toolValueSource(for: field) == .initialInstance || toolValueSource(for: field) == .sessionEdit))
    }

    func makeInstanceJSONValue() -> FormKitJSONValue {
        var rootObject: [String: FormKitJSONValue] = [:]
        let requiredSectionPointers = Set(
            renderPlan.sections
                .filter(\.isRequired)
                .filter(\.shouldSerialize)
                .filter { !$0.isOwnedByArrayRow }
                .map(\.pointer)
                .filter { $0 != "#" }
        )

        for pointer in requiredSectionPointers.sorted(by: { $0.count < $1.count }) {
            ensureObjectExists(at: pointer, in: &rootObject)
        }

        let arraySections = renderPlan.sections
            .filter(shouldSerializeArray)
            .filter { !$0.isOwnedByArrayRow }
            .compactMap { section -> (FormKitRenderPlan.SectionDescriptor, FormKitArraySectionDescriptor)? in
                guard let descriptor = section.arrayDescriptor else {
                    return nil
                }
                return (section, descriptor)
            }
            .sorted { lhs, rhs in
                lhs.1.pointer.count < rhs.1.pointer.count
            }

        for (section, descriptor) in arraySections {
            if descriptor.rows.isEmpty {
                if descriptor.materializeWhenEmpty || touchedArrayIDs.contains(section.id) {
                    setArray([], at: descriptor.pointer, in: &rootObject)
                }
                continue
            }

            for row in descriptor.rows {
                insert(row.placeholderValue, at: row.pointer, into: &rootObject)
            }
        }

        restoreHiddenObjectContainers(into: &rootObject)

        for field in orderedFields {
            guard shouldSerialize(field) else {
                continue
            }

            guard let storedValue = primitiveValue(for: field) else {
                continue
            }

            insert(
                jsonValue(from: storedValue),
                at: field.pointer,
                into: &rootObject
            )
        }

        return .object(rootObject)
    }

    private func shouldSerializeArray(_ section: FormKitRenderPlan.SectionDescriptor) -> Bool {
        section.shouldSerialize || (includesHiddenToolFields && !section.isVisible
            && (suppliedInstance?.value(at: JSONPointer(from: section.pointer))?.array != nil
                || touchedArrayIDs.contains(section.id)
                || touchedFieldIDs.contains { $0.hasPrefix(section.pointer + "/") }))
    }

    private func restoreHiddenObjectContainers(into rootObject: inout [String: FormKitJSONValue]) {
        guard includesHiddenToolFields else { return }
        for section in renderPlan.sections where !section.isVisible {
            if suppliedInstance?.value(at: JSONPointer(from: section.pointer))?.object != nil {
                ensureObjectExists(at: section.pointer, in: &rootObject)
            }
        }
    }

    func refreshRenderPlan() {
        let nextPlan = Self.failClosed(renderPlanProvider(makeInstanceJSONValue()))
        guard nextPlan != renderPlan else {
            return
        }

        renderPlan = nextPlan
        rebuildRenderPlanCaches()

        let visibleFieldIDs = Set(nextPlan.fields.map(\.id))
        let visibleArrayIDs: Set<String> = Set(
            nextPlan.sections.compactMap { section in
                guard section.arrayDescriptor != nil else {
                    return nil
                }
                return section.id
            }
        )
        fieldErrors = fieldErrors.filter { visibleFieldIDs.contains($0.key) }
        pendingConcreteFieldIDs = pendingConcreteFieldIDs.filter { visibleFieldIDs.contains($0) }
        arrayErrors = arrayErrors.filter { visibleArrayIDs.contains($0.key) }
        if let firstInvalidFieldID, !visibleFieldIDs.contains(firstInvalidFieldID) {
            self.firstInvalidFieldID = nil
        }
    }

    func applyInstance(_ instance: FormKitJSONValue) {
        revision += 1
        let nextPlan = Self.failClosed(renderPlanProvider(instance))
        let previousFieldValues = fieldValues
        renderPlan = nextPlan
        rebuildRenderPlanCaches()
        let seededFieldValues = fieldValueSeedProvider(nextPlan, instance).compactMapValues { $0 }
        var nextFieldValues = previousFieldValues

        for field in nextPlan.fields {
            if touchedFieldIDs.contains(field.id),
               let preservedValue = previousFieldValues[field.id]
            {
                nextFieldValues[field.id] = preservedValue
                continue
            }

            if let seededValue = seededFieldValues[field.id] {
                nextFieldValues[field.id] = seededValue
            } else {
                nextFieldValues.removeValue(forKey: field.id)
            }
        }

        fieldValues = nextFieldValues

        let visibleFieldIDs = Set(nextPlan.fields.map(\.id))
        let visibleArrayIDs: Set<String> = Set(
            nextPlan.sections.compactMap { section in
                guard section.arrayDescriptor != nil else {
                    return nil
                }
                return section.id
            }
        )
        touchedFieldIDs = touchedFieldIDs.filter { visibleFieldIDs.contains($0) }
        touchedArrayIDs = touchedArrayIDs.filter { visibleArrayIDs.contains($0) }
        pendingConcreteFieldIDs = pendingConcreteFieldIDs.filter { visibleFieldIDs.contains($0) }
        fieldErrors = fieldErrors.filter { visibleFieldIDs.contains($0.key) }
        arrayErrors = arrayErrors.filter { visibleArrayIDs.contains($0.key) }
        if let firstInvalidFieldID, !visibleFieldIDs.contains(firstInvalidFieldID) {
            self.firstInvalidFieldID = nil
        }

        invalidateCurrentInstanceJSON()
        if hasAttemptedValidation, validationBehavior == .revalidateAfterFirstAttempt {
            _ = validate()
        } else if validationBehavior == .onDemandOnly {
            validationStatusMessage = nil
        }
    }

    func invalidateCurrentInstanceJSON() {
        cachedCurrentInstanceJSON = nil
    }

    func rebuildRenderPlanCaches() {
        fieldsByID = Dictionary(uniqueKeysWithValues: renderPlan.fields.map { ($0.id, $0) })
        orderedFields = renderPlan.fieldOrder.compactMap { fieldsByID[$0] }
        arraySectionsByPointer = Dictionary(
            uniqueKeysWithValues: renderPlan.sections.compactMap { section in
                guard section.arrayDescriptor != nil else {
                    return nil
                }
                return (section.pointer, section)
            }
        )
    }

    func setPrimitiveValue(
        _ value: FormKitFieldDescriptor.PrimitiveValue?,
        for field: FormKitFieldDescriptor
    ) {
        touchedFieldIDs.insert(field.id)
        if let value {
            fieldValues[field.id] = value
        } else {
            fieldValues.removeValue(forKey: field.id)
        }
    }

    func seededValue(
        for field: FormKitFieldDescriptor,
        preferInitialInstance: Bool = true,
        usesNullFallback: Bool = true
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        if preferInitialInstance,
           let initialInstance = includesHiddenToolFields ? suppliedInstance : initialInstance,
           let initialValue = initialInstance.value(at: JSONPointer(from: field.pointer)),
           let seededFromInstance = primitiveValue(
            from: initialValue,
            scalarType: field.scalarType,
            allowsNull: field.allowsNull,
            normalizesEmptyText: !field.enumOptions.contains {
                jsonValue(from: $0.value) == initialValue
            }
           )
        {
            return seededFromInstance
        }

        if let defaultValue = field.defaultValue {
            return defaultValue
        }

        if field.allowsNull, field.isRequired, usesNullFallback {
            return .null
        }

        if field.isEnum {
            return field.isRequired ? field.enumOptions.first?.value : nil
        }

        switch field.scalarType {
        case .boolean:
            return field.isRequired ? .boolean(false) : nil
        case .date:
            return field.isRequired ? .string(FormKitRenderer.dateFormatter.string(from: .now)) : nil
        case .time:
            return field.isRequired ? .string(FormKitRenderer.timeFormatter.string(from: .now)) : nil
        case .dateTime:
            return field.isRequired ? .string(FormKitRenderer.dateTimeFormatter.string(from: .now)) : nil
        default:
            return nil
        }
    }

    func primitiveValue(
        from jsonValue: FormKitJSONValue?,
        scalarType: FormKitFieldDescriptor.ScalarType,
        allowsNull: Bool,
        normalizesEmptyText: Bool = true
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        guard let jsonValue else {
            return nil
        }

        switch jsonValue {
        case .null:
            return allowsNull ? .null : nil
        case .string(let value):
            return primitiveString(
                value,
                scalarType: scalarType,
                allowsNull: allowsNull,
                normalizesEmptyText: normalizesEmptyText
            )
        case .integer(let value):
            return primitiveInteger(value, scalarType: scalarType)
        case .number(let value):
            return scalarType == .number ? .number(value) : nil
        case .boolean(let value):
            return scalarType == .boolean ? .boolean(value) : nil
        case .object, .array:
            return nil
        }
    }

    private func primitiveString(
        _ value: String,
        scalarType: FormKitFieldDescriptor.ScalarType,
        allowsNull: Bool,
        normalizesEmptyText: Bool
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        if allowsNull,
           normalizesEmptyText,
           value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return .null
        }

        switch scalarType {
        case .string, .email, .uri, .date, .time, .dateTime, .integer, .number:
            return .string(value)
        case .boolean:
            return nil
        }
    }

    private func primitiveInteger(
        _ value: Int,
        scalarType: FormKitFieldDescriptor.ScalarType
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        switch scalarType {
        case .integer:
            return .integer(value)
        case .number:
            return .number(Double(value))
        default:
            return nil
        }
    }
}

private extension FormKitFieldDescriptor.PrimitiveValue {
    var isBlankString: Bool {
        guard case .string(let value) = self else {
            return false
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
