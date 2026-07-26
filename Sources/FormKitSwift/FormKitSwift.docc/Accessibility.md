# Accessibility

Stock FormKitSwift controls provide accessible labels, values, hints, Dynamic Type layouts, and minimum-size actions.

## Deterministic Identifiers

The stock root form uses `formkit_form`. Field and section identifiers derive from their full JSON Pointer so repeated rows remain distinct. Input controls, validation errors, array actions, upload rows, and signature actions add role-specific suffixes.

Use descriptor identifiers when host UI tests or surrounding views need to coordinate with a form:

```swift
let identifier = field.accessibilityIdentifier
```

## Custom Components

A full ``FormKitComponents/field`` override replaces the stock field wrapper, so the host owns its accessibility, focus, errors, and layout. A ``FormKitComponents/fieldInput`` override keeps the stock field presentation but owns the input's control semantics. Preserve:

- the schema-authored field or section title,
- descriptions and validation messages,
- disabled and read-only state,
- a minimum 44-point action target,
- Dynamic Type layouts without clipped labels,
- meaningful values and hints for custom gestures.

Use ``FormKitFieldComponentContext/errors`` and ``FormKitFieldComponentContext/isEditingLocked`` when recreating full field presentation.
