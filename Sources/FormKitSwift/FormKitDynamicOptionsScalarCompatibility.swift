enum FormKitDynamicOptionsScalarCompatibility {
    static func supports(
        component: FormKitUIComponent?,
        scalarType: FormKitFieldDescriptor.ScalarType,
        hasValueConstraint: Bool
    ) -> Bool {
        component == .dynamicOptions && scalarType == .string && !hasValueConstraint
    }
}

extension FormKitFieldDescriptor {
    var usesDynamicOptions: Bool {
        FormKitDynamicOptionsScalarCompatibility.supports(
            component: uiComponent, scalarType: scalarType, hasValueConstraint: isEnum || isConstant
        )
    }
}

extension FormKitSession {
    func preservesDynamicOptionID(for field: FormKitFieldDescriptor) -> Bool {
        field.usesDynamicOptions || isDynamicOptionsArrayItem(field)
    }
}

extension FormKitRenderPlan {
    func dynamicOptionsRowSeed(for field: FormKitFieldDescriptor) -> FormKitJSONValue? {
        guard field.usesDynamicOptions || field.isScalarArrayItem else { return nil }
        for section in sections where section.isArraySection {
            guard field.usesDynamicOptions || (section.usesDynamicOptions && field.parentPointer == section.pointer),
                  let row = section.arrayDescriptor?.rows.first(where: {
                      field.pointer == $0.pointer || field.pointer.hasPrefix($0.pointer + "/")
                  }) else { continue }
            let suffix = field.pointer.dropFirst(row.pointer.count)
            guard let value = row.placeholderValue.value(atPointer: "#" + suffix) else { continue }
            return value
        }
        return nil
    }
}
