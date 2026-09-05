import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitHiddenArrayTests: XCTestCase {
    func testHiddenArrayEditsOmitUntouchedDefaultsAndKeepBatchRowPointers() throws {
        let schema = #"""
        {
          "type": "object",
          "properties": {"enabled": {"type": "boolean"}},
          "if": {"properties": {"enabled": {"const": true}}, "required": ["enabled"]},
          "then": {"properties": {
            "entries": {"type": "array",
              "default": [{"note":"Generated", "choice":"A"}, {"note":"Other"}],
              "items": {"type":"object", "properties": {
                "note":{"type":"string"}, "choice":{"enum":["A","B"]}
              }}
            },
            "tags": {"type":"array", "default":["Generated", "Other"], "items":{"type":"string"}}
          }}
        }
        """#
        let renderer = FormKitRenderer(includesHiddenToolFields: true)
        let session = renderer.makeFormSession(schemaJSON: schema, instanceJSON: #"{"enabled":false}"#)
        let first = session.applyToolEdits([
            .init(pointer: "/entries/0/note", operation: .set, value: .string("Supplied")),
            .init(pointer: "/tags/1", operation: .set, value: .string("Supplied"))
        ])
        XCTAssertTrue(first.rejectedEdits.isEmpty)
        let saved = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(session.currentInstanceJSON.utf8))
        XCTAssertEqual(saved.object?["entries"], .array([.object(["note": .string("Supplied")]), .object([:])]))
        XCTAssertEqual(saved.object?["tags"], .array([.null, .string("Supplied")]))
        XCTAssertNil(first.context.currentValues["/entries/0/choice"])
        XCTAssertNil(first.context.currentValues["/entries/1/note"])
        XCTAssertNil(first.context.currentValues["/tags/0"])
        let reopened = renderer.makeFormSession(schemaJSON: schema, instanceJSON: session.currentInstanceJSON)
        XCTAssertEqual(reopened.currentInstanceJSON, session.currentInstanceJSON)

        let batchSession = renderer.makeFormSession(schemaJSON: schema, instanceJSON: #"{"enabled":false}"#)
        let batch = batchSession.applyToolEdits([
            .init(pointer: "/entries/0/note", operation: .set, value: .string("First")),
            .init(pointer: "/entries/1/note", operation: .set, value: .string("Second")),
            .init(pointer: "/tags/0", operation: .set, value: .string("First")),
            .init(pointer: "/tags/1", operation: .set, value: .string("Second"))
        ])
        XCTAssertTrue(batch.rejectedEdits.isEmpty)
        XCTAssertEqual(batch.appliedEdits.count, 4)
    }

    func testArraySeedsDoNotRestoreHiddenDefaultsOrClearedSuppliedChoices() throws {
        let schema = #"""
        {
          "type":"object", "properties":{
            "entries":{"type":"array", "default":[{"enabled":false,"choice":"A","details":{"note":"Generated"}}],
              "items":{"type":"object", "properties":{"enabled":{"type":"boolean"}},
                "if":{"properties":{"enabled":{"const":true}},"required":["enabled"]},
                "then":{"properties":{"choice":{"enum":["A","B"]},
                  "details":{"type":"object","properties":{"note":{"type":"string"}}}
                }}
              }
            }
          }
        }
        """#
        let renderer = FormKitRenderer(includesHiddenToolFields: true)
        let session = renderer.makeFormSession(schemaJSON: schema)
        let choice = try XCTUnwrap(session.makeToolContext().fields.first { $0.pointer == "/entries/0/choice" })
        XCTAssertFalse(choice.isVisible)
        XCTAssertNil(session.makeToolContext().currentValues["/entries/0/choice"])
        let saved = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(session.currentInstanceJSON.utf8))
        XCTAssertEqual(saved.object?["entries"], .array([.object(["enabled": .boolean(false)])]))

        let supplied = renderer.makeFormSession(
            schemaJSON: schema,
            instanceJSON: #"{"entries":[{"enabled":false,"choice":"A","unknown":"Keep"}]}"#
        )
        let result = supplied.applyToolEdits([.init(pointer: "/entries/0/choice", operation: .clear)])
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        let cleared = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(supplied.currentInstanceJSON.utf8))
        XCTAssertEqual(cleared.object?["entries"], .array([
            .object(["enabled": .boolean(false), "unknown": .string("Keep")])
        ]))
        let reopened = renderer.makeFormSession(schemaJSON: schema, instanceJSON: supplied.currentInstanceJSON)
        XCTAssertEqual(reopened.currentInstanceJSON, supplied.currentInstanceJSON)
    }
}
