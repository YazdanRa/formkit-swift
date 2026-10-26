import FormKitSwift
import SwiftUI

struct SectionPagesDemoView: View {
    @State private var session: FormKitSession
    @State private var navigator: FormKitPageNavigator
    @State private var lastUserNavigation = "none"

    init() {
        let session = FormKitRenderer().makeFormSession(schemaJSON: DemoSchemas.sectionPagesSchema)
        _session = State(initialValue: session)
        _navigator = State(initialValue: FormKitPageNavigator(session: session))
    }

    var body: some View {
        NavigationStack {
            FormKitView(session: session, pageNavigator: navigator)
                .navigationTitle("Room Inspection")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Text(lastUserNavigation)
                            .accessibilityIdentifier("demo_pages_last_user_navigation")
                        Spacer()
                        Button("Ask about lighting") {
                            navigator.revealField("#/electrical/lighting")
                        }
                        .accessibilityIdentifier("demo_pages_reveal_lighting")
                    }
                    .font(.footnote)
                    .padding()
                    .background(.bar)
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

#Preview {
    SectionPagesDemoView()
}
