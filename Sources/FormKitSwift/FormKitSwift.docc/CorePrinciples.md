# Core Principles

Build forms from standards-based data contracts while keeping application concerns in the host.

## Keep the Schema Authoritative

JSON Schema defines the form's structure, constraints, defaults, and conditional applicability. FormKitSwift derives rendering and validation from the same document so the UI does not become a second, conflicting schema.

The `x-formkit-ui-component` extension selects a package-native input when JSON Schema alone cannot express the desired interaction. Conditional presentation remains renderer configuration rather than schema vocabulary.

## Preserve JSON Semantics

Missing, `null`, blank, and concrete values are distinct:

- A missing optional property is **Not Set**.
- An explicit JSON `null` is **No Value**.
- Blank text remains blank for non-nullable fields so validation can reject it.
- Empty text in a non-choice field becomes `null` when the field allows `null`.

Schema-authored blank enum and `const` choices remain concrete values. Form controls, session mutations, schema defaults, and generic tool edits follow this same contract.

## Keep State in the Session

``FormKitSession`` is the authoritative editable value, render plan, validation state, and revision. Retain it whenever the host needs to read serialized JSON, validate, coordinate edits, or preserve state across view updates.

## Keep Side Effects in the Host

The package renders forms but does not own persistence, authentication, networking, or storage. For example, stock upload controls collect a file or signature and send a ``FormKitUploadRequest`` to a host-provided ``FormKitUploadHandler``. The host returns durable asset URLs.

## Fail Visibly

Unsupported or invalid schemas produce explicit reasons in ``FormKitRenderPlan/unsupportedReasons`` instead of silently rendering a partial form. Check ``FormKitRenderPlan/isSupported`` when deciding whether to offer an alternate experience.
