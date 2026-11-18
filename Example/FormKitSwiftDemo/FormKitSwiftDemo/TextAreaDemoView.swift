import FormKitSwift
import SwiftUI

struct TextAreaDemoView: View {
    @State private var session: FormKitSession
    @State private var focusedFieldID: String?

    init() {
        _session = State(initialValue: FormKitRenderer().makeFormSession(schemaJSON: Self.schema))
    }

    var body: some View {
        NavigationStack {
            FormKitView(session: session, focusedFieldID: $focusedFieldID)
                .id(ObjectIdentifier(session))
                .safeAreaInset(edge: .bottom) {
                    Text(session.currentInstanceJSON)
                        .font(.caption.monospaced())
                        .lineLimit(3)
                        .accessibilityIdentifier("demo_text_area_json")
                }
                .toolbar {
                    Button("Clear Focus") { focusedFieldID = nil }
                        .accessibilityIdentifier("demo_text_area_blur")
                    Button("Reopen") {
                        session = FormKitRenderer().makeFormSession(
                            schemaJSON: Self.schema,
                            instanceJSON: session.currentInstanceJSON
                        )
                    }
                    .accessibilityIdentifier("demo_text_area_reopen")
                }
                .navigationTitle("Narrative")
        }
    }

    private static let schema = #"""
    {
      "type":"object",
      "properties":{
        "subject":{"type":"string","title":"Subject","x-formkit-order":0},
        "description":{"type":"string","title":"Description","x-formkit-order":1,
          "x-formkit-ui-component":"text-area","maxLength":2000}
      }
    }
    """#
}
