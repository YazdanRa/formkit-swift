# Customization

``FormKitOptions`` keeps host customization package-owned and explicit.

```swift
let options = FormKitOptions(
    mode: .editable,
    validationBehavior: .revalidateAfterFirstAttempt,
    style: FormKitStyle(accent: .teal, cornerRadius: 8),
    fieldState: { field in
        changedPointers.contains(field.pointer) ? .changed : .normal
    }
)
```

Pass options into ``FormKitView``:

```swift
FormKitView(session: session, options: options)
```

Conditional behavior is a render-engine option, not a JSON Schema extension. Use standard JSON Schema conditionals to decide applicability, then key overrides by rendered JSON Pointer when one inactive field or section needs `.disable` or `.ignore`:

```swift
let session = FormKitRenderer(
    defaultConditionalRenderBehavior: .hide,
    conditionalRenderBehaviorOverrides: ["#/advancedNotes": .ignore]
).makeFormSession(schemaJSON: schemaJSON, instanceJSON: instanceJSON)
```

If the view owns the session, pass the same override map through ``FormKitOptions``. Override keys may use concrete rendered JSON Pointers such as `#/advancedNotes` or a `*` segment for repeated array rows, such as `#/entries/*/notes`.

## Field State

Use ``FormKitOptions/fieldState`` for host-owned visual state such as changed, locked, or normal fields. This keeps report models, assistant models, and synchronization state outside the package.

## Component Overrides

Use ``FormKitOptions/components`` to replace field or section-header rendering with package-owned context types:

```swift
FormKitOptions(
    components: FormKitComponents(
        field: { context in
            AnyView(
                VStack(alignment: .leading) {
                    Text(context.field.title)
                    Text(context.session.stringValue(for: context.field))
                }
            )
        }
    )
)
```

Component contexts intentionally expose ``FormKitSession`` and form descriptors, not host app models.
