import Foundation
import JSONSchema

extension FormKitSession {
    func toolArrayFields(
        for sections: [FormKitRenderPlan.SectionDescriptor],
        in instance: FormKitJSONValue,
        focusedPointers: Set<String>
    ) -> [FormKitToolField] {
        sections.map { section in
            FormKitToolField(
                pointer: publicToolPointer(for: section.pointer), title: section.title, type: "array",
                isRequired: section.isRequired, isVisible: section.isVisible,
                valueSource: toolArrayValueSource(for: section, in: instance),
                description: section.description,
                isLocked: !isToolArrayEditable(section) || isToolArrayLocked(section, by: focusedPointers),
                validationMessages: errorMessages(for: section),
                minItems: section.arrayDescriptor?.minItems, maxItems: section.arrayDescriptor?.maxItems
            )
        }
    }

    func applyToolArrayEdit(
        _ edit: FormKitToolEdit,
        to section: FormKitRenderPlan.SectionDescriptor,
        lockedPointers: Set<String>
    ) -> ToolEditApplicationOutcome {
        guard isToolArrayEditable(section),
              let descriptor = section.arrayDescriptor
        else {
            return rejected(edit, reason: "field_not_visible",
                            message: "The requested field is not currently visible or editable.")
        }
        guard !isToolArrayLocked(section, by: lockedPointers) else {
            return rejected(edit, reason: "field_locked", message: "The requested field is locked.")
        }

        let values: [FormKitJSONValue]
        switch edit.operation {
        case .set:
            guard let value = edit.value else {
                return rejected(edit, reason: "missing_value", message: "A set operation requires a value.")
            }
            guard case .array(let items) = value, items.allSatisfy({ $0.string != nil }) else {
                return rejected(edit, reason: "type_mismatch", message: "This field requires an array of strings.")
            }
            values = items
        case .clear:
            values = []
        }
        guard values.count >= descriptor.minItems,
              descriptor.maxItems.map({ values.count <= $0 }) ?? true
        else {
            return rejected(edit, reason: "invalid_count", message: "The array must respect its item-count bounds.")
        }
        if edit.operation == .clear {
            let instance = makeInstanceJSONValue()
            if instance.value(atPointer: section.pointer) == .array([]),
               toolArrayValueSource(for: section, in: instance) != .defaultValue
            {
                return rejected(edit, reason: "no_change", message: "The field is already empty.")
            }
        }

        setArrayValue(values, for: section)
        return .applied(FormKitToolEdit(
            pointer: publicToolPointer(for: section.pointer), operation: edit.operation,
            value: edit.operation == .set ? .array(values) : nil
        ))
    }

    func isToolArrayLocked(_ section: FormKitRenderPlan.SectionDescriptor, by pointers: Set<String>) -> Bool {
        let parent = normalizedToolPointer(section.pointer)
        return pointers.contains { $0 == parent || $0.hasPrefix(parent + "/") || parent.hasPrefix($0 + "/") }
    }

    func isToolArrayEditable(_ section: FormKitRenderPlan.SectionDescriptor) -> Bool {
        section.conditionalState == .active && section.isVisible && section.shouldSerialize && !section.isDisabled
    }

    func isUnavailableToolArrayItem(_ field: FormKitFieldDescriptor) -> Bool {
        guard isDynamicOptionsArrayItem(field), let section = arraySectionsByPointer[field.parentPointer] else {
            return false
        }
        return field.isConditionallyInactive || !isToolArrayEditable(section)
    }

    func isToolFieldLocked(_ field: FormKitFieldDescriptor, by pointers: Set<String>) -> Bool {
        let pointer = normalizedToolPointer(field.pointer)
        return pointers.contains(pointer) || (isDynamicOptionsArrayItem(field) && pointers.contains {
            pointer.hasPrefix($0 + "/")
        })
    }

    func toolArrayValueSource(
        for section: FormKitRenderPlan.SectionDescriptor,
        in instance: FormKitJSONValue
    ) -> FormKitToolValueSource? {
        guard instance.value(atPointer: section.pointer)?.array != nil else { return nil }
        let sources = orderedFields.filter {
            $0.isScalarArrayItem && $0.parentPointer == section.pointer
        }.compactMap { toolValueSource(for: $0) }
        // Adding a generated row does not confirm its default identifier.
        if sources.contains(.defaultValue) {
            return .defaultValue
        }
        if touchedArrayIDs.contains(section.id) || sources.contains(.sessionEdit) {
            return .sessionEdit
        }
        let supplied = includesHiddenToolFields ? suppliedInstance : initialInstance
        if supplied?.value(atPointer: section.pointer)?.array != nil {
            return .initialInstance
        }
        return .defaultValue
    }

    func orderedToolFields(_ fields: [FormKitToolField]) -> [FormKitToolField] {
        let fieldsByPointer = Dictionary(uniqueKeysWithValues: fields.map { ($0.pointer, $0) })
        let sectionsByPointer = Dictionary(uniqueKeysWithValues: renderPlan.sections.map { ($0.pointer, $0) })
        var result: [FormKitToolField] = []
        var included: Set<String> = []
        func append(at pointer: String) {
            if let field = fieldsByPointer[publicToolPointer(for: pointer)], included.insert(field.pointer).inserted {
                result.append(field)
            }
            guard let section = sectionsByPointer[pointer] else { return }
            if let array = section.arrayDescriptor {
                for row in array.rows {
                    append(at: row.pointer)
                }
            } else {
                for property in section.propertyOrder {
                    let suffix = JSONPointer.pointerString(from: [property]).dropFirst()
                    append(at: pointer + String(suffix))
                }
            }
        }
        append(at: "#")
        return result + fields.filter { !included.contains($0.pointer) }
    }

    func toolSummary(
        for fields: [FormKitToolField],
        currentValues: [String: FormKitJSONValue]
    ) -> String {
        let arrayItemPointers = Set(orderedFields.filter(isDynamicOptionsArrayItem)
            .map(\.pointer).map(publicToolPointer(for:)))
        let missingRequiredTitles = fields.compactMap { field -> String? in
            guard field.type != "array", field.isVisible, field.isRequired,
                  !arrayItemPointers.contains(field.pointer)
            else {
                return nil
            }
            if case .string(let value) = currentValues[field.pointer],
               value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               self.field(forToolPointer: field.pointer).map({ !preservesDynamicOptionID(for: $0) }) ?? true
            {
                return field.title
            }
            return currentValues[field.pointer] == nil ? field.title : nil
        } + missingDynamicOptionsArrays(in: makeInstanceJSONValue()).map(qualifiedTitle(for:))
        return missingRequiredTitles.isEmpty
            ? "All currently visible required fields are filled."
            : "Missing required fields: \(missingRequiredTitles.joined(separator: ", "))."
    }
}
