import Foundation

public struct FormKitUIComponent: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public static let fileField = FormKitUIComponent(rawValue: "file-field")
    public static let multipleFileField = FormKitUIComponent(rawValue: "multiple-file-field")
    public static let signaturePad = FormKitUIComponent(rawValue: "signature-pad")
    /// A searchable choice list populated by a host-provided data source.
    public static let dynamicOptions = FormKitUIComponent(rawValue: "dynamic-options")
    public static let lineOptionsChoice = FormKitUIComponent(rawValue: "line-options-choice")
}
