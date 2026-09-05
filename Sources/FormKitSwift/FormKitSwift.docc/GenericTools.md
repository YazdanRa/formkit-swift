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

## Supplying Answers For Hidden Fields

Hosts that capture multiple answers together can opt in with `FormKitRenderer(includesHiddenToolFields: true)`.
The session retains conditional field descriptors and includes hidden fields in tool context with `isVisible = false`.
The UI continues to honor `.hide`. Hosts should use visibility and requiredness to choose questions, rather than
restricting which clear user-supplied answers tools can apply. Disabled and locked fields remain protected.

Opted-in sessions accept validated edits to known hidden fields, including edits placed before a controlling answer
when the supplied value matches that hidden descriptor. When a controller changes a shared field's type or choices,
apply the controller first and use the refreshed descriptor. Active branch definitions remain authoritative. Initial and session-edited hidden values survive `currentInstanceJSON` and reopening; untouched
hidden defaults are omitted. Hidden arrays retain row positions using empty objects or null slots where needed,
without copying untouched default values into those rows. Hidden answers remain subject to the original JSON Schema validation rules.
The default renderer continues to expose and edit only visible fields.

## Edit Contract

Tool pointers omit the descriptor's leading `#`. Set edits require a value. Clear edits apply the same nullable and empty-value rules as stock controls.

Each ``FormKitToolField`` exposes an optional ``FormKitToolField/valueSource``. ``FormKitToolValueSource/initialInstance`` means the value was present when the session was created, ``FormKitToolValueSource/defaultValue`` means FormKit supplied a schema or required-control fallback, and ``FormKitToolValueSource/sessionEdit`` means the value was set or confirmed during the current session. A missing value has no source. Host apps can use this provenance without changing the effective values or ``FormKitSession/currentInstanceJSON``.

Date, time, and date-time fields also expose ``FormKitToolField/valueFormat``. Temporal set edits may use the documented local wall-clock form or an explicit-offset form. FormKit validates and normalizes those strings through the same date codec used by its controls; malformed or ambiguous local values are rejected with `invalid_format`.

Use ``FormKitSession/instanceJSONOmittingNonArrayDefaults`` when persistence must distinguish untouched renderer defaults from supplied or confirmed non-array values. It omits untouched default-sourced properties and optional object ancestors emptied by those omissions while retaining required objects, initial values, and session edits, including same-value confirmations. Arrays and all their descendants remain unchanged because FormKit cannot omit their defaults without losing authored container structure or array identity.

When a host knows that an untouched initial value represented an older default, call ``FormKitSession/rematerializeDefaultValue(for:)`` after the field becomes visible. The session replaces only that field with its current schema or required-control default and reports ``FormKitToolValueSource/defaultValue`` without disturbing unrelated edits or hidden values.

Pass `baseRevision` to reject an entire stale batch after another mutation changes the session. Pass `lockedPointers` to protect fields owned by the user or another workflow. In a current batch, invalid edits are rejected individually while valid sibling edits can still apply. Rejections are reported in ``FormKitToolEditResult/rejectedEdits``.

The returned context is refreshed after the batch, so it is the appropriate input to the next tool call.

## Host Boundary

The package does not know about OpenAI, Assist, telemetry, persistence, or app runtime sessions. Host apps translate their own tool contracts to and from ``FormKitToolContext``, ``FormKitToolEdit``, and ``FormKitToolEditResult``.
