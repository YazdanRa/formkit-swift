import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitOptionColorTests: XCTestCase {
    func testSelectedColorChoosesTheHigherContrastText() throws {
        for hex in ["#fff", "#f00", "#0f0", "#ff0"] {
            XCTAssertTrue(try XCTUnwrap(FormKitOptionColor(hex: hex)).usesDarkForeground, hex)
        }
        for hex in ["#000", "#00f", "#64748B", "#DC2626"] {
            XCTAssertFalse(try XCTUnwrap(FormKitOptionColor(hex: hex)).usesDarkForeground, hex)
        }
    }

    func testHexColorsAcceptShortAndFullASCIIWithSurroundingWhitespace() throws {
        for hex in ["#aBc", " \n#AAbbCC\t"] {
            let color = try XCTUnwrap(FormKitOptionColor(hex: hex))
            XCTAssertEqual(color.red, 170.0 / 255, accuracy: 0.000_001)
            XCTAssertEqual(color.green, 187.0 / 255, accuracy: 0.000_001)
            XCTAssertEqual(color.blue, 204.0 / 255, accuracy: 0.000_001)
        }
    }

    func testHexColorsRejectUnsupportedLengthsCharactersAndAlpha() {
        let invalidHexValues = [
            "", "abc", "#12", "#1234", "#12345", "#1234567", "#12345678", "#gg0000", "#12 456", "#１２３", "#ＡＢＣＤＥＦ"
        ]
        for hex in invalidHexValues {
            XCTAssertNil(FormKitOptionColor(hex: hex), hex)
        }
    }

    func testStringOptionKeysMatchExactValuesAndPreserveWhitespace() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {"type":"object","properties":{"result":{
              "enum":["Pass","pass"," Pass ","Missing"],
              "x-formkit-ui-component":"line-options-choice",
              "x-formkit-option-color-map":{"Pass":"#0F0","pass":"#f00"," Pass ":" #0000ff "}
            }}}
            """,
            instanceJSON: nil
        )
        XCTAssertTrue(session.renderPlan.isSupported)
        let choices = try XCTUnwrap(session.renderPlan.fields.first).enumOptions
        XCTAssertEqual(choices.map(\.title), ["Pass", "pass", " Pass ", "Missing"])
        XCTAssertEqual(choices[0].color, FormKitOptionColor(hex: "#00ff00"))
        XCTAssertEqual(choices[1].color, FormKitOptionColor(hex: "#ff0000"))
        XCTAssertEqual(choices[2].color, FormKitOptionColor(hex: "#0000ff"))
        XCTAssertNil(choices[3].color)
    }

    func testScalarColorKeysUseCanonicalValuesWithoutChangingSerialization() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {"type":"object","properties":{
              "number":{"type":"number","enum":[1.0,1.5],
                "x-formkit-option-color-map":{"1":"#123","1.5":"#456"}},
              "integer":{"type":"integer","enum":[1,2],
                "x-formkit-option-color-map":{"1":"#789","2":"#abc"}},
              "boolean":{"type":"boolean","enum":[false,true],
                "x-formkit-option-color-map":{"false":"#000","true":"#fff","Off":"#f00"}},
              "nullable":{"type":["string","null"],"enum":["null",null],
                "x-formkit-option-color-map":{"null":"#def"}}
            }}
            """,
            instanceJSON: nil
        )
        XCTAssertTrue(session.renderPlan.isSupported)
        let fields = Dictionary(uniqueKeysWithValues: session.renderPlan.fields.map { ($0.propertyKey, $0) })
        let number = try XCTUnwrap(fields["number"])
        XCTAssertEqual(number.enumOptions.map(\.value), [.number(1), .number(1.5)])
        XCTAssertEqual(
            number.enumOptions.map(\.color), [FormKitOptionColor(hex: "#123"), FormKitOptionColor(hex: "#456")]
        )
        let integer = try XCTUnwrap(fields["integer"])
        XCTAssertEqual(integer.enumOptions[0].color, FormKitOptionColor(hex: "#789"))
        let boolean = try XCTUnwrap(fields["boolean"])
        XCTAssertEqual(
            boolean.enumOptions.map(\.color), [FormKitOptionColor(hex: "#000"), FormKitOptionColor(hex: "#fff")]
        )
        let nullable = try XCTUnwrap(fields["nullable"])
        XCTAssertEqual(nullable.enumOptions.map(\.value), [.string("null"), .null])
        XCTAssertTrue(nullable.enumOptions.allSatisfy { $0.color == FormKitOptionColor(hex: "#def") })

        for field in session.renderPlan.fields {
            session.setSelectedEnumChoiceID(field.enumOptions.last?.id, for: field)
        }
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["number", "integer", "boolean", "nullable"])
        XCTAssertEqual(object["number"] as? Double, 1.5)
        XCTAssertEqual(object["integer"] as? Int, 2)
        XCTAssertEqual(object["boolean"] as? Bool, true)
        XCTAssertTrue(object["nullable"] is NSNull)
        XCTAssertTrue(session.validate())
    }

    func testInvalidOrMissingColorMetadataDoesNotInvalidateEnumFields() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {"type":"object","properties":{
              "invalidColors":{"enum":["A","B","C","D"],
                "x-formkit-option-color-map":{"A":"#invalid","B":123,"C":null,"D":{"hex":"#fff"}}},
              "invalidMap":{"enum":["A","B"],"x-formkit-option-color-map":["#fff","#000"]},
              "missing":{"enum":["A","B"]}
            }}
            """,
            instanceJSON: nil
        )
        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertEqual(session.renderPlan.fields.count, 3)
        for field in session.renderPlan.fields {
            XCTAssertTrue(field.enumOptions.allSatisfy { $0.color == nil }, field.propertyKey)
            session.setSelectedEnumChoiceID(field.enumOptions.first?.id, for: field)
        }
        XCTAssertTrue(session.validate())
    }

    func testColorsSurviveLocalReferencesAndConditionalOverrides() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type":"object",
              "$defs":{"result":{"enum":["Pass","Fail"],
                "x-formkit-ui-component":"line-options-choice",
                "x-formkit-option-color-map":{"Pass":"#0f0","Fail":"#f00"}}},
              "properties":{
                "enabled":{"type":"boolean","default":false},
                "result":{"$ref":"#/$defs/result"}
              },
              "if":{"properties":{"enabled":{"const":true}},"required":["enabled"]},
              "then":{"properties":{"result":{"x-formkit-option-color-map":{"Pass":"#00f"}}}}
            }
            """,
            instanceJSON: nil
        )
        XCTAssertTrue(session.renderPlan.isSupported)
        let initial = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "result" })
        XCTAssertEqual(initial.enumOptions[0].color, FormKitOptionColor(hex: "#0f0"))
        let enabled = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "enabled" })
        session.setBooleanValue(true, for: enabled)
        let active = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "result" })
        XCTAssertEqual(active.enumOptions[0].color, FormKitOptionColor(hex: "#00f"))
        XCTAssertEqual(active.enumOptions[1].color, FormKitOptionColor(hex: "#f00"))
        XCTAssertEqual(initial.enumOptions.map(\.id), active.enumOptions.map(\.id))
    }
}
