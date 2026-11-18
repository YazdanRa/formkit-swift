import FormKitSwift
import SwiftUI

struct ExplicitChoicesDemoView: View {
    @State private var session: FormKitSession
    @State private var focusedFieldID: String?

    init() {
        _session = State(initialValue: Self.makeSession(instance: #"{"operator_name":"Example operator"}"#))
    }

    var body: some View {
        NavigationStack {
            FormKitView(session: session, focusedFieldID: $focusedFieldID)
                .id(ObjectIdentifier(session))
                .safeAreaInset(edge: .bottom) {
                    Text(session.currentInstanceJSON)
                        .font(.caption.monospaced())
                        .accessibilityIdentifier("demo_explicit_json")
                }
                .toolbar {
                    Button("Clear Focus") { focusedFieldID = nil }
                        .accessibilityIdentifier("demo_explicit_blur")
                    Button("Reopen") { session = Self.makeSession(instance: session.currentInstanceJSON) }
                        .accessibilityIdentifier("demo_explicit_reopen")
                }
                .navigationTitle("Required choices")
        }
    }

    private static func makeSession(instance: String) -> FormKitSession {
        let schema = ProcessInfo.processInfo.arguments.contains("-EXPLICIT_STOCK_PICKER")
            ? Self.schema.replacingOccurrences(of: #", "x-formkit-ui-component":"line-options-choice""#, with: "")
            : Self.schema
        return FormKitRenderer(requiresExplicitEnumSelection: true).makeFormSession(
            schemaJSON: schema, instanceJSON: instance
        )
    }

    private static let schema = #"""
    {
      "type":"object","required":["operator_name","zone"],
      "properties":{
        "operator_name":{"type":"string","title":"Operator","x-formkit-order":0},
        "zone":{"type":"string","title":"Workshop zone","enum":["North","South"],
          "x-formkit-order":1, "x-formkit-ui-component":"line-options-choice"}
      }
    }
    """#
}
