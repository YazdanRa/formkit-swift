import FormKitSwift
import SwiftUI

struct PickerLayoutDemoView: View {
    var body: some View {
        FormKitView(
            schemaJSON: Self.schema,
            instanceJSON: """
            {"station":"Main gun","traverse":"Pass","elevation":"Pass","enabled":true,
             "date":null,"condition":"Failed"}
            """
        )
        .pickerStyle(.menu)
        .frame(width: 320)
        .environment(
            \.layoutDirection,
            ProcessInfo.processInfo.arguments.contains("-UITEST_RTL") ? .rightToLeft : .leftToRight
        )
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-UITEST_DARK") ? .dark : nil)
    }

    private static let schema = """
    {
      "type": "object",
      "required": ["station", "traverse", "elevation"],
      "properties": {
        "station": {
          "type": "string", "title": "Weapon Station", "x-formkit-order": 0,
          "enum": ["Main gun", "Secondary"]
        },
        "traverse": {
          "type": "string", "x-formkit-order": 1,
          "title": "Turret Traverse (360°) — Powered & Manual, Smooth, No Binding",
          "enum": ["Pass", "Requires further inspection before operation"]
        },
        "elevation": {
          "type": "string", "x-formkit-order": 2,
          "title": "Weapon Elevation / Depression — Full Travel to Limits",
          "enum": ["Pass", "Fail"]
        },
        "enabled": {
          "type": ["boolean", "null"], "x-formkit-order": 3,
          "title": "Stabilization System — Functional & Calibrated"
        },
        "date": {
          "type": ["string", "null"], "format": "date", "x-formkit-order": 4,
          "title": "Scheduled Inspection — Confirmed Date for Full System Review"
        },
        "condition": {
          "type": "string", "x-formkit-order": 5,
          "title": "Terrace or balcony clean and safe",
          "x-formkit-ui-component": "line-options-choice",
          "x-formkit-option-color-map": {"Pass": "#16A34A", "Failed": "#DC2626", "N/A": "#64748B"},
          "enum": ["Pass", "Failed", "N/A"]
        }
      }
    }
    """
}
