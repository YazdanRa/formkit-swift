import Foundation

/// A person supplied by the host, with a stable identifier used as the form value.
public struct FormKitPersonOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    /// Optional host-supplied company or other non-sensitive display context.
    public let detail: String?

    public init(id: String, displayName: String, detail: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
    }
}
