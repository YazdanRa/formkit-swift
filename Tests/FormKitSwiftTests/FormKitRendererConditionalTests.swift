import XCTest
@testable import FormKitSwift

private let hiddenDraftsSchema =
    """
    {
      "title": "Transport",
      "type": "object",
      "properties": {
        "transport": {
          "title": "Transport",
          "enum": ["car", "bike"],
          "default": "car"
        }
      },
      "required": ["transport"],
      "if": {
        "properties": {
          "transport": {
            "const": "car"
          }
        },
        "required": ["transport"]
      },
      "then": {
        "properties": {
          "licensePlate": {
            "type": "string",
            "title": "License Plate"
          }
        },
        "required": ["licensePlate"]
      },
      "else": {
        "properties": {
          "helmetColor": {
            "type": "string",
            "title": "Helmet Color"
          }
        },
        "required": ["helmetColor"]
      }
    }
    """

private let conditionalDisableSchema =
    """
    {
      "title": "Conditional Disable",
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

private let conditionalIgnoreSchema =
    """
    {
      "title": "Conditional Ignore",
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

private let ignoredRenderAnnotationSchema =
    """
    {
      "title": "Ignored Schema Annotation",
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
            "title": "Advanced Code",
            "x-render-behavior": "disable"
          }
        },
        "required": ["advancedCode"]
      }
    }
    """

private let ignoredFormKitAnnotationSchema =
    """
    {
      "title": "Ignored FormKit Annotation",
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
            "title": "Advanced Code",
            "x-formkit-render-behavior": "disable"
          }
        },
        "required": ["advancedCode"]
      }
    }
    """

extension FormKitRendererTests {
    func testIfThenElseUpdatesVisibleFieldsAndSerialization() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: conditionalSchema, instanceJSON: nil)

        XCTAssertEqual(field(named: "mode", in: session)?.enumOptions.map(\.title), ["ABC", "XYZ"])
        XCTAssertNil(field(named: "anotherField", in: session))
        XCTAssertNotNil(field(named: "fallbackField", in: session))

        session.setSelectedEnumChoiceID("string:XYZ", for: tryUnwrapField("mode", in: session))

        XCTAssertNotNil(field(named: "anotherField", in: session))
        XCTAssertNil(field(named: "fallbackField", in: session))

        session.setStringValue("Visible now", for: tryUnwrapField("anotherField", in: session))
        let jsonObject = try decodeJSONObject(session.currentInstanceJSON)

        XCTAssertEqual(jsonObject["mode"] as? String, "XYZ")
        XCTAssertEqual(jsonObject["anotherField"] as? String, "Visible now")
        XCTAssertNil(jsonObject["fallbackField"])
    }

    func testIfThenElseUpdatesVisibleFieldsAndPreservesHiddenDrafts() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: hiddenDraftsSchema, instanceJSON: nil)
        let transportField = tryUnwrapField("transport", in: session)

        XCTAssertNotNil(field(named: "licensePlate", in: session))
        XCTAssertNil(field(named: "helmetColor", in: session))

        session.setSelectedEnumChoiceID("string:bike", for: transportField)

        XCTAssertNil(field(named: "licensePlate", in: session))
        let helmetColorField = tryUnwrapField("helmetColor", in: session)
        session.setStringValue("Matte Black", for: helmetColorField)

        session.setSelectedEnumChoiceID("string:car", for: transportField)
        XCTAssertNotNil(field(named: "licensePlate", in: session))
        XCTAssertNil(field(named: "helmetColor", in: session))

        session.setSelectedEnumChoiceID("string:bike", for: transportField)
        XCTAssertEqual(session.stringValue(for: tryUnwrapField("helmetColor", in: session)), "Matte Black")
    }

    func testConditionalDisableBehaviorKeepsFieldVisibleButNonSerializableUntilApplicable() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: conditionalDisableSchema,
            instanceJSON: nil,
            conditionalRenderBehaviorOverrides: ["#/advancedCode": .disable]
        )
        let modeField = tryUnwrapField("mode", in: session)
        let advancedCodeField = tryUnwrapField("advancedCode", in: session)

        XCTAssertTrue(advancedCodeField.isDisabled)
        session.setStringValue("SHOULD-NOT-STICK", for: advancedCodeField)
        XCTAssertEqual(session.stringValue(for: advancedCodeField), "")
        XCTAssertFalse(session.currentInstanceJSON.contains("advancedCode"))
        XCTAssertTrue(session.validate())

        session.setSelectedEnumChoiceID("string:advanced", for: modeField)

        let activeAdvancedCodeField = tryUnwrapField("advancedCode", in: session)
        XCTAssertFalse(activeAdvancedCodeField.isDisabled)
        session.setStringValue("LIVE-CODE", for: activeAdvancedCodeField)
        XCTAssertTrue(session.currentInstanceJSON.contains("\"advancedCode\" : \"LIVE-CODE\""))
    }

    func testConditionalIgnoreBehaviorKeepsFieldVisibleAndSerializableWhileInactive() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: conditionalIgnoreSchema,
            instanceJSON: nil,
            conditionalRenderBehaviorOverrides: ["/advancedNotes": .ignore]
        )
        let advancedNotesField = tryUnwrapField("advancedNotes", in: session)

        XCTAssertFalse(advancedNotesField.isDisabled)
        XCTAssertTrue(advancedNotesField.isConditionallyInactive)

        session.setStringValue("Carry across branches", for: advancedNotesField)
        XCTAssertTrue(session.currentInstanceJSON.contains("\"advancedNotes\" : \"Carry across branches\""))
        XCTAssertTrue(session.validate())
    }

    func testSchemaRenderBehaviorAnnotationsAreIgnored() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: ignoredRenderAnnotationSchema, instanceJSON: nil)

        XCTAssertNil(field(named: "advancedCode", in: session))
    }

    func testSchemaFormKitPrefixedRenderAnnotationsAreIgnored() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: ignoredFormKitAnnotationSchema, instanceJSON: nil)

        XCTAssertNil(field(named: "advancedCode", in: session))
    }
}
