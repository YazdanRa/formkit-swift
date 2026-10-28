import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitSummaryRegressionTests: XCTestCase {
    func testArrayRulesKeepNestedAndEscapedPointers() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: #"""
            {
              "type": "object", "x-formkit-layout": "section-pages",
              "properties": {
                "first": {
                  "type": "object", "x-formkit-order": 1,
                  "properties": {
                    "checks/list": {
                      "type": "array",
                      "items": {
                        "type": "object",
                        "properties": {
                          "inspection~detail": {
                            "type": "object",
                            "properties": {
                              "result": {"type": "string", "enum": ["Pass", "Failed"]},
                              "note": {"type": "string"}
                            },
                            "if": {"properties": {"result": {"const": "Failed"}}, "required": ["result"]},
                            "then": {"required": ["note"]}
                          }
                        }
                      }
                    }
                  }
                },
                "second": {"type": "object", "x-formkit-order": 2, "properties": {"other": {"type": "string"}}}
              }
            }
            """#,
            instanceJSON: #"{"first":{"checks/list":[{"inspection~detail":{"result":"Failed"}}]}}"#
        )
        let summary = session.formSummary()

        XCTAssertTrue(session.renderPlan.isSupported, session.renderPlan.unsupportedReasons.map(\.message).joined())
        XCTAssertEqual(summary.flagged.map(\.field.id), ["#/first/checks~1list/0/inspection~0detail/result"])
        XCTAssertEqual(
            summary.flagged.first?.details.map(\.fieldID),
            ["#/first/checks~1list/0/inspection~0detail/note"]
        )
        XCTAssertEqual(summary.pages.first?.status, .needsAttention)
        XCTAssertEqual(summary.pages.first?.total, 1)
    }

    func testArrayFollowUpsTrackAddedAndReindexedRowsBeforeValidation() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: arraySchema,
            instanceJSON: #"{"first":{"checks":[{"result":"Pass"}]}}"#
        )
        for _ in 0..<2 {
            session.appendArrayRow(to: try arraySection(in: session))
        }
        session.setSelectedEnumChoiceID("string:Failed", for: try field("#/first/checks/1/result", in: session))
        session.setSelectedEnumChoiceID("string:Pass", for: try field("#/first/checks/2/result", in: session))

        var summary = session.formSummary()
        XCTAssertEqual(summary.pages.map(\.page.propertyKey), ["first", "second"])
        XCTAssertEqual(summary.pages.first?.total, 3)
        XCTAssertEqual(summary.pages.first?.answered, 3)
        XCTAssertEqual(summary.pages.first?.status, .needsAttention)
        XCTAssertEqual(summary.flagged.map(\.field.id), ["#/first/checks/1/result"])
        XCTAssertEqual(summary.flagged.first?.pageIndex, 0)
        XCTAssertEqual(summary.flagged.first?.details.map(\.fieldID), ["#/first/checks/1/note"])
        XCTAssertEqual(summary.missingRequired.map(\.id), ["#/first/checks/1/note"])

        let section = try arraySection(in: session)
        session.removeArrayRow(try XCTUnwrap(section.arrayDescriptor?.rows.first), from: section)
        summary = session.formSummary()
        XCTAssertEqual(summary.pages.first?.total, 2)
        XCTAssertEqual(summary.pages.first?.answered, 2)
        XCTAssertEqual(summary.pages.first?.status, .needsAttention)
        XCTAssertEqual(summary.flagged.map(\.field.id), ["#/first/checks/0/result"])
        XCTAssertEqual(summary.flagged.first?.details.map(\.fieldID), ["#/first/checks/0/note"])
        XCTAssertEqual(summary.missingRequired.map(\.id), ["#/first/checks/0/note"])

        session.setStringValue("Replace damaged part", for: try field("#/first/checks/0/note", in: session))
        summary = session.formSummary()
        XCTAssertEqual(summary.pages.first?.status, .done)
        XCTAssertEqual(summary.pages.first?.total, 2)
        XCTAssertEqual(summary.flagged.first?.details.map(\.answer), ["Replace damaged part"])
        XCTAssertTrue(summary.missingRequired.isEmpty)
    }

    func testHiddenConditionalFieldsNeverLeakRetainedSummaryAnswers() throws {
        let session = FormKitRenderer(includesHiddenToolFields: true).makeFormSession(
            schemaJSON: hiddenSectionSchema,
            instanceJSON: #"""
            {"first":{"enabled":false,"conditional":{"result":"Failed","note":"Retained observation"}}}
            """#
        )
        XCTAssertFalse(try field("#/first/conditional/result", in: session).isVisible)
        XCTAssertFalse(try field("#/first/conditional/result", in: session).shouldSerialize)
        XCTAssertFalse(try field("#/first/conditional/note", in: session).isVisible)
        XCTAssertEqual(session.formPages.map(\.propertyKey), ["first", "second"])
        XCTAssertTrue(session.formSummary().flagged.isEmpty)
        XCTAssertFalse(session.formSummary().general.contains { $0.fieldID.hasPrefix("#/first/conditional/") })
        XCTAssertEqual(
            session.makeToolContext().currentValues["/first/conditional/note"], .string("Retained observation")
        )

        session.setBooleanValue(true, for: try field("#/first/enabled", in: session))
        let visible = session.formSummary()
        XCTAssertTrue(try field("#/first/conditional/result", in: session).isVisible)
        XCTAssertEqual(session.formPages.map(\.propertyKey), ["first", "second"])
        let flagged = try XCTUnwrap(visible.flagged.first { $0.field.id == "#/first/conditional/result" })
        XCTAssertEqual(flagged.details.map(\.answer), ["Retained observation"])

        session.setBooleanValue(false, for: try field("#/first/enabled", in: session))
        let hidden = session.formSummary()
        XCTAssertFalse(try field("#/first/conditional/result", in: session).isVisible)
        XCTAssertFalse(try field("#/first/conditional/note", in: session).isVisible)
        XCTAssertEqual(session.formPages.map(\.propertyKey), ["first", "second"])
        XCTAssertTrue(hidden.flagged.isEmpty)
        XCTAssertFalse(hidden.general.contains { $0.fieldID.hasPrefix("#/first/conditional/") })
        XCTAssertFalse(hidden.missingRequired.contains { $0.id.hasPrefix("#/first/conditional/") })
        XCTAssertEqual(
            session.makeToolContext().currentValues["/first/conditional/note"], .string("Retained observation")
        )
    }

    func testSharedTriggerMergesDistinctFollowUpsInFieldOrder() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: sharedTriggerSchema,
            instanceJSON: #"{"first":{"result":"Failed","note":"Damaged"}}"#
        )
        var summary = session.formSummary()
        XCTAssertEqual(summary.flagged.map(\.field.id), ["#/first/result"])
        XCTAssertEqual(summary.flagged.first?.details.map(\.fieldID), ["#/first/note", "#/first/correctiveAction"])
        XCTAssertEqual(summary.flagged.first?.details.map(\.answer), ["Damaged", ""])
        XCTAssertEqual(summary.missingRequired.map(\.id), ["#/first/correctiveAction"])
        XCTAssertEqual(summary.pages.first?.status, .needsAttention)
        XCTAssertEqual(summary.pages.first?.total, 1)
        XCTAssertEqual(summary.pages.first?.answered, 1)

        session.setStringValue("Replace", for: try field("#/first/correctiveAction", in: session))
        summary = session.formSummary()
        XCTAssertEqual(summary.flagged.count, 1)
        XCTAssertEqual(summary.flagged.first?.details.map(\.fieldID), ["#/first/note", "#/first/correctiveAction"])
        XCTAssertEqual(summary.flagged.first?.details.map(\.answer), ["Damaged", "Replace"])
        XCTAssertEqual(summary.pages.first?.status, .done)
        XCTAssertEqual(summary.pages.first?.total, 1)
        XCTAssertTrue(summary.missingRequired.isEmpty)
    }

    private func field(_ id: String, in session: FormKitSession) throws -> FormKitFieldDescriptor {
        try XCTUnwrap(session.renderPlan.fields.first { $0.id == id })
    }

    private func arraySection(in session: FormKitSession) throws -> FormKitRenderPlan.SectionDescriptor {
        try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/first/checks" })
    }

    private var arraySchema: String {
        #"""
        {
          "type": "object", "x-formkit-layout": "section-pages",
          "$defs": {
            "failed": {"properties": {"result": {"const": "Failed"}}, "required": ["result"]},
            "check": {
              "type": "object",
              "properties": {
                "result": {"type": "string", "enum": ["Pass", "Failed"], "x-formkit-order": 1},
                "note": {"type": "string", "x-formkit-order": 2}
              },
              "if": {"$ref": "#/$defs/failed"}, "then": {"required": ["note"]}
            }
          },
          "properties": {
            "first": {
              "type": "object", "title": "First", "x-formkit-order": 1,
              "properties": {"checks": {"type": "array", "items": {"$ref": "#/$defs/check"}}}
            },
            "second": {
              "type": "object", "title": "Second", "x-formkit-order": 2,
              "properties": {"other": {"type": "string"}}
            }
          }
        }
        """#
    }

    private var hiddenSectionSchema: String {
        #"""
        {
          "type": "object", "x-formkit-layout": "section-pages",
          "properties": {
            "first": {
              "type": "object", "title": "First", "x-formkit-order": 1,
              "properties": {
                "enabled": {"type": "boolean", "x-formkit-order": 0},
                "conditional": {
                  "type": "object", "title": "Conditional", "x-formkit-order": 1,
                  "properties": {
                    "result": {"type": "string", "enum": ["Pass", "Failed"], "x-formkit-order": 1},
                    "note": {"type": "string", "x-formkit-order": 2}
                  },
                  "if": {"properties": {"result": {"const": "Failed"}}, "required": ["result"]},
                  "then": {"required": ["note"]}
                }
              },
              "if": {"properties": {"enabled": {"const": true}}, "required": ["enabled"]},
              "then": {"required": ["conditional"]}
            },
            "second": {
              "type": "object", "title": "Second", "x-formkit-order": 2,
              "properties": {"other": {"type": "string"}}
            }
          }
        }
        """#
    }

    private var sharedTriggerSchema: String {
        #"""
        {
          "type": "object", "x-formkit-layout": "section-pages",
          "properties": {
            "first": {
              "type": "object", "title": "First", "x-formkit-order": 1,
              "properties": {
                "result": {"type": "string", "enum": ["Pass", "Failed"], "x-formkit-order": 1},
                "note": {"type": "string", "x-formkit-order": 2},
                "correctiveAction": {"type": "string", "x-formkit-order": 3}
              },
              "allOf": [
                {
                  "if": {"properties": {"result": {"const": "Failed"}}, "required": ["result"]},
                  "then": {"required": ["correctiveAction", "note"]}
                },
                {
                  "if": {"properties": {"result": {"const": "Failed"}}, "required": ["result"]},
                  "then": {"required": ["note"]}
                }
              ]
            },
            "second": {
              "type": "object", "title": "Second", "x-formkit-order": 2,
              "properties": {"other": {"type": "string"}}
            }
          }
        }
        """#
    }
}
