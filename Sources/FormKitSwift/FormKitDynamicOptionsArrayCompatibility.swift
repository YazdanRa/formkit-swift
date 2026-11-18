enum FormKitDynamicOptionsArrayCompatibility {
    static func supports(
        component: FormKitUIComponent?,
        itemKind: FormKitArraySectionDescriptor.ItemKind,
        itemScalarType: FormKitFieldDescriptor.ScalarType?,
        itemAllowsNull: Bool,
        itemHasValueConstraint: Bool
    ) -> Bool {
        component == .dynamicOptions && itemKind == .scalar && itemScalarType == .string
            && !itemAllowsNull && !itemHasValueConstraint
    }
}

extension FormKitRenderPlan.SectionDescriptor {
    var offersEmptyDynamicOptionsSelection: Bool {
        usesDynamicOptions && arrayDescriptor?.minItems == 0 && arrayDescriptor?.rows.isEmpty == true
    }

    var usesDynamicOptions: Bool {
        guard let descriptor = arrayDescriptor else { return false }
        return FormKitDynamicOptionsArrayCompatibility.supports(
            component: uiComponent, itemKind: descriptor.itemKind,
            itemScalarType: descriptor.itemScalarType, itemAllowsNull: descriptor.itemAllowsNull,
            itemHasValueConstraint: descriptor.itemHasValueConstraint
        )
    }
}
