import FormKitSwift
import SwiftUI

struct SectionPagesDemoView: View {
    /// A starting point for previews and screenshots: answers plus the page that opens.
    enum Scenario: String, CaseIterable {
        case fresh
        case needsAttention = "needs-attention"
        case inProgress = "in-progress"
        case lastPage = "last-page"
        case summary
        case complete

        /// Reads `-SECTION_PAGES_SCENARIO <name>` from the launch arguments.
        static var launchArgument: Scenario {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-SECTION_PAGES_SCENARIO"),
                  arguments.indices.contains(index + 1)
            else {
                return .fresh
            }
            return Scenario(rawValue: arguments[index + 1]) ?? .fresh
        }

        var instanceJSON: String? {
            switch self {
            case .fresh:
                return nil
            case .needsAttention:
                return #"{"roomNumber": 1204, "housekeeping": {"linens": "Failed", "bed": "Pass"}}"#
            case .inProgress, .lastPage, .summary:
                return """
                {"roomNumber": 1204,
                 "housekeeping": {"linens": "Failed", "linens_observation": "Torn pillowcase", "bed": "Pass"},
                 "equipment": {"doorLock": "Pass"}}
                """
            case .complete:
                return """
                {"roomNumber": 1204,
                 "housekeeping": {"linens": "Pass", "bed": "Pass"},
                 "equipment": {"doorLock": "Pass", "television": "N/A"},
                 "electrical": {"lighting": "Failed", "lighting_observation": "Bulb out by the desk"}}
                """
            }
        }

        var position: FormKitPagePosition {
            switch self {
            case .fresh, .needsAttention:
                return .page(0)
            case .inProgress:
                return .page(1)
            case .lastPage:
                return .page(2)
            case .summary, .complete:
                return .summary
            }
        }
    }

    @State private var session: FormKitSession
    @State private var navigator: FormKitPageNavigator
    @State private var lastUserNavigation = "none"
    /// Host controls the UI tests use to turn pages from outside the form and read page callbacks.
    private let showsHostControls: Bool

    init(scenario: Scenario = .fresh, showsHostControls: Bool = false) {
        self.showsHostControls = showsHostControls
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: DemoSchemas.sectionPagesSchema,
            instanceJSON: scenario.instanceJSON
        )
        let navigator = FormKitPageNavigator(session: session)
        switch scenario.position {
        case let .page(index):
            navigator.goToPage(index)
        case .summary:
            navigator.goToPage(scenario == .complete ? 2 : 1)
            navigator.openSummary()
        }
        _session = State(initialValue: session)
        _navigator = State(initialValue: navigator)
    }

    var body: some View {
        NavigationStack {
            FormKitView(session: session, pageNavigator: navigator)
                .navigationTitle("Room Inspection")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showsHostControls {
                        ToolbarItem(placement: .bottomBar) {
                            Text(lastUserNavigation)
                                .font(.footnote)
                                .accessibilityIdentifier("demo_pages_last_user_navigation")
                        }
                        ToolbarItem(placement: .bottomBar) {
                            Button("Ask about lighting") {
                                navigator.revealField("#/electrical/lighting")
                            }
                            .font(.footnote)
                            .accessibilityIdentifier("demo_pages_reveal_lighting")
                        }
                    }
                }
        }
        .onAppear {
            navigator.onUserNavigation = { position in
                switch position {
                case let .page(index):
                    lastUserNavigation = "page \(index)"
                case .summary:
                    lastUserNavigation = "summary"
                }
            }
        }
    }
}

#Preview("Fresh form") {
    SectionPagesDemoView(scenario: .fresh)
}

#Preview("Failed answer needs an observation") {
    SectionPagesDemoView(scenario: .needsAttention)
}

#Preview("Second section in progress") {
    SectionPagesDemoView(scenario: .inProgress)
}

#Preview("Last section") {
    SectionPagesDemoView(scenario: .lastPage)
}

#Preview("Summary with flagged and missing answers") {
    SectionPagesDemoView(scenario: .summary)
}

#Preview("Summary of a complete form") {
    SectionPagesDemoView(scenario: .complete)
}

#Preview("Dark mode") {
    SectionPagesDemoView(scenario: .inProgress)
        .preferredColorScheme(.dark)
}

#Preview("Accessibility text size") {
    SectionPagesDemoView(scenario: .inProgress)
        .dynamicTypeSize(.accessibility2)
}

#Preview("Right to left") {
    SectionPagesDemoView(scenario: .inProgress)
        .environment(\.layoutDirection, .rightToLeft)
}
