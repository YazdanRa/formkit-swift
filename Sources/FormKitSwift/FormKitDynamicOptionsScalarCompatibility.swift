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
        field.usesDynamicOptions || (field.isScalarArrayItem
            && arraySectionsByPointer[field.parentPointer]?.usesDynamicOptions == true)
    }
}
