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
