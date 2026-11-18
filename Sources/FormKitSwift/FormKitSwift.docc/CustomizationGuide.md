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

Stock text input titles, normal editable outlines, and validation messages use the platform's primary foreground color for legibility. Validation icons and error outlines use the configured status colors. `secondaryText` continues to style supporting text and custom input captions.

For file and signature inputs, provide a host upload handler through ``FormKitOptions/uploadHandler``. See <doc:SchemaDrivenComponents>.

## Dynamic Options

Annotate a string or an array of strings with `"x-formkit-ui-component": "dynamic-options"`. Supply `FormKitOptions.dynamicOptions` to resolve a host data source for each actual field or array pointer. The registry supplies scalar and array bindings, schema limits, locked state, and validation presentation. A host field or array override still takes precedence; an incompatible schema or unresolved source retains the standard input. Fixed schema enums continue to use `line-options-choice`.

```swift
FormKitView(
    session: session,
    options: FormKitOptions(dynamicOptions: { context in
        FormKitDynamicOptionsSource(
            savedOptions: directory.cachedOptions(for: context.selectedIDs),
            provider: { search, cursor in
                try await directory.options(
                    at: context.pointer,
                    search: search,
                    cursor: cursor
                )
            }
        )
    })
)
.id(catalogIdentity)
```

The source factory runs during rendering and should return cached presentation data and a provider without starting work. Lookup starts when the picker opens. The provider owns authorization, networking, search, pagination, caching and any selected-ID hydration; `context.selectedIDs` includes saved identifiers outside the current page. Supply the source's optional `canSelect` callback to recheck current host eligibility when adding an identifier, including when permissions change while the sheet is open. Existing identifiers can still be removed or cleared. No URL or transport is defined by the schema. Different pointers can resolve unrelated sources such as contacts and equipment. The context also exposes the existing field or array-section component context.

An option contains an opaque `id`, visible `label` and optional `detail`. Use detail for supporting text such as a company name or a readable identifier. Rows, accessible labels and selected summaries use the same detail. Duplicate labels without detail use the opaque identifier as a fallback. Only identifiers enter the selection binding. Learned labels survive closing and reopening; supply saved labels through `savedOptions` for offline presentation, and scope the view identity to the form and catalog so cached labels belong to that context.

For custom presentation, use `FormKitDynamicOptionsPicker` directly with `FormKitDynamicSelection.single($selectedID)` or `.multiple($selectedIDs)`. Pass schema `maxItems` as `maximumSelectionCount`. At the limit additional options are disabled while selected options can still be removed. Existing oversized selections remain intact. Selection writes identifiers immediately; Done closes the sheet. Required multiple selection keeps its last identifier. Requiredness and validity remain schema-owned.

Opening, loading, or failing to resolve a saved identifier never writes selection. Optional clearing writes nil for a scalar or an empty array for multiple selection. The registry emits explicit null for a nullable scalar, omits an optional nonnullable scalar, and emits an empty array for multiple selection. Untouched absence stays absent. Direct picker users own that serialization mapping. Previously saved identifiers stay selected when absent from results or when lookup fails.
