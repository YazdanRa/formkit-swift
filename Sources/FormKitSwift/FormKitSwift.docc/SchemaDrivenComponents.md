# Schema-Driven Components

Select package-native file and signature inputs from the schema and connect their side effects to the host.

## Select a Component

Add `x-formkit-ui-component` to a compatible schema:

```json
{
  "type": "object",
  "properties": {
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

Unknown or incompatible annotations remain available on descriptors but fall back to stock rendering. Annotation values are trimmed and case-insensitive.

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
