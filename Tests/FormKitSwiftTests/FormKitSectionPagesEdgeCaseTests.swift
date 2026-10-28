import XCTest
@testable import FormKitSwift

/// Section-pages edge cases: hidden sections, explicit nulls, referenced conditions, and array errors.
@MainActor
final class FormKitSectionPagesEdgeCaseTests: XCTestCase {
    func testHiddenSectionsAreNotPages() throws {
        let schema = """
        {
          "type": "object",
          "x-formkit-layout": "section-pages",
          "properties": {
            "requestType": { "type": "string", "enum": ["Bug", "Feature"], "x-formkit-order": 1 },
            "contact": { "type": "object", "title": "Contact", "x-formkit-order": 2,
                         "properties": { "name": { "type": "string" } } },
            "bugDetails": { "type": "object", "title": "Bug Details", "x-formkit-order": 3,
                            "properties": { "severity": { "type": "string" } } },
            "notes": { "type": "object", "title": "Notes", "x-formkit-order": 4,
                       "properties": { "text": { "type": "string" } } }
          },
          "if": { "properties": { "requestType": { "const": "Bug" } }, "required": ["requestType"] },
          "then": { "required": ["bugDetails"] }
        }
        """
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: #"{"requestType": "Feature"}"#
        )

        XCTAssertEqual(session.formPages.map(\.title), ["Contact", "Notes"])
        XCTAssertEqual(session.formPages.first?.fieldIDs.first, "#/requestType")
        XCTAssertNil(session.pageIndex(containing: "#/bugDetails/severity"))

        let requestType = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "requestType" })
        session.setSelectedEnumChoiceID("string:Bug", for: requestType)
        XCTAssertEqual(session.formPages.map(\.title), ["Contact", "Bug Details", "Notes"])
    }

    func testValidExplicitNullCountsAsAnAnswer() throws {
        let schema = """
        {
          "type": "object",
          "x-formkit-layout": "section-pages",
          "properties": {
            "first": { "type": "object", "title": "First", "required": ["reading"],
                       "properties": { "reading": { "type": ["string", "null"], "title": "Reading" } } },
            "second": { "type": "object", "title": "Second", "properties": { "note": { "type": "string" } } }
          }
        }
        """
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: #"{"first": {"reading": null}}"#
        )
        let summary = session.formSummary()

        XCTAssertTrue(session.validate())
        XCTAssertEqual(summary.pages.first?.status, .done)
        XCTAssertTrue(summary.missingRequired.isEmpty)
    }

    func testConditionsResolveReferencesToTheRootSchema() {
        let schema = """
        {
          "type": "object",
          "x-formkit-layout": "section-pages",
          "$defs": {
            "failed": { "properties": { "result": { "const": "Failed" } }, "required": ["result"] }
          },
          "properties": {
            "first": {
              "type": "object", "title": "First",
              "properties": {
                "result": { "type": "string", "enum": ["Pass", "Failed"] },
                "note": { "type": "string" }
              },
              "if": { "$ref": "#/$defs/failed" },
              "then": { "required": ["note"] }
            },
            "second": { "type": "object", "title": "Second", "properties": { "other": { "type": "string" } } }
          }
        }
        """
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: #"{"first": {"result": "Failed"}}"#
        )
        let summary = session.formSummary()

        XCTAssertEqual(summary.flagged.map(\.field.id), ["#/first/result"])
        XCTAssertEqual(summary.pages.first?.status, .needsAttention)
        XCTAssertEqual(summary.missingRequired.map(\.id), ["#/first/note"])
    }

    func testArrayValidationErrorsFlagTheirPage() throws {
        let schema = """
        {
          "type": "object",
          "x-formkit-layout": "section-pages",
          "properties": {
            "first": {
              "type": "object", "title": "First",
              "properties": {
                "name": { "type": "string" },
                "photos": { "type": "array", "maxItems": 1, "items": { "type": "string" } }
              }
            },
            "second": { "type": "object", "title": "Second", "properties": { "other": { "type": "string" } } }
          }
        }
        """
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: #"{"first": {"name": "Ada", "photos": ["a", "b"]}}"#
        )
        XCTAssertEqual(session.formSummary().pages.first?.status, .done)

        XCTAssertFalse(session.validate())
        XCTAssertFalse(session.arrayErrors.isEmpty)
        XCTAssertEqual(session.formSummary().pages.first?.status, .needsAttention)
        XCTAssertEqual(session.formSummary().pages.last?.status, .notStarted)
    }
}
