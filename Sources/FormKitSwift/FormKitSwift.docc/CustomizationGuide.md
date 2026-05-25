# Customization

``FormKitOptions`` keeps host customization package-owned and explicit.

```swift
let options = FormKitOptions(
    mode: .editable,
    validationBehavior: .revalidateAfterFirstAttempt,
    defaultConditionalRenderBehavior: .hide,
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
