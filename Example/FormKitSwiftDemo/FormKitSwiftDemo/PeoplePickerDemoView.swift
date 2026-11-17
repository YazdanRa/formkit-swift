import FormKitSwift
import SwiftUI

struct PeoplePickerDemoView: View {
    @State private var issuedTo: String? = "company-contact:saved"
    @State private var assignedTo: [String] = []
    @State private var isLocked = false

    private let contacts = [
        FormKitPersonOption(id: "company-contact:101", displayName: "Alex Morgan"),
        FormKitPersonOption(id: "company-contact:102", displayName: "Alex Morgan"),
        FormKitPersonOption(id: "company-contact:103", displayName: "Jamie Patel")
    ]
    private let members = [
        FormKitPersonOption(id: "company-user:101", displayName: "Alex Morgan"),
        FormKitPersonOption(id: "company-user:102", displayName: "Casey Chen"),
        FormKitPersonOption(id: "company-user:103", displayName: "Jordan Smith")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Issued to") {
                    FormKitPeoplePicker(
                        title: "Issued to",
                        selection: .single($issuedTo),
                        savedPeople: [.init(id: "company-contact:saved", displayName: "Saved contact")],
                        isEditingLocked: isLocked,
                        provider: { search, cursor in try await page(contacts, search: search, cursor: cursor) }
                    )
                    .accessibilityIdentifier("demo_issued_to_picker")
                }
                Section("Assigned to") {
                    FormKitPeoplePicker(
                        title: "Assigned to",
                        selection: .multiple($assignedTo),
                        isRequired: ProcessInfo.processInfo.arguments.contains("-PEOPLE_REQUIRED"),
                        isEditingLocked: isLocked,
                        provider: { search, cursor in try await page(members, search: search, cursor: cursor) }
                    )
                    .accessibilityIdentifier("demo_assigned_to_picker")
                }
                Section("Saved identifiers") {
                    Text(issuedTo ?? "none").accessibilityIdentifier("demo_issued_to_value")
                    Text(assignedTo.joined(separator: ",")).accessibilityIdentifier("demo_assigned_to_value")
                }
            }
            .navigationTitle("Project people")
        }
    }

    private func page(
        _ people: [FormKitPersonOption],
        search: String,
        cursor: String?
    ) async throws -> FormKitPeoplePage {
        await Task.yield()
        if ProcessInfo.processInfo.arguments.contains("-PEOPLE_LOCK_ON_LOAD") {
            isLocked = true
        }
        if ProcessInfo.processInfo.arguments.contains("-PEOPLE_LOOKUP_FAILS") {
            throw DemoLookupError.unavailable
        }
        let matches = people.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
        let offset = Int(cursor ?? "") ?? 0
        let end = min(offset + 2, matches.count)
        return FormKitPeoplePage(
            people: Array(matches.dropFirst(offset).prefix(2)),
            nextCursor: end < matches.count ? String(end) : nil
        )
    }

    private enum DemoLookupError: Error {
        case unavailable
    }
}
