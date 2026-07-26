# Getting Started

Create a renderer, build a session from schema and instance JSON, and pass the session to ``FormKitView``.

```swift
import FormKitSwift
import SwiftUI

let session = FormKitRenderer().makeFormSession(
    schemaJSON: schemaJSON,
    instanceJSON: instanceJSON
)
```

```swift
FormKitView(session: session)
```

Use the convenience initializer when the host view does not need to retain session state:

```swift
FormKitView(schemaJSON: schemaJSON, instanceJSON: "{}")
```

Use a retained ``FormKitSession`` when you need:

- ``FormKitSession/currentInstanceJSON``
- validation through ``FormKitSession/validate()``
- undo/redo snapshots in the host app
- field state from external workflows
- generic tool context and edit application

FormKitSwift accepts compact missing-instance fallbacks such as `"{}"` and emits stable pretty-printed JSON from ``FormKitSession/currentInstanceJSON``.

## Empty Values

FormKitSwift uses one empty-value contract across stock controls, session and tool mutations, initial instance values, and schema defaults:

- Empty or whitespace-only text becomes JSON `null` when the field allows null.
- A non-nullable text-backed field keeps its blank string so validation can report it; required non-nullable fields fail validation while blank.
- Optional nullable controls keep **Not Set** (the property is absent) distinct from **No Value** (the property is present as `null`).
- In the multiple-file component, a nullable `null` item is an empty upload slot. It does not consume file capacity and is replaced when an upload succeeds.

Explicit enum and `const` choices retain their schema-authored values.
