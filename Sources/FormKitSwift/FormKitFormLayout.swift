import Foundation

/// Form-level layouts a schema can request with the root `x-formkit-layout` annotation.
public enum FormKitFormLayout: String, Sendable, Equatable, CaseIterable {
    /// Every field on one scrolling form. This is the default.
    case scroll

    /// `"section-pages"`: one top-level object section per page, with a summary page after the last one.
    case sectionPages = "section-pages"

    /// The root schema annotation that selects a layout.
    public static let schemaKey = "x-formkit-layout"

    /// Reads an `x-formkit-layout` value. Unknown or missing values keep ``scroll``.
    public init(schemaValue: String?) {
        let normalized = schemaValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = normalized.flatMap(Self.init(rawValue:)) ?? .scroll
    }
}
