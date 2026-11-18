import Foundation

/// One page from the host's options search.
public struct FormKitDynamicOptionsPage: Equatable, Sendable {
    public let options: [FormKitDynamicOption]
    public let nextCursor: String?

    public init(options: [FormKitDynamicOption], nextCursor: String? = nil) {
        self.options = options
        self.nextCursor = nextCursor
    }
}

/// The host owns lookup, authorization, networking, and cursor interpretation.
public typealias FormKitDynamicOptionsProvider = @MainActor (
    _ search: String, _ cursor: String?
) async throws -> FormKitDynamicOptionsPage
