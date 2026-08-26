import XCTest
@testable import FormKitSwift

private let predeclaredConditionalObjectSchema =
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "Project Intake Form",
      "description": "Collect a few basic details and export them as JSON Schema.",
      "type": "object",
      "properties": {
        "contact_details": {
          "title": "Contact Details",
          "description": "Basic information about the requester.",
          "type": "object",
          "properties": {
            "full_name": {
              "title": "Full Name",
              "description": "Name of the requester",
              "type": "string"
            },
            "email": {
              "title": "Email",
              "description": "Primary contact email",
              "type": "string",
              "format": "email"
            }
          },
          "required": ["full_name", "email"]
        },
        "request_type": {
          "title": "Request Type",
          "description": "Select the kind of request",
          "type": "string",
          "enum": ["Bug", "Feature", "Support"]
        },
        "bug_details": {
          "title": "Bug Details",
          "description": "Optional details when the request is a bug.",
          "type": "object",
          "properties": {
            "severity": {
              "title": "Severity",
              "type": "string",
              "enum": ["Low", "Medium", "High"]
            },
            "steps": {
              "title": "Steps to Reproduce",
              "type": "string"
            }
          },
          "required": ["severity"]
        },
        "links": {
          "title": "Related Links",
          "description": "A simple list of text items",
          "type": "array",
          "items": {
            "type": "string"
          }
        },
        "team_members": {
          "title": "Team Members",
          "description": "A list of nested object items",
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": {
                "title": "Name",
                "type": "string"
              },
              "role": {
                "title": "Role",
                "type": "string"
              }
            },
            "required": ["name"]
          }
        }
      },
      "required": ["request_type"],
      "allOf": [
        {
          "if": {
            "properties": {
              "request_type": {
                "const": "Bug"
              }
            },
            "required": ["request_type"]
          },
          "then": {
            "required": ["bug_details"]
          }
        }
      ]
    }
    """

private let predeclaredConditionalObjectInstance =
    """
    {
      "request_type": "Feature"
    }
    """

private let predeclaredConditionalScalarSchema =
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "Advanced Settings",
      "type": "object",
      "properties": {
        "mode": {
          "title": "Mode",
          "type": "string",
          "enum": ["basic", "advanced"]
        },
        "advanced_code": {
          "title": "Advanced Code",
          "type": "string"
        }
      },
      "required": ["mode"],
      "allOf": [
        {
          "if": {
            "properties": {
              "mode": { "const": "advanced" }
            },
            "required": ["mode"]
          },
          "then": {
            "required": ["advanced_code"]
          }
        }
      ]
    }
    """

private let predeclaredConditionalScalarInstance =
    """
    {
      "mode": "basic"
    }
    """

extension FormKitRendererTests {
    func testConditionalRequiredPredeclaredObjectSectionHidesWhenBranchInactive() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: predeclaredConditionalObjectSchema,
            instanceJSON: predeclaredConditionalObjectInstance
        )
        let requestTypeField = tryUnwrapField("request_type", in: session)

        let hiddenBugDetailsSection = try XCTUnwrap(
            session.renderPlan.sections.first(where: { $0.title == "Bug Details" })
        )
        XCTAssertFalse(hiddenBugDetailsSection.isVisible)
        XCTAssertFalse(tryUnwrapField("severity", in: session).isVisible)
        XCTAssertFalse(tryUnwrapField("steps", in: session).isVisible)

        XCTAssertEqual(
            visibleRootBlockLabels(in: session.renderPlan),
            ["Contact Details", "request_type", "Related Links", "Team Members"]
        )

        session.setSelectedEnumChoiceID("string:Bug", for: requestTypeField)

        XCTAssertTrue(
            try XCTUnwrap(
                session.renderPlan.sections.first(where: { $0.title == "Bug Details" })
            ).isVisible
        )
        XCTAssertTrue(tryUnwrapField("severity", in: session).isVisible)
    }

    func testConditionalRequiredPredeclaredScalarFieldHidesUntilBranchActivates() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: predeclaredConditionalScalarSchema,
            instanceJSON: predeclaredConditionalScalarInstance
        )
        let modeField = tryUnwrapField("mode", in: session)
        let inactiveAdvancedCodeField = tryUnwrapField("advanced_code", in: session)

        XCTAssertFalse(inactiveAdvancedCodeField.isVisible)
        XCTAssertFalse(inactiveAdvancedCodeField.isRequired)
        XCTAssertTrue(session.validate())

        XCTAssertEqual(visibleRootBlockLabels(in: session.renderPlan), ["mode"])

        session.setSelectedEnumChoiceID("string:advanced", for: modeField)

        let activeAdvancedCodeField = tryUnwrapField("advanced_code", in: session)
        XCTAssertTrue(activeAdvancedCodeField.isVisible)
        XCTAssertTrue(activeAdvancedCodeField.isRequired)
        XCTAssertFalse(session.validate())
        XCTAssertEqual(session.errorMessages(for: activeAdvancedCodeField), ["This field is required."])

        session.setStringValue("ALPHA-7", for: activeAdvancedCodeField)
        XCTAssertTrue(session.validate())
    }
}

private func visibleRootBlockLabels(in renderPlan: FormKitRenderPlan) -> [String] {
    let renderIndex = FormKitRenderIndex(renderPlan: renderPlan)

    return renderIndex.visibleRootBlocks.compactMap { block -> String? in
        switch block.kind {
        case .section(let sectionID):
            return renderIndex.section(sectionID)?.title
        case .fieldGroup(_, let fieldIDs):
            return fieldIDs
                .compactMap { renderIndex.field($0)?.propertyKey }
                .joined(separator: ",")
        }
    }
}

private let pureConditionalObjectSchema =
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "Feedback Form",
      "type": "object",
      "properties": {
        "request_type": {
          "title": "Request Type",
          "type": "string",
          "enum": ["Bug", "Feature", "Support"]
        }
      },
      "required": ["request_type"],
      "allOf": [
        {
          "if": {
            "properties": {
              "request_type": { "const": "Bug" }
            },
            "required": ["request_type"]
          },
          "then": {
            "properties": {
              "bug_details": {
                "title": "Bug Details",
                "type": "object",
                "properties": {
                  "severity": {
                    "title": "Severity",
                    "type": "string",
                    "enum": ["Low", "Medium", "High"]
                  },
                  "steps": {
                    "title": "Steps to Reproduce",
                    "type": "string"
                  }
                }
              }
            },
            "required": ["bug_details"]
          }
        },
        {
          "if": {
            "properties": {
              "request_type": { "const": "Feature" }
            },
            "required": ["request_type"]
          },
          "then": {
            "properties": {
              "feature_details": {
                "title": "Feature Details",
                "type": "object",
                "properties": {
                  "summary": {
                    "title": "Summary",
                    "type": "string"
                  }
                }
              }
            },
            "required": ["feature_details"]
          }
        }
      ]
    }
    """

extension FormKitRendererTests {
    func testPureJSONSchemaConditionalObjectSectionsHideAndShowWithDiscriminator() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: pureConditionalObjectSchema,
            instanceJSON: nil
        )
        let requestTypeField = tryUnwrapField("request_type", in: session)

        XCTAssertNotNil(session.renderPlan.sections.first(where: { $0.title == "Bug Details" }))
        XCTAssertNil(session.renderPlan.sections.first(where: { $0.title == "Feature Details" }))
        XCTAssertNotNil(field(named: "severity", in: session))
        XCTAssertNil(field(named: "summary", in: session))

        session.setSelectedEnumChoiceID("string:Feature", for: requestTypeField)

        XCTAssertNil(session.renderPlan.sections.first(where: { $0.title == "Bug Details" }))
        XCTAssertNotNil(session.renderPlan.sections.first(where: { $0.title == "Feature Details" }))
        XCTAssertNil(field(named: "severity", in: session))
        XCTAssertNotNil(field(named: "summary", in: session))

        XCTAssertEqual(
            visibleRootBlockLabels(in: session.renderPlan),
            ["request_type", "Feature Details"]
        )
    }
}
