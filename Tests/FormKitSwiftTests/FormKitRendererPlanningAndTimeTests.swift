import Foundation
import XCTest
@testable import FormKitSwift

private let detailPageSchema =
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "Feedback Form",
      "type": "object",
      "properties": {
        "contact_details": {
          "title": "Contact Details",
          "type": "object",
          "properties": {
            "full_name": {
              "title": "Full Name",
              "type": "string"
            },
            "email": {
              "title": "Email",
              "type": "string",
              "format": "email"
            }
          },
          "required": ["full_name", "email"]
        },
        "request_type": {
          "title": "Request Type",
          "type": "string",
          "enum": ["Bug", "Feature", "Support"]
        },
        "bug_details": {
          "title": "Bug Details",
          "type": "object",
          "properties": {
            "severity": {
              "title": "Severity",
              "type": "string",
              "enum": ["Low", "Medium", "High"]
            }
          }
        },
        "links": {
          "title": "Related Links",
          "type": "array",
          "items": {
            "type": "string"
          }
        },
        "team_members": {
          "title": "Team Members",
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": {
                "title": "Name",
                "type": "string"
              }
            }
          }
        }
      },
      "required": ["request_type"]
    }
    """

extension FormKitRendererTests {
    func testSupportedSchemaProducesFieldPlan() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: supportedSchema, instanceJSON: nil)

        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertEqual(session.renderPlan.title, "Project Intake")
        XCTAssertEqual(session.renderPlan.sections.map(\.title), ["Project Intake", "Contact"])
        XCTAssertEqual(
            session.renderPlan.sections.first(where: { $0.title == "Project Intake" })?.fieldIDs,
            ["#/visitDate", "#/priority"]
        )
        XCTAssertEqual(
            session.renderPlan.sections.first(where: { $0.title == "Contact" })?.fieldIDs,
            ["#/contact/fullName", "#/contact/email", "#/contact/website", "#/contact/sendUpdates"]
        )
        XCTAssertEqual(
            session.renderPlan.fields.map(\.propertyKey),
            ["fullName", "email", "website", "sendUpdates", "visitDate", "priority"]
        )
        XCTAssertEqual(field(named: "website", in: session)?.scalarType, .uri)
        XCTAssertEqual(
            field(named: "priority", in: session)?.enumOptions.map(\.title),
            ["Standard", "Expedited", "Critical"]
        )
    }

    func testRendererPreservesDeclaredPropertyOrder() throws {
        let schema =
            """
            {
              "title": "Ordering",
              "type": "object",
              "properties": {
                "zeta": {
                  "type": "string",
                  "title": "Zeta"
                },
                "alpha": {
                  "type": "string",
                  "title": "Alpha"
                },
                "middle": {
                  "type": "string",
                  "title": "Middle"
                }
              },
              "required": ["alpha"]
            }
            """

        for _ in 0..<25 {
            let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

            XCTAssertEqual(
                session.renderPlan.sections.first(where: { $0.title == "Ordering" })?.fieldIDs,
                ["#/zeta", "#/alpha", "#/middle"]
            )
            XCTAssertEqual(session.renderPlan.fields.map(\.propertyKey), ["zeta", "alpha", "middle"])
        }
    }

    func testRendererPreservesDependentSchemaOrderAcrossSessions() {
        let schema =
            """
            {
              "type": "object",
              "properties": {
                "one": { "type": "string" },
                "two": { "type": "string" }
              },
              "dependentSchemas": {
                "one": {
                  "properties": {
                    "z": { "type": "string" },
                    "a": { "type": "string" }
                  }
                },
                "two": {
                  "properties": {
                    "m": { "type": "string" },
                    "b": { "type": "string" }
                  }
                }
              }
            }
            """

        for _ in 0..<25 {
            let session = FormKitRenderer().makeFormSession(
                schemaJSON: schema,
                instanceJSON: #"{"one":"1","two":"2"}"#
            )

            XCTAssertEqual(
                session.renderPlan.fields.map(\.propertyKey),
                ["one", "two", "z", "a", "m", "b"]
            )
        }
    }

    func testPropertyOrderScannerIgnoresAnnotationDataNamedDependentSchemas() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "examples": [
                { "dependentSchemas": "ordinary data" }
              ],
              "properties": {
                "name": { "type": "string" }
              }
            }
            """,
            instanceJSON: nil
        )

        XCTAssertEqual(session.renderPlan.fields.map(\.propertyKey), ["name"])
        XCTAssertTrue(session.renderPlan.unsupportedReasons.isEmpty)
    }

    func testRendererPreservesReferencedPropertyOrder() throws {
        let schema =
            """
            {
              "title": "Reference Ordering",
              "type": "object",
              "properties": {
                "contact": {
                  "$ref": "#/$defs/contact_details"
                }
              },
              "$defs": {
                "contact_details": {
                  "title": "Contact Details",
                  "type": "object",
                  "properties": {
                    "full_name": {
                      "title": "Full Name",
                      "type": "string"
                    },
                    "email": {
                      "title": "Email",
                      "type": "string",
                      "format": "email"
                    },
                    "phone": {
                      "title": "Phone",
                      "type": "string"
                    }
                  },
                  "required": ["email"]
                }
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

        XCTAssertEqual(
            session.renderPlan.sections.first(where: { $0.title == "Contact Details" })?.fieldIDs,
            ["#/contact/full_name", "#/contact/email", "#/contact/phone"]
        )
        XCTAssertEqual(session.renderPlan.fields.map(\.propertyKey), ["full_name", "email", "phone"])
    }

    func testDetailPageRenderIndexPreservesRootContentOrder() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: detailPageSchema, instanceJSON: nil)
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        let blockLabels = renderIndex.visibleRootBlocks.compactMap { block -> String? in
            switch block.kind {
            case .section(let sectionID):
                return renderIndex.section(sectionID)?.title
            case .fieldGroup(_, let fieldIDs):
                return fieldIDs
                    .compactMap { renderIndex.field($0)?.propertyKey }
                    .joined(separator: ",")
            }
        }

        XCTAssertEqual(
            blockLabels,
            ["Contact Details", "request_type", "Bug Details", "Related Links", "Team Members"]
        )
    }

    func testUnsupportedSchemaReturnsFailClosedPlan() {
        let session = FormKitRenderer().makeFormSession(schemaJSON: unsupportedSchema, instanceJSON: nil)

        XCTAssertFalse(session.renderPlan.isSupported)
        XCTAssertTrue(session.renderPlan.sections.isEmpty, "Unexpected sections: \(session.renderPlan.sections)")
        XCTAssertTrue(session.renderPlan.fields.isEmpty, "Unexpected fields: \(session.renderPlan.fields)")
        XCTAssertTrue(session.renderPlan.unsupportedReasons.contains(where: {
            $0.message.localizedCaseInsensitiveContains("prefixItems")
        }))
    }

    func testInvalidSchemaFallbackUsesUntitledJSONFormTitle() {
        let invalidJSONSession = FormKitRenderer().makeFormSession(schemaJSON: "{", instanceJSON: nil)
        let nonObjectRootSession = FormKitRenderer().makeFormSession(schemaJSON: "[]", instanceJSON: nil)

        XCTAssertEqual(invalidJSONSession.renderPlan.title, FormKitDefaults.untitledTitle)
        XCTAssertEqual(nonObjectRootSession.renderPlan.title, FormKitDefaults.untitledTitle)
        XCTAssertFalse(invalidJSONSession.renderPlan.isSupported)
        XCTAssertFalse(nonObjectRootSession.renderPlan.isSupported)
    }
}

extension FormKitRendererTests {
    func testTimeFormatMapsToTimeScalarAndRoundTripsRFC3339FullTime() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "startTime": {
                  "type": "string",
                  "format": "time"
                }
              },
              "required": ["startTime"]
            }
            """,
            instanceJSON: #"{"startTime":"08:30:06.5-08:00"}"#
        )
        let field = try XCTUnwrap(session.renderPlan.fields.first)

        XCTAssertEqual(field.scalarType, .time)
        XCTAssertTrue(session.validate())

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let parsedComponents = calendar.dateComponents(
            [.hour, .minute, .second],
            from: session.dateValue(for: field)
        )
        XCTAssertEqual(parsedComponents.hour, 16)
        XCTAssertEqual(parsedComponents.minute, 30)
        XCTAssertEqual(parsedComponents.second, 6)

        session.setDateValue(Date(timeIntervalSince1970: 52200), for: field)

        XCTAssertEqual(
            try decodeJSONObject(session.currentInstanceJSON)["startTime"] as? String,
            "14:30:00Z"
        )
        XCTAssertTrue(session.validate())
    }

    func testParsedTimeUsesCurrentSeasonalOffsetWhenDisplayed() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let referenceDate = try XCTUnwrap(
            FormKitRenderer.dateTimeFallbackFormatter.date(from: "2026-07-28T12:00:00Z")
        )
        let parsedDate = try XCTUnwrap(
            FormKitRenderer.reanchoredTime(
                from: "16:00:00Z",
                referenceDate: referenceDate,
                timeZone: timeZone
            )
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        XCTAssertEqual(calendar.component(.hour, from: parsedDate), 9)
        XCTAssertEqual(FormKitRenderer.timeFormatter.string(from: parsedDate), "16:00:00Z")
    }

    func testParsedTimeAnchorsToActualLocalDayAcrossDSTTransition() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 19))
        )
        let parsedDate = try XCTUnwrap(
            FormKitRenderer.reanchoredTime(
                from: "03:00:00Z",
                referenceDate: referenceDate,
                timeZone: timeZone
            )
        )

        XCTAssertEqual(calendar.component(.day, from: parsedDate), 1)
        XCTAssertEqual(calendar.component(.hour, from: parsedDate), 19)
        XCTAssertEqual(FormKitRenderer.timeFormatter.string(from: parsedDate), "03:00:00Z")
    }

    func testParsedTimeUsesReferenceOffsetAtDSTDayBoundaries() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let springReference = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))
        )
        let springGap = try XCTUnwrap(
            FormKitRenderer.reanchoredTime(
                from: "07:00:00Z",
                referenceDate: springReference,
                timeZone: timeZone
            )
        )
        let fallReference = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 3))
        )
        let fallOverlap = try XCTUnwrap(
            FormKitRenderer.reanchoredTime(
                from: "07:00:00Z",
                referenceDate: fallReference,
                timeZone: timeZone
            )
        )

        XCTAssertEqual(FormKitRenderer.timeFormatter.string(from: springGap), "07:00:00Z")
        XCTAssertEqual(abs(springGap.timeIntervalSince(springReference)), 12 * 60 * 60)
        XCTAssertEqual(calendar.component(.day, from: fallOverlap), 1)
        XCTAssertEqual(calendar.component(.hour, from: fallOverlap), 23)
    }

}
