import Foundation

extension FormKitSession {
    var visibleArraySections: [FormKitRenderPlan.SectionDescriptor] {
        renderPlan.sections.filter { $0.isArraySection && $0.isVisible && $0.shouldSerialize }
            .sorted { $0.order < $1.order }
    }

    var visibleDynamicOptionsArrays: [FormKitRenderPlan.SectionDescriptor] {
        visibleArraySections.filter(\.usesDynamicOptions)
    }

    func isDynamicOptionsArrayItem(_ field: FormKitFieldDescriptor) -> Bool {
        field.isScalarArrayItem && arraySectionsByPointer[field.parentPointer]?.usesDynamicOptions == true
    }

    func missingDynamicOptionsArrays(in instance: FormKitJSONValue) -> [FormKitRenderPlan.SectionDescriptor] {
        visibleDynamicOptionsArrays.filter { section in
            guard let descriptor = section.arrayDescriptor, let parent = section.parentPointer,
                  instance.value(atPointer: parent)?.object != nil else { return false }
            guard let value = instance.value(atPointer: section.pointer) else { return section.isRequired }
            return value.array.map { $0.count < descriptor.minItems } ?? false
        }
    }

    func hasAnswer(for section: FormKitRenderPlan.SectionDescriptor, in instance: FormKitJSONValue) -> Bool {
        guard section.usesDynamicOptions, section.isVisible, section.shouldSerialize,
              let descriptor = section.arrayDescriptor,
              let values = instance.value(atPointer: section.pointer)?.array,
              values.count >= descriptor.minItems else { return false }
        if values.isEmpty {
            let supplied = includesHiddenToolFields ? suppliedInstance : initialInstance
            return supplied?.value(atPointer: section.pointer)?.array != nil || touchedArrayIDs.contains(section.id)
        }
        return orderedFields.contains { field in
            field.isScalarArrayItem && field.parentPointer == section.pointer && hasAnswer(for: field)
        }
    }
}
