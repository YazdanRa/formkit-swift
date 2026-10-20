import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitOptionColorCompositionTests: XCTestCase {
    private let optionNames = ["required", "properties", "$defs", "definitions", "enum", "Pass"]

    func testReferenceSiblingColorMapsMergeLiteralOptionKeys() throws {
        for option in optionNames {
            let session = FormKitRenderer().makeFormSession(
                schemaJSON: """
                {"type":"object",
                  "$defs":{"result":{"enum":["\(option)","unchanged","added"],
                    "x-formkit-option-color-map":{"\(option)":"#f00","unchanged":"#abc"}}},
                  "properties":{"result":{"$ref":"#/$defs/result",
                    "x-formkit-option-color-map":{"\(option)":"#0f0","added":"#00f"}}}
                }
                """,
                instanceJSON: nil
            )
            XCTAssertTrue(session.renderPlan.isSupported, option)
            let field = try XCTUnwrap(session.renderPlan.fields.first)
            XCTAssertEqual(field.enumOptions.map(\.title), [option, "unchanged", "added"])
            XCTAssertEqual(field.enumOptions.map(\.color), [
                FormKitOptionColor(hex: "#0f0"),
                FormKitOptionColor(hex: "#abc"),
                FormKitOptionColor(hex: "#00f")
            ], option)
        }
    }

    func testConditionalColorOverridesOnReferencesPreserveLiteralKeysAndReset() throws {
        for option in optionNames {
            let session = FormKitRenderer().makeFormSession(
                schemaJSON: """
                {"type":"object",
                  "$defs":{"result":{"enum":["\(option)","unchanged","added"],
                    "x-formkit-option-color-map":{"\(option)":"#f00","unchanged":"#abc"}}},
                  "properties":{
                    "enabled":{"type":"boolean","default":false},
                    "result":{"$ref":"#/$defs/result"}
                  },
                  "if":{"properties":{"enabled":{"const":true}},"required":["enabled"]},
                  "then":{"properties":{"result":{
                    "x-formkit-option-color-map":{"\(option)":"#0f0","added":"#00f"}}}},
                  "else":{"properties":{"result":{
                    "x-formkit-option-color-map":{"\(option)":"#fff"}}}}
                }
                """,
                instanceJSON: nil
            )
            XCTAssertTrue(session.renderPlan.isSupported, option)
            let enabled = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "enabled" })
            let initial = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "result" })
            XCTAssertEqual(initial.enumOptions.map(\.color), [
                FormKitOptionColor(hex: "#fff"), FormKitOptionColor(hex: "#abc"), nil
            ], option)

            session.setBooleanValue(true, for: enabled)
            let active = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "result" })
            XCTAssertEqual(active.enumOptions.map(\.color), [
                FormKitOptionColor(hex: "#0f0"),
                FormKitOptionColor(hex: "#abc"),
                FormKitOptionColor(hex: "#00f")
            ], option)
            XCTAssertEqual(active.enumOptions.map(\.id), initial.enumOptions.map(\.id), option)

            session.setBooleanValue(false, for: enabled)
            let restored = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "result" })
            XCTAssertEqual(restored.enumOptions.map(\.color), initial.enumOptions.map(\.color), option)
        }
    }

    func testAllOfColorMapsKeepSchemaRequiredAndPropertyMerging() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {"type":"object",
              "properties":{"result":{"enum":["required","properties","Pass"],
                "x-formkit-option-color-map":{"required":"#f00","properties":"#abc","Pass":"#000"}}},
              "required":["result"],
              "allOf":[
                {"properties":{
                  "result":{"x-formkit-option-color-map":{"required":"#0f0","Pass":"#fff"}},
                  "notes":{"type":"string"}
                },"required":["notes"]},
                {"properties":{"result":{"x-formkit-option-color-map":{"required":"#00f"}}}}
              ]
            }
            """,
            instanceJSON: nil
        )
        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertEqual(Set(session.renderPlan.fields.map(\.propertyKey)), ["result", "notes"])
        XCTAssertTrue(session.renderPlan.fields.allSatisfy(\.isRequired))
        let result = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "result" })
        XCTAssertEqual(result.enumOptions.map(\.color), [
            FormKitOptionColor(hex: "#00f"), FormKitOptionColor(hex: "#abc"), FormKitOptionColor(hex: "#fff")
        ])
        XCTAssertFalse(session.validate())
        session.setSelectedEnumChoiceID(result.enumOptions.first?.id, for: result)
        let notes = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "notes" })
        session.setStringValue("Details", for: notes)
        XCTAssertTrue(session.validate())
    }
}
