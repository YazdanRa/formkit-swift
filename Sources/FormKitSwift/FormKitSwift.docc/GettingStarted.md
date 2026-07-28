# Getting Started

Add FormKitSwift to a SwiftPM package:

```swift
dependencies: [
    .package(
        url: "https://github.com/YazdanRa/formkit-swift.git",
        from: "1.2.0"
    )
]
```

Add the library to the target that renders forms:

```swift
.product(name: "FormKitSwift", package: "formkit-swift")
```

The package supports iOS 18, macOS 15, and visionOS 2 or later.

## Supported Schema Surface

FormKitSwift supports object sections; string, email, URI, date, time, date-time, integer, number, and Boolean fields; enums and constants; nullable primitive unions; and arrays of scalar or object items. It resolves supported local references and composition or conditional keywords including `allOf`, `oneOf`, `if`/`then`/`else`, `dependentSchemas`, and `dependentRequired`.

Time-only fields use `{ "type": "string", "format": "time" }` and RFC 3339 full-time values such as `14:30:00Z`.

Remote references, nested arrays, schema-valued `additionalProperties`, and other unsupported render shapes produce explicit unsupported reasons instead of a partial editable form.

## Render a Controlled Form

Create a renderer, build a session from schema and instance JSON, and retain the session in the host view:

```swift
import FormKitSwift
import SwiftUI

struct EditorView: View {
    @State private var session = FormKitRenderer().makeFormSession(
        schemaJSON: schemaJSON,
        instanceJSON: instanceJSON
    )

    var body: some View {
        FormKitView(session: session)
    }
}
```

Read `session.currentInstanceJSON` to persist the current value and call `session.validate()` before submission.

### Coordinate Focus And Host State

Pass a binding when the host needs to dismiss a stock text field or protect the active field from an external workflow:

```swift
@State private var focusedFieldID: String?

FormKitView(
    session: session,
    focusedFieldID: $focusedFieldID
)
```

Binding values are ``FormKitFieldDescriptor/id`` values. Setting the binding to `nil` commits and dismisses the active stock text field. FormKit updates the binding as focus moves through stock text inputs. Custom inputs own their own focus behavior.

Observe ``FormKitSession/revision`` when the host needs to reconcile FormKit edits with undo history or persistence. A revision is a mutation signal, not proof that serialized data changed, so compare canonical JSON snapshots:

```swift
@State private var lastInstanceJSON = session.currentInstanceJSON

FormKitView(session: session)
    .onChange(of: session.revision) { _, _ in
        let currentInstanceJSON = session.currentInstanceJSON
        guard currentInstanceJSON != lastInstanceJSON else { return }
        defer { lastInstanceJSON = currentInstanceJSON }

        persist(currentInstanceJSON)
    }
```

When the host applies its own tool edits or replaces the session for undo/redo, update the retained baseline as part of that same logical operation to avoid recording it twice.

## Let the View Own the Session

Use the convenience initializer when the host view does not need to retain session state:

```swift
FormKitView(schemaJSON: schemaJSON, instanceJSON: "{}")
```

When `schemaJSON`, `instanceJSON`, or the render options change, this initializer rebuilds its owned session. Use a retained session when edits must survive those input changes.

Use a retained ``FormKitSession`` when you need:

- ``FormKitSession/currentInstanceJSON``
- validation through ``FormKitSession/validate()``
- undo/redo snapshots in the host app
- field state from external workflows
- generic tool context and edit application

FormKitSwift accepts compact missing-instance fallbacks such as `"{}"` and emits stable pretty-printed JSON from ``FormKitSession/currentInstanceJSON``.

## Validate

``FormKitValidationBehavior/revalidateAfterFirstAttempt`` validates on demand first, then revalidates after edits. For a controlled session, pass ``FormKitValidationBehavior/onDemandOnly`` to the renderer when only explicit calls to ``FormKitSession/validate()`` should update validation state:

```swift
let session = FormKitRenderer().makeFormSession(
    schemaJSON: schemaJSON,
    instanceJSON: instanceJSON,
    validationBehavior: .onDemandOnly
)
FormKitView(session: session)
```

When the view owns the session, set the behavior in ``FormKitOptions`` instead.

## Empty Values

FormKitSwift uses one empty-value contract across stock controls, session and tool mutations, initial instance values, and schema defaults:

- Empty or whitespace-only text becomes JSON `null` when the field allows null.
- A non-nullable text-backed field keeps its blank string so validation can report it; required non-nullable fields fail validation while blank.
- Stock text and numeric inputs do not add a separate value-state control.
- Optional nullable enum, Boolean, and date controls keep **Not Set** (the property is absent) distinct from **No Value** (the property is present as `null`).
- In the multiple-file component, a nullable `null` item is an empty upload slot. It does not consume file capacity and is replaced when an upload succeeds.

Explicit enum and `const` choices retain their schema-authored values.

## Handle Unsupported Schemas

The view displays unsupported schema reasons. Hosts that need an alternate flow can inspect the render plan before presenting it:

```swift
if session.renderPlan.isSupported {
    FormKitView(session: session)
} else {
    UnsupportedFormView(reasons: session.renderPlan.unsupportedReasons)
}
```
