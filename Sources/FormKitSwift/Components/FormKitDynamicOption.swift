import Foundation

/// An option supplied by the host, with a stable identifier used as the form value.
public struct FormKitDynamicOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    /// Optional host-supplied secondary display context.
    public let detail: String?

    public init(id: String, label: String, detail: String? = nil) {
        self.id = id
        self.label = label
        self.detail = detail
    }
}
