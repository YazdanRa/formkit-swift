# FormKitSwift

> [!CAUTION]
> This project is still in early stages and under heavy development. Anything and everything can change. Most of the code is AI generated and hasn't been fully reviewed yet!


FormKitSwift renders native SwiftUI forms from JSON Schema. It owns schema parsing, validation, form session state, serialization, generic tool-edit APIs, and customization hooks without depending on any host app runtime.

## Installation

Add the package to a SwiftPM or Xcode project:

```swift
.package(url: "https://github.com/YazdanRa/formkit-swift.git", from: "0.1.0")
```

Then depend on the product:

```swift
.product(name: "FormKitSwift", package: "formkit-swift")
```

## Quick Start

```swift
import FormKitSwift
import SwiftUI

struct ContentView: View {
    @State private var session = FormKitRenderer().makeFormSession(
        schemaJSON: """
        {
          "type": "object",
          "required": ["name"],
          "properties": {
            "name": { "type": "string", "title": "Name" },
            "active": { "type": "boolean", "title": "Active" }
          }
        }
        """,
        instanceJSON: #"{"name":"Ada","active":true}"#
    )

    var body: some View {
        FormKitView(session: session)
    }
}
```

You can also let the view create its own session:

```swift
FormKitView(schemaJSON: schemaJSON, instanceJSON: instanceJSON)
```

Use a controlled `FormKitSession` when the host app needs validation, current JSON, undo/redo, autosave, tool integration, or custom rendering state.

## Customization

`FormKitOptions` controls editing mode, validation behavior, conditional rendering behavior, labels, colors, field state, and component overrides:

```swift
FormKitView(
    session: session,
    options: FormKitOptions(
        mode: .editable,
        style: FormKitStyle(accent: .teal, cornerRadius: 8),
        fieldState: { field in
            changedPointers.contains(field.pointer) ? .changed : .normal
        }
    )
)
```

For deeper customization, set `FormKitOptions.components.field` or `sectionHeader` and render with package-owned context types. Future package-native components can be added behind these same options without leaking host app models.

## Generic Tool APIs

FormKitSwift exposes generic form-tool models, not assistant-specific APIs:

```swift
let context = session.makeToolContext(focusedPointers: ["/notes"])

let result = session.applyToolEdits(
    [
        FormKitToolEdit(
            pointer: "/summary",
            operation: .set,
            value: .string("Inspection complete.")
        )
    ],
    baseRevision: session.revision,
    lockedPointers: ["/notes"]
)
```

Host apps map `FormKitToolContext`, `FormKitToolEdit`, and `FormKitToolEditResult` to their own assistant, automation, or collaboration protocols.

## Supported Surface

The first public package pass focuses on the current renderer behavior:

- object sections and field ordering
- strings, numbers, integers, booleans, dates, date-times, enums, nullable scalar values
- arrays of scalar or object items
- defaults, required fields, validation messages, and serialization
- `$ref`, `allOf`, `oneOf`, `if`/`then`/`else`, `dependentSchemas`, and `dependentRequired` where supported by the renderer
- unsupported-state rendering for schemas outside the supported form surface

## Demo

The demo app lives in `Example/FormKitSwiftDemo`.

Development setup, demo build, and test instructions live in [CONTRIBUTING.md](CONTRIBUTING.md).
