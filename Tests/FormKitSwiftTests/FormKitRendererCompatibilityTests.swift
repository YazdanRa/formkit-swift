import XCTest
@testable import FormKitSwift

private let conditionalConstAnnotationSchema =
    """
    {
      "type": "object",
      "properties": {
        "selection": {
          "type": "object",
          "properties": {
            "details": {
              "type": "object",
              "properties": {
                "x-formkit-render-behavior": { "type": "string" },
                "x-formkit-conditional-state": { "type": "string" }
              }
            }
          }
        }
      },
      "if": {
        "properties": {
          "selection": {
            "const": {
              "details": {
                "x-formkit-render-behavior": "disable",
                "x-formkit-conditional-state": "inactive"
              }
            }
          }
        },
        "required": ["selection"]
      },
      "then": {
        "properties": {
          "matched": {
            "type": "string",
            "title": "Matched"
          }
        }
      }
    }
    """

private let conditionalConstAnnotationInstance =
    """
    {
      "selection": {
        "details": {
          "x-formkit-render-behavior": "disable",
          "x-formkit-conditional-state": "inactive"
        }
      }
    }
    """

extension FormKitRendererTests {
    func testConditionalConstPreservesAnnotationNamedInstanceData() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: conditionalConstAnnotationSchema,
            instanceJSON: conditionalConstAnnotationInstance
        )

        XCTAssertNotNil(field(named: "matched", in: session))
    }

    func testLocalReferenceTargetsIgnoreRenderAnnotations() throws {
        let schema =
            """
            {
              "type": "object",
              "x-local-schemas": {
                "value": {
                  "type": "string",
                  "x-formkit-render-behavior": "disable",
                  "x-formkit-conditional-state": "inactive"
                }
              },
              "properties": {
                "value": {
                  "$ref": "#/x-local-schemas/value"
                }
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let valueField = try XCTUnwrap(field(named: "value", in: session))

        XCTAssertEqual(valueField.renderBehavior, .hide)
        XCTAssertEqual(valueField.conditionalState, .active)
        XCTAssertFalse(valueField.isDisabled)
    }

    func testSchemaPropertiesNamedLikeRenderAnnotationsStillRenderAndValidate() throws {
        let schema =
            """
            {
              "title": "Annotation Named Fields",
              "type": "object",
              "properties": {
                "x-render-behavior": {
                  "type": "string",
                  "title": "Render Behavior"
                },
                "x-conditions": {
                  "type": "string",
                  "title": "Conditions"
                }
              },
              "required": ["x-render-behavior", "x-conditions"]
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let renderBehaviorField = tryUnwrapField("x-render-behavior", in: session)
        let conditionsField = tryUnwrapField("x-conditions", in: session)

        XCTAssertEqual(renderBehaviorField.pointer, "#/x-render-behavior")
        XCTAssertEqual(conditionsField.pointer, "#/x-conditions")
        XCTAssertFalse(session.validate())

        session.setStringValue("disable", for: renderBehaviorField)
        session.setStringValue("Bug", for: conditionsField)

        XCTAssertTrue(session.validate())
        let object = try decodeJSONObject(session.currentInstanceJSON)
        XCTAssertEqual(object["x-render-behavior"] as? String, "disable")
        XCTAssertEqual(object["x-conditions"] as? String, "Bug")
    }

    func testRendererAcceptsEscapedNonBMPUnicodeInSchemaStrings() throws {
        let schema =
            """
            {
              "title": "Emoji \\uD83D\\uDE00 Form",
              "type": "object",
              "properties": {
                "name": {
                  "title": "Name",
                  "type": "string"
                }
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertEqual(session.renderPlan.title, "Emoji 😀 Form")
    }
}

private let ignoredXConditionsSchema =
    """
    {
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
          "description": "Shown only for bug reports",
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
          "required": ["severity"],
          "x-conditions": [
            {
              "dependsOn": "request_type",
              "equals": "Bug"
            }
          ]
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
            },
            "required": ["name"]
          }
        }
      },
      "required": ["request_type"]
    }
    """

private let ignoredArrayItemXConditionsSchema =
    """
    {
      "title": "Entries",
      "type": "object",
      "properties": {
        "entries": {
          "title": "Entries",
          "type": "array",
          "items": {
            "title": "Entry",
            "type": "object",
            "properties": {
              "kind": {
                "title": "Kind",
                "type": "string",
                "enum": ["Bug", "Feature"]
              },
              "details": {
                "title": "Details",
                "type": "string"
              }
            },
            "x-conditions": [
              {
                "dependsOn": "kind",
                "equals": "Bug"
              }
            ]
          }
        }
      }
    }
    """

private let ignoredArrayItemXConditionsInstance =
    """
    {
      "entries": [
        {
          "kind": "Bug",
          "details": "Keep"
        },
        {
          "kind": "Feature",
          "details": "Hide"
        }
      ]
    }
    """

extension FormKitRendererTests {
    func testXConditionsAreIgnoredAsNonNativeAnnotations() throws {
        let featureInstance =
            """
            {
              "request_type": "Feature"
            }
            """

        let session = FormKitRenderer().makeFormSession(
            schemaJSON: ignoredXConditionsSchema,
            instanceJSON: featureInstance
        )

        XCTAssertNotNil(session.renderPlan.sections.first(where: { $0.title == "Bug Details" }))
        XCTAssertNotNil(field(named: "severity", in: session))
        XCTAssertNotNil(field(named: "steps", in: session))

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

    func testArrayItemRootXConditionsAreIgnored() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: ignoredArrayItemXConditionsSchema,
            instanceJSON: ignoredArrayItemXConditionsInstance
        )

        let entriesSection = try XCTUnwrap(
            session.renderPlan.sections.first(where: {
                $0.pointer == "#/entries" && $0.arrayDescriptor != nil
            })
        )
        let descriptor = try XCTUnwrap(entriesSection.arrayDescriptor)

        XCTAssertEqual(descriptor.rows.map(\.pointer), ["#/entries/0", "#/entries/1"])
        XCTAssertEqual(descriptor.rows.count, 2)
    }

    func testMalformedXConditionsAreIgnored() throws {
        let schema =
            """
            {
              "title": "Malformed Annotation",
              "type": "object",
              "properties": {
                "name": {
                  "title": "Name",
                  "type": "string",
                  "x-conditions": {
                    "dependsOn": "mode",
                    "equals": "advanced"
                  }
                }
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertNotNil(field(named: "name", in: session))
    }
}
