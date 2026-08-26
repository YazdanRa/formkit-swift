import Foundation
import JSONSchema

public extension FormKitSession {
    func arrayValue(for section: FormKitRenderPlan.SectionDescriptor) -> [FormKitJSONValue]? {
        makeInstanceJSONValue().value(atPointer: section.pointer)?.array
    }

    func setArrayValue(
        _ value: [FormKitJSONValue]?,
        for section: FormKitRenderPlan.SectionDescriptor
    ) {
        replaceArrayValue(value, for: section)
    }

    private func replaceArrayValue(
        _ value: [FormKitJSONValue]?,
        for section: FormKitRenderPlan.SectionDescriptor,
        preserving valueSources: [String: FormKitToolValueSource]? = nil
    ) {
        guard renderPlan.sections.contains(section),
              section.arrayDescriptor != nil,
              section.shouldSerialize,
              !section.isDisabled
        else {
            return
        }

        var instance = makeInstanceJSONValue()
        if let value {
            insert(.array(value), at: section.pointer, into: &instance)
        } else {
            instance = removingValue(from: instance, path: Self.tokens(from: section.pointer))
        }

        let descendantPrefix = "\(section.pointer)/"
        touchedFieldIDs = touchedFieldIDs.filter {
            $0 != section.pointer && !$0.hasPrefix(descendantPrefix)
        }
        toolValueSourceOverrides = toolValueSourceOverrides.filter {
            $0.key != section.pointer && !$0.key.hasPrefix(descendantPrefix)
        }
        let descendantArrayIDs = Set(
            renderPlan.sections
                .filter { $0.pointer == section.pointer || $0.pointer.hasPrefix(descendantPrefix) }
                .map(\.id)
        )
        touchedArrayIDs.subtract(descendantArrayIDs)
        fieldErrors = fieldErrors.filter {
            $0.key != section.pointer && !$0.key.hasPrefix(descendantPrefix)
        }
        arrayErrors = arrayErrors.filter { !descendantArrayIDs.contains($0.key) }
        if let firstInvalidFieldID,
           firstInvalidFieldID == section.pointer || firstInvalidFieldID.hasPrefix(descendantPrefix)
        {
            self.firstInvalidFieldID = nil
        }
        if value != nil {
            touchedArrayIDs.insert(section.id)
        }

        applyInstance(instance)

        let nextValueSources = valueSources ?? toolValueSources(
            afterReplacingArrayIn: instance,
            descendantPrefix: descendantPrefix
        )
        let visibleValuePointers = Set(
            orderedFields.compactMap { primitiveValue(for: $0) == nil ? nil : $0.pointer }
        )
        toolValueSourceOverrides.merge(
            nextValueSources.filter { visibleValuePointers.contains($0.key) }
        ) { _, new in new }
    }

    private func toolValueSources(
        afterReplacingArrayIn instance: FormKitJSONValue,
        descendantPrefix: String
    ) -> [String: FormKitToolValueSource] {
        Dictionary(uniqueKeysWithValues: orderedFields.compactMap { field in
            guard field.pointer.hasPrefix(descendantPrefix),
                  primitiveValue(for: field) != nil
            else {
                return nil
            }
            let suppliedValue = instance.value(at: JSONPointer(from: field.pointer))
            let hasUsableSuppliedValue = suppliedValue.flatMap { rawValue in
                primitiveValue(
                    from: rawValue,
                    scalarType: field.scalarType,
                    allowsNull: field.allowsNull,
                    normalizesEmptyText: !field.enumOptions.contains {
                        jsonValue(from: $0.value) == rawValue
                    }
                )
            } != nil
            let source: FormKitToolValueSource = if hasUsableSuppliedValue {
                .sessionEdit
            } else if fieldValues[field.id] != nil {
                .defaultValue
            } else {
                toolValueSource(for: field) ?? .defaultValue
            }
            return (field.pointer, source)
        })
    }

    func appendArrayRow(to section: FormKitRenderPlan.SectionDescriptor) {
        guard !section.isDisabled,
              let arrayDescriptor = section.arrayDescriptor
        else {
            return
        }

        if let maxItems = arrayDescriptor.maxItems,
           arrayDescriptor.rows.count >= maxItems
        {
            return
        }

        touchedArrayIDs.insert(section.id)
        var instance = makeInstanceJSONValue()
        let nextIndex = arrayValue(at: arrayDescriptor.pointer, in: instance)?.count ?? 0
        insert(
            arrayDescriptor.newItemPlaceholder,
            at: "\(arrayDescriptor.pointer)/\(nextIndex)",
            into: &instance
        )
        applyInstance(instance)
        let newRowPrefix = "\(arrayDescriptor.pointer)/\(nextIndex)"
        for field in orderedFields where
            (field.pointer == newRowPrefix || field.pointer.hasPrefix("\(newRowPrefix)/")) &&
            primitiveValue(for: field) != nil
        {
            toolValueSourceOverrides[field.pointer] = .defaultValue
        }
    }

    func removeArrayRow(
        _ row: FormKitArrayRowDescriptor,
        from section: FormKitRenderPlan.SectionDescriptor
    ) {
        guard !section.isDisabled,
              let arrayDescriptor = section.arrayDescriptor
        else {
            return
        }

        if arrayDescriptor.rows.count <= arrayDescriptor.minItems {
            return
        }

        guard var array = arrayValue(for: section),
              array.indices.contains(row.index)
        else {
            return
        }

        let valueSources = arrayDescriptor.rows
            .filter { $0.index != row.index }
            .reduce(into: [String: FormKitToolValueSource]()) { sources, existingRow in
                let nextIndex = existingRow.index > row.index ? existingRow.index - 1 : existingRow.index
                let nextRowPointer = "\(arrayDescriptor.pointer)/\(nextIndex)"
                for field in orderedFields where
                    field.pointer == existingRow.pointer ||
                    field.pointer.hasPrefix("\(existingRow.pointer)/")
                {
                    guard let source = toolValueSource(for: field) else {
                        continue
                    }
                    let suffix = field.pointer.dropFirst(existingRow.pointer.count)
                    sources["\(nextRowPointer)\(suffix)"] = source
                }
            }
        array.remove(at: row.index)
        replaceArrayValue(
            array,
            for: section,
            preserving: valueSources
        )
    }
}
