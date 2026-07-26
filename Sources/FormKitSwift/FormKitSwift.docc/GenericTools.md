# Generic Tools

FormKitSwift exposes generic tool context and edit APIs so host apps can attach assistants, automations, scripts, or collaboration systems without leaking those systems into the package.

Build context from the visible render plan:

```swift
let context = session.makeToolContext(focusedPointers: ["/notes"])
```

`focusedPointers` marks those fields as locked in the generated context so a tool can avoid proposing edits to them. Pass the same protected pointers as `lockedPointers` when applying edits to enforce the lock.

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

## Edit Contract

Tool pointers omit the descriptor's leading `#`. Set edits require a value. Clear edits apply the same nullable and empty-value rules as stock controls.

Pass `baseRevision` to reject an entire stale batch after another mutation changes the session. Pass `lockedPointers` to protect fields owned by the user or another workflow. In a current batch, invalid edits are rejected individually while valid sibling edits can still apply. Rejections are reported in ``FormKitToolEditResult/rejectedEdits``.

The returned context is refreshed after the batch, so it is the appropriate input to the next tool call.

## Host Boundary

The package does not know about OpenAI, Assist, telemetry, persistence, or app runtime sessions. Host apps translate their own tool contracts to and from ``FormKitToolContext``, ``FormKitToolEdit``, and ``FormKitToolEditResult``.
