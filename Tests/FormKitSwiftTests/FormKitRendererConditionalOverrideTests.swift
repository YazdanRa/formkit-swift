import XCTest
@testable import FormKitSwift

private let conditionalArrayWildcardSchema =
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
                "enum": ["basic", "advanced"]
              }
            },
            "required": ["kind"],
            "if": {
              "properties": {
                "kind": { "const": "advanced" }
              },
              "required": ["kind"]
            },
            "then": {
              "properties": {
                "notes": {
                  "title": "Notes",
                  "type": "string"
                }
              }
            }
          }
        }
      }
    }
    """

private let conditionalArrayWildcardInstance =
    """
    {
      "entries": [
        { "kind": "basic" },
        { "kind": "basic" }
      ]
    }
    """

private let conditionalDisabledArraySchema =
    """
    {
      "title": "Conditional Array",
      "type": "object",
      "properties": {
        "mode": {
          "title": "Mode",
          "enum": ["basic", "advanced"],
          "default": "basic"
        }
      },
      "required": ["mode"],
      "if": {
        "properties": {
          "mode": { "const": "advanced" }
        },
        "required": ["mode"]
      },
      "then": {
        "properties": {
          "crew": {
            "type": "array",
            "title": "Crew",
            "items": {
              "type": "string",
              "title": "Crew Member"
            }
          }
        }
      }
    }
    """

extension FormKitRendererTests {
    func testRendererInitializerConditionalRenderBehaviorOverridesApplyToSessions() throws {
        let schema =
            """
            {
              "title": "Initializer Overrides",
              "type": "object",
              "properties": {
                "mode": {
                  "title": "Mode",
                  "enum": ["basic", "advanced"],
                  "default": "basic"
                }
              },
              "required": ["mode"],
              "if": {
                "properties": {
                  "mode": { "const": "advanced" }
                },
                "required": ["mode"]
              },
              "then": {
                "properties": {
                  "advancedCode": {
                    "type": "string",
                    "title": "Advanced Code"
                  }
                },
                "required": ["advancedCode"]
              }
            }
            """

        let session = FormKitRenderer(
            conditionalRenderBehaviorOverrides: ["#/advancedCode": .disable]
        ).makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let advancedCodeField = tryUnwrapField("advancedCode", in: session)

        XCTAssertTrue(advancedCodeField.isDisabled)
        XCTAssertFalse(advancedCodeField.shouldSerialize)
    }

    func testProtocolConditionalRenderBehaviorOverridesApplyToSessions() throws {
        let schema =
            """
            {
              "title": "Protocol Overrides",
              "type": "object",
              "properties": {
                "mode": {
                  "title": "Mode",
                  "enum": ["basic", "advanced"],
                  "default": "basic"
                }
              },
              "required": ["mode"],
              "if": {
                "properties": {
                  "mode": { "const": "advanced" }
                },
                "required": ["mode"]
              },
              "then": {
                "properties": {
                  "advancedNotes": {
                    "type": "string",
                    "title": "Advanced Notes"
                  }
                }
              }
            }
            """

        let renderer: any FormKitRendering = FormKitRenderer()
        let session = renderer.makeFormSession(
            schemaJSON: schema,
            instanceJSON: nil,
            defaultConditionalRenderBehavior: nil,
            conditionalRenderBehaviorOverrides: ["#/advancedNotes": .ignore],
            validationBehavior: .revalidateAfterFirstAttempt
        )
        let advancedNotesField = tryUnwrapField("advancedNotes", in: session)

        XCTAssertTrue(advancedNotesField.isConditionallyInactive)
        XCTAssertFalse(advancedNotesField.isDisabled)
        XCTAssertTrue(advancedNotesField.shouldSerialize)
    }

    func testConditionalRenderBehaviorOverridesSupportArrayRowWildcards() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: conditionalArrayWildcardSchema,
            instanceJSON: conditionalArrayWildcardInstance,
            conditionalRenderBehaviorOverrides: ["#/entries/*/notes": .ignore]
        )
        let notesFields = session.renderPlan.fields.filter { $0.propertyKey == "notes" }

        XCTAssertEqual(notesFields.map(\.pointer), ["#/entries/0/notes", "#/entries/1/notes"])
        XCTAssertTrue(notesFields.allSatisfy(\.isConditionallyInactive))
        XCTAssertTrue(notesFields.allSatisfy(\.shouldSerialize))
    }

    func testConditionalDisableBehaviorOnArraySectionBlocksEditsWhileInactive() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: conditionalDisabledArraySchema,
            instanceJSON: nil,
            conditionalRenderBehaviorOverrides: ["#/crew": .disable]
        )
        let modeField = tryUnwrapField("mode", in: session)
        let disabledCrewSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.title == "Crew" }))

        XCTAssertTrue(disabledCrewSection.isDisabled)
        session.appendArrayRow(to: disabledCrewSection)
        XCTAssertNil(try decodeJSONObject(session.currentInstanceJSON)["crew"])

        session.setSelectedEnumChoiceID("string:advanced", for: modeField)

        let activeCrewSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.title == "Crew" }))
        XCTAssertFalse(activeCrewSection.isDisabled)
        session.appendArrayRow(to: activeCrewSection)

        let updatedCrewSection = try XCTUnwrap(
            session.renderPlan.sections.first(where: { $0.id == activeCrewSection.id })
        )
        let crewDescriptor = try XCTUnwrap(updatedCrewSection.arrayDescriptor)
        XCTAssertEqual(crewDescriptor.rows.count, 1)
    }
}
