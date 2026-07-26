# Customization

``FormKitOptions`` keeps host customization package-owned and explicit.

```swift
let options = FormKitOptions(
    mode: .editable,
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

For an injected session, configure validation and conditional rendering when creating the session. When ``FormKitView`` owns the session, set them in ``FormKitOptions``.

Conditional behavior is a render-engine option, not a JSON Schema extension. Use standard JSON Schema conditionals to decide applicability, then key overrides by rendered JSON Pointer when one inactive field or section needs `.disable` or `.ignore`:

```swift
let session = FormKitRenderer(
    defaultConditionalRenderBehavior: .hide,
    conditionalRenderBehaviorOverrides: ["#/advancedNotes": .ignore]
).makeFormSession(schemaJSON: schemaJSON, instanceJSON: instanceJSON)
```

If the view owns the session, pass the same override map through ``FormKitOptions``. Override keys may use concrete rendered JSON Pointers such as `#/advancedNotes` or a `*` segment for repeated array rows, such as `#/entries/*/notes`.

Inactive conditional content follows one of three behaviors:

- ``FormKitConditionalRenderBehavior/hide`` removes it from the view and serialized instance.
- ``FormKitConditionalRenderBehavior/disable`` keeps it visible and read-only but removes it from the serialized instance.
- ``FormKitConditionalRenderBehavior/ignore`` keeps it visible, editable, and serialized.

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

## Input and Array Overrides

Replace only the stock input while keeping FormKitSwift's label, description, validation messages, and field layout:

```swift
FormKitOptions(
    components: FormKitComponents(
        fieldInput: { context in
            guard context.field.uiComponent?.rawValue == "rating" else {
                return nil
            }
            return AnyView(
                Stepper(
                    value: Binding(
                        get: { Int(context.session.stringValue(for: context.field)) ?? 0 },
                        set: { context.session.setStringValue(String($0), for: context.field) }
                    ),
                    in: 0 ... 5,
                    label: { EmptyView() }
                )
                .accessibilityLabel(context.field.title)
            )
        },
        arraySection: { context in
            // Return nil to use a package-native or stock array control.
            nil
        }
    )
)
```

Host overrides run before package-native component selection. Use an entire `field` override only when the host also intends to own field layout and error presentation.

## Editing and Labels

Set ``FormKitMode/readOnly`` to preserve the rendered form while locking mutations. Use ``FormKitLabels`` for host-provided control text and ``FormKitStyle`` for colors and spacing.

For file and signature inputs, provide a host upload handler through ``FormKitOptions/uploadHandler``. See <doc:SchemaDrivenComponents>.
