import Foundation

/// A person supplied by the host, with a stable identifier used as the form value.
public struct FormKitPersonOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}
