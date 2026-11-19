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

Use `.clear` to select null for a nullable scalar. Clearing an active field's untouched null default records `.sessionEdit` without changing its value. An already supplied or confirmed null remains `no_change`.

### Whole Dynamic-Option Arrays

Compatible `dynamic-options` arrays of nonnullable plain strings also expose a parent tool field with `type = "array"`, including when absent or empty. Its `minItems` and `maxItems` describe collection cardinality, and `currentValues` contains the whole array when present. Existing indexed item fields remain available. Parent fields follow schema property order, independently of the currently displayed form page.

Use the existing operations to replace or clear a collection:

```swift
FormKitToolEdit(pointer: "/equipment", operation: .set,
                value: .array([.string("asset:1"), .string("asset:2")]))
FormKitToolEdit(pointer: "/equipment", operation: .clear)
```

Set requires an array containing only strings and respecting its current item-count bounds. IDs and their order remain literal. Clear deliberately writes `[]`; it is rejected when the minimum count is nonzero. Context reads never turn absence into an empty array. Item constraints continue through normal session validation.

An untouched array default, including `[]`, has source `.defaultValue`. Setting that same array explicitly confirms it as `.sessionEdit`. An array containing an unconfirmed generated item remains default-sourced. Initial values, explicit empty answers and confirmed replacements retain their provenance across unrelated edits.

Edits to these collections require the current schema section to be active, visible and editable, even with `includesHiddenToolFields`; retained indexed targets enforce the same activity and ancestor locks. Existing supplied hidden answers remain retained by the opted-in session. A lock on the parent or any indexed descendant blocks replacement. View-only read-only mode and ID authorization remain host responsibilities; callers must reject unauthorized edits or pass the appropriate pointer locks. Nullable outer arrays and nullable-item fallback arrays do not gain whole-array tool editing.

Date, time, and date-time fields also expose ``FormKitToolField/valueFormat``. Temporal set edits may use the documented local wall-clock form or an explicit-offset form. FormKit validates and normalizes those strings through the same date codec used by its controls; malformed or ambiguous local values are rejected with `invalid_format`.

Use ``FormKitSession/instanceJSONOmittingNonArrayDefaults`` when persistence must distinguish untouched renderer defaults from supplied or confirmed non-array values. It omits untouched default-sourced properties and optional object ancestors emptied by those omissions while retaining required objects, initial values, and session edits, including same-value confirmations. Arrays and all their descendants remain unchanged because FormKit cannot omit their defaults without losing authored container structure or array identity.

When a host knows that an untouched initial value represented an older default, call ``FormKitSession/rematerializeDefaultValue(for:)`` after the field becomes visible. The session replaces only that field with its current schema or required-control default and reports ``FormKitToolValueSource/defaultValue`` without disturbing unrelated edits or hidden values.

Pass `baseRevision` to reject an entire stale batch after another mutation changes the session. Pass `lockedPointers` to protect fields owned by the user or another workflow. In a current batch, invalid edits are rejected individually while valid sibling edits can still apply. Rejections are reported in ``FormKitToolEditResult/rejectedEdits``.

The returned context is refreshed after the batch, so it is the appropriate input to the next tool call.

## Host Boundary

The package does not know about OpenAI, Assist, telemetry, persistence, or app runtime sessions. Host apps translate their own tool contracts to and from ``FormKitToolContext``, ``FormKitToolEdit``, and ``FormKitToolEditResult``.
