enum FormKitAccessibility {
    static func fieldIdentifier(for field: FormKitFieldDescriptor) -> String {
        field.accessibilityIdentifier
    }

    static func sectionIdentifier(_ sectionID: String, fieldIDs: [String], showsHeader: Bool) -> String {
        guard !showsHeader else {
            return sectionID
        }
        guard let firstFieldID = fieldIDs.first else {
            return "formkit_display_block_footer:\(sectionID)"
        }
        return "formkit_display_block_group:\(sectionID):\(firstFieldID)"
    }
}
