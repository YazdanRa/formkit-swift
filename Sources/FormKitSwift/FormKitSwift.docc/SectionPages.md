# Section Pages

Show a long sectioned form one top-level section per page, with a summary page after the last one.

## Request the Layout

Add `x-formkit-layout` to the root schema:

```json
{
  "type": "object",
  "title": "Room inspection",
  "x-formkit-layout": "section-pages",
  "required": ["roomNumber"],
  "properties": {
    "roomNumber": { "type": "integer", "title": "Room number", "x-formkit-order": 1 },
    "housekeeping": {
      "type": "object",
      "title": "Housekeeping",
      "x-formkit-order": 2,
      "properties": {
        "linens": { "type": "string", "title": "Linens", "enum": ["Pass", "Failed", "N/A"] },
        "linens_observation": { "type": "string", "title": "Observation" }
      },
      "allOf": [
        {
          "if": { "properties": { "linens": { "const": "Failed" } }, "required": ["linens"] },
          "then": { "required": ["linens_observation"] }
        }
      ]
    },
    "electrical": { "type": "object", "title": "Electrical", "x-formkit-order": 3, "properties": {} }
  }
}
```

Each top-level object property becomes a page, in `x-formkit-order` order. Top-level fields and arrays outside any section join the page of the section after them, or the last page when no section follows, so "Room number" opens page one. A form with fewer than two top-level sections, or any other `x-formkit-layout` value, keeps the single scrolling form. ``FormKitRenderPlan/layout`` reports the requested ``FormKitFormLayout``.

## What the Pages Show

- A Liquid Glass control floats above the page, under the host's own navigation bar: a round previous button, a capsule showing "2 of 6 · Housekeeping" with one progress bar per section, and a round next button. The capsule opens a menu of every section with its status, followed by the summary. Next on the last section opens the summary.
- A Liquid Glass button at the foot of each page continues to the next section, or opens the summary from the last one. It is a standard-size button on the trailing edge of the page.
- Each page shows only its own fields. The section title is left out because the header names it; nested sections keep their titles. The form description shows on the first page.
- The summary page lists each section's progress, the flagged answers, and the required fields that are still empty. Tapping a section or a flagged answer goes back to its page.

Text comes from ``FormKitLabels/pages``. Colors come from ``FormKitStyle``.

## Progress and the Summary

``FormKitSession/formPages`` returns the pages, and ``FormKitSession/formSummary()`` returns a ``FormKitFormSummary``:

- **Answered** counts the section's own visible questions with an answer someone gave. Renderer defaults do not count, and neither do follow-ups or top-level fields placed on the page.
- **Flagged answers** are answers that satisfied an `if` whose `then` requires or declares other fields, such as "Failed" opening its observation. Rules are read from the object they are declared in, including its `allOf` members and local `$ref` targets.
- A page **needs attention** when a follow-up an answer opened is still empty, or when a field on it failed validation. A required field nobody has reached yet does not flag the page, so a fresh form does not open in an error state.

## Turning Pages from the Host

``FormKitView`` keeps its own ``FormKitPageNavigator`` unless the host passes one. Pass one to turn pages from the host, for example when a voice assistant moves to its next question, or to react when the person pages by hand:

```swift
let navigator = FormKitPageNavigator(session: session)
navigator.onUserNavigation = { position in
    assistant.userOpened(position)
}

FormKitView(session: session, focusedFieldID: $focusedFieldID, pageNavigator: navigator)

navigator.revealField("#/electrical/lighting")
```

Changes with ``FormKitPageNavigationOrigin/user`` origin call ``FormKitPageNavigator/onUserNavigation``. Host changes, ``FormKitPageNavigator/revealField(_:scrollsToField:)``, and focus requests through the `focusedFieldID` binding turn the page without calling it. Keyboard focus stays on the page on screen, and a half-typed answer is kept when the page changes.
