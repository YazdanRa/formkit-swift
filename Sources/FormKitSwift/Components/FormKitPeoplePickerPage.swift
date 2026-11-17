import Foundation

/// One page from the host's people search.
public struct FormKitPeoplePage: Equatable, Sendable {
    public let people: [FormKitPersonOption]
    public let nextCursor: String?

    public init(people: [FormKitPersonOption], nextCursor: String? = nil) {
        self.people = people
        self.nextCursor = nextCursor
    }
}

/// The host owns lookup, authorization, networking, and cursor interpretation.
public typealias FormKitPeopleProvider = @MainActor (
    _ search: String, _ cursor: String?
) async throws -> FormKitPeoplePage
