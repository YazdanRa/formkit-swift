import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitHiddenToolFieldTests: XCTestCase {
    func testHiddenAnswersApplyBeforeTheirControllerAndOptionalAnswersPersist() throws {
        let session = makeSession()
        XCTAssertTrue(try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#" }).isVisible)
        XCTAssertFalse(FormKitRenderIndex(renderPlan: session.renderPlan).visibleRootBlocks.isEmpty)
        let before = session.makeToolContext()
        XCTAssertFalse(try XCTUnwrap(before.fields.first { $0.pointer == "/details/notes" }).isVisible)
        XCTAssertNil(before.currentValues["/details/defaultNote"])

        let result = session.applyToolEdits([
            .init(pointer: "/details/followup", operation: .set, value: .string("Nested answer")),
            .init(pointer: "/details/notes", operation: .set, value: .string("Observed at loading bay")),
            .init(pointer: "/optionalNote", operation: .set, value: .string("Provided voluntarily")),
            .init(pointer: "/mode", operation: .set, value: .string("advanced"))
        ], baseRevision: before.revision)

        XCTAssertTrue(result.rejectedEdits.isEmpty)
        XCTAssertEqual(result.appliedEdits.count, 4)
        let revealed = try XCTUnwrap(result.context.fields.first { $0.pointer == "/details/notes" })
        XCTAssertTrue(revealed.isVisible)
        XCTAssertTrue(revealed.isRequired)
        let nested = try XCTUnwrap(result.context.fields.first { $0.pointer == "/details/followup" })
        XCTAssertTrue(nested.isVisible)
        XCTAssertTrue(nested.isRequired)
        XCTAssertEqual(result.context.currentValues["/details/followup"], .string("Nested answer"))
        XCTAssertEqual(result.context.currentValues["/details/notes"], .string("Observed at loading bay"))
        XCTAssertEqual(result.context.currentValues["/optionalNote"], .string("Provided voluntarily"))
    }

    func testHiddenInitialAndEditedAnswersSurviveReopeningWithoutHiddenDefaults() throws {
        let session = makeSession(instanceJSON: #"{"mode":"basic","details":{"notes":"Existing"}}"#)
        XCTAssertEqual(session.makeToolContext().currentValues["/details/notes"], .string("Existing"))
        let result = session.applyToolEdits([
            .init(pointer: "/details/notes", operation: .set, value: .string("Revised"))
        ])
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        let saved = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(session.currentInstanceJSON.utf8))
        XCTAssertEqual(saved.object?["details"]?.object, ["notes": .string("Revised")])
        let reopened = makeSession(instanceJSON: session.currentInstanceJSON)
        XCTAssertEqual(reopened.makeToolContext().currentValues["/details/notes"], .string("Revised"))
        XCTAssertNil(reopened.makeToolContext().currentValues["/details/defaultNote"])
        XCTAssertFalse(try XCTUnwrap(reopened.renderPlan.fields.first { $0.pointer == "#/details/notes" }).isVisible)
    }

    func testHiddenInitialEmptyObjectPersists() throws {
        let session = makeSession(instanceJSON: #"{"mode":"basic","details":{}}"#)
        let saved = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(session.currentInstanceJSON.utf8))
        XCTAssertEqual(saved.object?["details"], .object([:]))
    }

    func testHiddenFieldsKeepTypeChoiceTemporalLockAndRevisionChecks() {
        let session = makeSession(overrides: ["/details/disabledNote": .disable])
        let result = session.applyToolEdits([
            .init(pointer: "/details/notes", operation: .set, value: .string("Locked")),
            .init(pointer: "/details/disabledNote", operation: .set, value: .string("Disabled")),
            .init(pointer: "/unknown", operation: .set, value: .string("Unknown")),
            .init(pointer: "/details/defaultNote", operation: .set, value: .boolean(true)),
            .init(pointer: "/details/choice", operation: .set, value: .string("unknown")),
            .init(pointer: "/details/date", operation: .set, value: .string("yesterday"))
        ], lockedPointers: ["/details/notes"])
        XCTAssertTrue(result.appliedEdits.isEmpty)
        XCTAssertEqual(result.rejectedEdits.map(\.reason), [
            "field_locked", "field_not_visible", "field_not_found", "type_mismatch", "invalid_choice", "invalid_format"
        ])
        let stale = session.applyToolEdits([
            .init(pointer: "/details/notes", operation: .set, value: .string("Stale"))
        ], baseRevision: -1)
        XCTAssertEqual(stale.rejectedEdits.map(\.reason), ["revision_conflict"])
    }

    func testHiddenArrayRowsKeepTheirStructureAcrossEditsAndReopening() throws {
        let schema = #"""
        {
          "type": "object",
          "properties": {"enabled": {"type": "boolean"}},
          "if": {"properties": {"enabled": {"const": true}}, "required": ["enabled"]},
          "then": {"properties": {"entries": {
            "type": "array",
            "items": {"type": "object", "properties": {
              "note": {"type": "string"},
              "extra": {"type": "object", "properties": {"text": {"type": "string"}}}
            }}
          }}}
        }
        """#
        let renderer = FormKitRenderer(includesHiddenToolFields: true)
        for entries in ["[]", "[{}]", #"[{"note":"First"},{}]"#, #"[{"extra":{}}]"#] {
            let initialJSON = "{\"enabled\":false,\"entries\":\(entries)}"
            let initialSession = renderer.makeFormSession(schemaJSON: schema, instanceJSON: initialJSON)
            let saved = try JSONDecoder().decode(
                FormKitJSONValue.self, from: Data(initialSession.currentInstanceJSON.utf8)
            )
            let initial = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(initialJSON.utf8))
            XCTAssertEqual(saved, initial)
        }
        let session = renderer.makeFormSession(
            schemaJSON: schema,
            instanceJSON: #"{"enabled":false,"entries":[{"note":"First"},{},{"note":"Last"}]}"#
        )
        let result = session.applyToolEdits([
            .init(pointer: "/entries/2/note", operation: .set, value: .string("Updated"))
        ])
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        let saved = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(session.currentInstanceJSON.utf8))
        XCTAssertEqual(saved.object?["entries"], .array([
            .object(["note": .string("First")]), .object([:]), .object(["note": .string("Updated")])
        ]))
        let reopened = renderer.makeFormSession(schemaJSON: schema, instanceJSON: session.currentInstanceJSON)
        XCTAssertEqual(reopened.currentInstanceJSON, session.currentInstanceJSON)
    }

    func testDefaultRendererStillExcludesHiddenFields() {
        let session = FormKitRenderer().makeFormSession(schemaJSON: Self.schema, instanceJSON: #"{"mode":"basic"}"#)
        XCTAssertFalse(session.makeToolContext().fields.contains { $0.pointer == "/details/notes" })
        let result = session.applyToolEdits([
            .init(pointer: "/details/notes", operation: .set, value: .string("Hidden"))
        ])
        XCTAssertEqual(result.rejectedEdits.map(\.reason), ["field_not_found"])
    }

    func testRendererOverrideCloneKeepsHiddenToolSupport() {
        let session = FormKitRenderer(includesHiddenToolFields: true).makeFormSession(
            schemaJSON: Self.schema,
            instanceJSON: #"{"mode":"basic"}"#,
            conditionalRenderBehaviorOverrides: ["/details/disabledNote": .disable]
        )
        XCTAssertTrue(session.makeToolContext().fields.contains { $0.pointer == "/details/notes" && !$0.isVisible })
    }

    func testActiveBranchWinsWhenInactiveBranchUsesSamePointer() throws {
        let schema = #"""
        {
          "type": "object",
          "properties": {"enabled": {"type": "boolean"}},
          "if": {"properties": {"enabled": {"const": true}}, "required": ["enabled"]},
          "then": {"properties": {"details": {"type": "string"}}},
          "else": {"properties": {"details": {"enum": ["A", "B"]}}}
        }
        """#
        let session = FormKitRenderer(includesHiddenToolFields: true).makeFormSession(
            schemaJSON: schema, instanceJSON: #"{"enabled":true}"#
        )
        let field = try XCTUnwrap(session.makeToolContext().fields.first { $0.pointer == "/details" })
        XCTAssertTrue(field.isVisible)
        XCTAssertEqual(field.type, "string")
        XCTAssertTrue(field.enumOptions.isEmpty)
    }

    func testPredeclaredConditionallyRequiredFieldKeepsItsVisibility() throws {
        let schema = #"""
        {
          "type": "object",
          "properties": {"enabled": {"type": "boolean"}, "code": {"type": "string"}},
          "if": {"properties": {"enabled": {"const": true}}, "required": ["enabled"]},
          "then": {"required": ["code"]}
        }
        """#
        for includesHidden in [false, true] {
            let session = FormKitRenderer(includesHiddenToolFields: includesHidden).makeFormSession(
                schemaJSON: schema, instanceJSON: #"{"enabled":false}"#
            )
            XCTAssertFalse(try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/code" }).isVisible)
            let result = session.applyToolEdits([.init(pointer: "/enabled", operation: .set, value: .boolean(true))])
            let revealed = try XCTUnwrap(result.context.fields.first { $0.pointer == "/code" })
            XCTAssertTrue(revealed.isVisible)
            XCTAssertTrue(revealed.isRequired)
        }
    }

    func testInactiveBranchCannotHideOrConstrainUnconditionalProperties() throws {
        let schema = #"""
        {
          "type": "object",
          "properties": {
            "enabled": {"type": "boolean"},
            "details": {"type": "string"},
            "nested": {"type": "object", "properties": {"note": {"type": "string"}}},
            "entries": {"type": "array", "items": {
              "type": "object", "properties": {"note": {"type": "string"}}
            }}
          },
          "if": {"properties": {"enabled": {"const": true}}, "required": ["enabled"]},
          "then": {},
          "else": {"properties": {
            "details": {"type": "string", "maxLength": 1, "enum": ["A"], "default": "A"},
            "nested": {"type": "object", "properties": {"note": {"enum": ["A"]}}},
            "entries": {"type": "array", "items": {
              "type": "object", "properties": {"note": {"enum": ["A"]}}
            }},
            "hiddenOnly": {"type": "string"}
          }}
        }
        """#
        let session = FormKitRenderer(includesHiddenToolFields: true).makeFormSession(
            schemaJSON: schema,
            instanceJSON: #"{"enabled":true,"entries":[{}]}"#
        )
        XCTAssertTrue(session.renderPlan.isSupported)
        let pointers = ["/details", "/nested/note", "/entries/0/note"]
        for pointer in pointers {
            let field = try XCTUnwrap(session.makeToolContext().fields.first { $0.pointer == pointer })
            XCTAssertTrue(field.isVisible, pointer)
            XCTAssertEqual(field.type, "string", pointer)
            XCTAssertTrue(field.enumOptions.isEmpty, pointer)
            XCTAssertNil(session.makeToolContext().currentValues[pointer], pointer)
        }
        let hidden = try XCTUnwrap(session.makeToolContext().fields.first { $0.pointer == "/hiddenOnly" })
        XCTAssertFalse(hidden.isVisible)
        let result = session.applyToolEdits(pointers.map {
            .init(pointer: $0, operation: .set, value: .string("Unrestricted answer"))
        })
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        XCTAssertEqual(result.appliedEdits.count, pointers.count)
        XCTAssertTrue(session.validate())
    }

    func testRemovingOrReplacingRowsDoesNotRestoreAnotherRowsHiddenContainers() throws {
        let schema = #"""
        {
          "type": "object",
          "properties": {"entries": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {"expanded": {"type": "boolean"}},
              "if": {"properties": {"expanded": {"const": true}}, "required": ["expanded"]},
              "then": {"properties": {
                "extra": {"type": "object", "properties": {"text": {"type": "string"}}}
              }}
            }
          }}
        }
        """#
        let renderer = FormKitRenderer(includesHiddenToolFields: true)
        for (removesFirst, extra) in [(true, "{}"), (false, "{}"), (true, #"{"text":"Removed"}"#)] {
            let session = renderer.makeFormSession(
                schemaJSON: schema,
                instanceJSON: "{\"entries\":[{\"expanded\":false,\"extra\":\(extra)},{\"expanded\":false}]}"
            )
            let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/entries" })
            let rows = try XCTUnwrap(section.arrayDescriptor).rows
            let row = try XCTUnwrap(rows.first { $0.index == (removesFirst ? 0 : 1) })
            session.removeArrayRow(row, from: section)
            let saved = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(session.currentInstanceJSON.utf8))
            var expected: [String: FormKitJSONValue] = ["expanded": .boolean(false)]
            if !removesFirst {
                expected["extra"] = .object([:])
            }
            XCTAssertEqual(saved.object?["entries"], .array([.object(expected)]))

            let nextSection = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/entries" })
            session.setArrayValue([.object(["expanded": .boolean(false)])], for: nextSection)
            let replaced = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(session.currentInstanceJSON.utf8))
            XCTAssertEqual(replaced.object?["entries"], .array([.object(["expanded": .boolean(false)])]))
        }
    }

    private func makeSession(
        instanceJSON: String = #"{"mode":"basic"}"#,
        overrides: [String: FormKitConditionalRenderBehavior] = [:]
    ) -> FormKitSession {
        FormKitRenderer(
            conditionalRenderBehaviorOverrides: overrides,
            includesHiddenToolFields: true
        ).makeFormSession(schemaJSON: Self.schema, instanceJSON: instanceJSON)
    }

    private static let schema = #"""
    {
      "type": "object",
      "properties": {
        "mode": {"enum": ["basic", "advanced"]},
        "optionalNote": {"type": "string"}
      },
      "required": ["mode"],
      "if": {"properties": {"mode": {"const": "advanced"}}, "required": ["mode"]},
      "then": {
        "properties": {
          "details": {
            "type": "object",
            "properties": {
              "notes": {"type": "string"},
              "defaultNote": {"type": "string", "default": "Untouched"},
              "disabledNote": {"type": "string"},
              "choice": {"enum": ["A", "B"]},
              "date": {"type": "string", "format": "date"}
            },
            "required": ["notes"],
            "if": {"properties": {"notes": {"const": "Observed at loading bay"}}, "required": ["notes"]},
            "then": {
              "properties": {"followup": {"type": "string"}},
              "required": ["followup"]
            }
          }
        }
      }
    }
    """#
}
