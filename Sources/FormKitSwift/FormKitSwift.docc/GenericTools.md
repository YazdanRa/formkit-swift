# Generic Tools

FormKitSwift exposes generic tool context and edit APIs so host apps can attach assistants, automations, scripts, or collaboration systems without leaking those systems into the package.

Build context from the visible render plan:

```swift
let context = session.makeToolContext(focusedPointers: ["/notes"])
```

Apply edits with optional revision and pointer locking:

```swift
let result = session.applyToolEdits(
    [
        FormKitToolEdit(
            pointer: "/summary",
            operation: .set,
            value: .string("Ready for review.")
        )
    ],
    baseRevision: session.revision,
    lockedPointers: ["/notes"]
)
```

The result reports applied edits, rejected edits, validation messages, and refreshed context:

```swift
result.appliedEdits
result.rejectedEdits
result.context
```

## Host Boundary

The package does not know about OpenAI, Assist, telemetry, persistence, or app runtime sessions. Host apps translate their own tool contracts to and from ``FormKitToolContext``, ``FormKitToolEdit``, and ``FormKitToolEditResult``.
