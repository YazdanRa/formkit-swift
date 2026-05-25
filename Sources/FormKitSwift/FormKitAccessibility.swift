enum FormKitAccessibility {
    static func fieldIdentifier(for field: FormKitFieldDescriptor) -> String {
        field.accessibilityIdentifier
    }
}
