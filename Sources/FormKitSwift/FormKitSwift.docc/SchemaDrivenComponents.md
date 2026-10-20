# Schema-Driven Components

Select package-native choice, file, and signature inputs from the schema.

## Select a Component

Add `x-formkit-ui-component` to a compatible schema:

```json
{
  "type": "object",
  "properties": {
    "inspection": {
      "type": "string",
      "title": "Linens clean, pressed and free of visible wear",
      "enum": ["Pass", "Failed", "N/A"],
      "x-formkit-ui-component": "line-options-choice",
      "x-formkit-option-color-map": {"Pass": "#16A34A", "Failed": "#DC2626", "N/A": "#64748B"}
    },
    "license": {
      "type": "string",
      "format": "uri",
      "title": "License",
      "x-formkit-ui-component": "file-field"
    },
    "attachments": {
      "type": "array",
      "title": "Attachments",
      "maxItems": 5,
      "x-formkit-ui-component": "multiple-file-field",
      "items": {
        "type": "string",
        "format": "uri"
      }
    },
    "signature": {
      "type": "string",
      "format": "uri",
      "title": "Signature",
      "x-formkit-ui-component": "signature-pad"
    }
  }
}
```

Supported values and shapes are:

| Value | Compatible schema |
| --- | --- |
| `file-field` | Non-enum string field, normally with `format: "uri"` |
| `multiple-file-field` | Array of strings without item `enum` or `const`, normally with item `format: "uri"` |
| `signature-pad` | Non-enum string field, normally with `format: "uri"` |
| `line-options-choice` | Scalar enum field with 2–3 options, including any explicit `null` option |

Unknown or incompatible annotations remain available on descriptors but fall back to stock rendering. Annotation values are trimmed and case-insensitive.

`line-options-choice` displays one slim, rounded outline with 2–3 equal-width segments and dividers. Unselected segments have a neutral background; the selected segment uses a highlighted fill and a selected accessibility trait. At accessibility text sizes the segments stack vertically, keeping labels readable and touch targets at least 44 points. Larger enums use the standard picker. Selection changes respect Reduce Motion. Required fields show an asterisk and retain their selection; optional fields can be cleared by tapping the selected option again. Existing enum defaults, validation, and read-only behavior apply.

## Set Option Colors

Add `x-formkit-option-color-map` to the same field schema as `enum` and `x-formkit-ui-component`. The map keys are enum values, and the values are opaque sRGB hex colors:

```json
{
  "Pass": "#16A34A",
  "Failed": "#DC2626",
  "N/A": "#64748B"
}
```

- Only the selected segment uses its mapped color as a solid background, with contrasting black or white text. Unselected segments stay neutral.
- Colors accept `#RGB` or `#RRGGBB`, with uppercase or lowercase hex digits and optional surrounding whitespace. Alpha channels and named colors are unsupported.
- Missing entries, malformed colors, and non-string color values use the host's accent tint. Invalid cosmetic metadata does not invalidate the form.
- String keys match enum values exactly, including case and whitespace.

For other scalar enum values, use `true`, `false`, `null`, or numeric strings such as `1` and `1.5`; integral numbers use `1` rather than `1.0`. A string `"null"` and an explicit `null` share the key `"null"`.

Color metadata never changes submitted values and is available to custom renderers through ``FormKitFieldDescriptor/Choice/color``. This selection styling applies to `line-options-choice`; enums outside its 2–3 option limit use the standard picker.

## Provide an Upload Handler

The controls collect local input; the host uploads it and returns durable URLs:

```swift
let options = FormKitOptions(
    uploadHandler: { request in
        var uploadedAssets: [FormKitUploadedAsset] = []
        for item in request.items {
            let asset = try await assetStore.upload(
                source: item.source,
                name: item.name,
                mimeType: item.mimeType
            )
            uploadedAssets.append(FormKitUploadedAsset(
                url: asset.url.absoluteString,
                name: asset.name,
                mimeType: asset.mimeType,
                size: asset.size,
                id: asset.id
            ))
        }
        return uploadedAssets
    }
)

FormKitView(session: session, options: options)
```

``FormKitUploadRequest/component`` identifies the selected component. File pickers send ``FormKitUploadItem/Source/fileURL(_:)`` values and the signature pad sends PNG data through ``FormKitUploadItem/Source/data(_:)``.

Return nonblank URL strings in ``FormKitUploadedAsset``. A single-file or signature control uses the first returned URL. A multiple-file control consumes returned URLs in order up to `maxItems`.

If no handler is supplied, annotated fields render their existing values but their upload actions are disabled.

## Ownership and Concurrency

The handler executes on the main actor and may suspend while the host uploads. FormKitSwift applies returned URLs only if the field or array still has its original value, preventing an older upload from overwriting a newer edit.

The host owns authentication, retry policy, storage cleanup, and persistence. FormKitSwift owns local selection, upload progress and errors, schema limits, and session mutation.

## Override Component Rendering

Use ``FormKitComponents/fieldInput`` or ``FormKitComponents/arraySection`` to replace an annotated component. Return `nil` to delegate to package-native selection.
