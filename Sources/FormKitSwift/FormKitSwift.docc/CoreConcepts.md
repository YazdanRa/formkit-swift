# Core Concepts

Understand how schema, rendering, state, and host integration fit together.

## Renderer and Render Plan

``FormKitRenderer`` parses schema and instance JSON, compiles validation, and creates a ``FormKitSession``. Its ``FormKitRenderPlan`` describes sections, fields, array rows, component annotations, and unsupported schema features.

Use the ``FormKitRendering`` protocol when a host needs to substitute session creation in tests.

## Session

``FormKitSession`` owns the current form state:

- `renderPlan` describes the currently applicable form.
- ``FormKitSession/currentInstanceJSON`` serializes the current value.
- ``FormKitSession/validate()`` refreshes validation errors and returns whether the value is valid.
- `revision` changes after mutations and supports optimistic tool edits.

Conditional schemas can change the render plan after an edit. Resolve fields and sections from the current plan instead of retaining descriptors indefinitely.

## View

``FormKitView`` renders a native SwiftUI `Form`. Inject a retained session for controlled state, or pass schema and instance JSON when the view can own the session.

``FormKitOptions`` configures editing mode, styling, labels, visual field state, upload handling, and component overrides. Its validation and conditional options configure session creation only when the view owns the session. For an injected session, pass those values to ``FormKitRenderer`` when creating it.

## JSON Pointers

Descriptors use root-prefixed JSON Pointers such as `#/contact/email`. Generic tool APIs expose pointers without the leading `#`, such as `/contact/email`.

Conditional render overrides accept either form and normalize them internally. A `*` segment targets repeated array rows, for example `#/entries/*/notes`.

## Components

Stock controls cover supported scalar, enum, date, array, file, and signature inputs. ``FormKitComponents`` can replace:

- an entire field,
- only a field's input,
- an array section, or
- a section header.

Returning `nil` from a field-input or array-section override delegates to the package registry and then the stock control.

## Generic Tools

``FormKitToolContext`` is a transport-neutral snapshot for assistants, automations, and collaboration systems. ``FormKitToolEdit`` applies pointer-based mutations with optional revision checks and pointer locks. Host-specific protocols stay outside the package.
