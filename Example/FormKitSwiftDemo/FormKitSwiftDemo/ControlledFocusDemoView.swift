import FormKitSwift
import SwiftUI

struct ControlledFocusDemoView: View {
    @State private var focusedFieldID: String?
    @State private var session: FormKitSession

    init(showsArray: Bool = false) {
        _session = State(
            initialValue: FormKitRenderer().makeFormSession(
                schemaJSON: showsArray ? Self.arraySchema : Self.focusSchema,
                instanceJSON: showsArray ? Self.arrayInstance : Self.focusInstance
            )
        )
    }

    var body: some View {
        FormKitView(session: session, focusedFieldID: $focusedFieldID)
            .safeAreaInset(edge: .top) {
                VStack {
                    HStack {
                        Button("Focus Site") {
                            focusedFieldID = "#/site"
                        }
                        .accessibilityIdentifier("demo_focus_site")

                        Button("Focus Temperature") {
                            focusedFieldID = "#/temperature"
                        }
                        .accessibilityIdentifier("demo_focus_temperature")

                        Button("Clear Focus") {
                            focusedFieldID = nil
                        }
                        .accessibilityIdentifier("demo_clear_focus")
                    }

                    Text(focusedFieldID ?? "none")
                        .accessibilityIdentifier("demo_focus_value")

                    Text(session.currentInstanceJSON)
                        .accessibilityIdentifier("demo_instance_json")
                }
                .padding()
                .background(.bar)
            }
    }

    private static let focusSchema = """
    {
      "type": "object",
      "properties": {
        "site": { "type": "string", "title": "Site" },
        "status": {
          "type": "string",
          "title": "Status",
          "enum": ["Draft", "Complete"]
        },
        "attachment": {
          "type": "string",
          "format": "uri",
          "title": "Attachment",
          "x-formkit-ui-component": "file-field"
        },
        "temperature": { "type": "number", "title": "Temperature" },
        "inspector": { "type": "string", "title": "Inspector" }
      }
    }
    """

    private static let focusInstance = """
    {
      "site": "North Yard",
      "status": "Draft",
      "inspector": "Ada"
    }
    """

    private static let arraySchema = """
    {
      "type": "object",
      "properties": {
        "notes": {
          "type": "array",
          "title": "Notes",
          "items": { "type": "string", "title": "Note" }
        }
      }
    }
    """

    private static let arrayInstance = """
    {
      "notes": ["First", "Second"]
    }
    """
}
