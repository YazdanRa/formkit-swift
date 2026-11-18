import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitOptionLabelCompositionTests: XCTestCase {
    private let literalKeys = ["required", "properties", "$defs", "definitions", "enum", "Pass"]

    func testReferenceSiblingLabelMapsMergeLiteralKeys() throws {
        for key in literalKeys {
            let session = FormKitRenderer().makeFormSession(schemaJSON: """
            {"type":"object",
              "$defs":{"result":{"enum":["\(key)","unchanged","added"],
                "x-formkit-option-label-map":{"\(key)":"Original","unchanged":"Unchanged"}}},
              "properties":{"result":{"$ref":"#/$defs/result",
                "x-formkit-option-label-map":{"\(key)":"Override","added":"Added"}}}
            }
            """)
            XCTAssertTrue(session.renderPlan.isSupported, key)
            let field = try XCTUnwrap(session.renderPlan.fields.first)
            XCTAssertEqual(field.enumOptions.map(\.title), ["Override", "Unchanged", "Added"], key)
            XCTAssertEqual(field.enumOptions.map(\.value), [.string(key), .string("unchanged"), .string("added")])
        }
    }

    func testConditionalLabelOverridesPreserveReferenceMapsAndReset() throws {
        for key in literalKeys {
            let session = FormKitRenderer().makeFormSession(schemaJSON: """
            {"type":"object",
              "$defs":{"result":{"enum":["\(key)","unchanged","added"],
                "x-formkit-option-label-map":{"\(key)":"Original","unchanged":"Unchanged"}}},
              "properties":{
                "enabled":{"type":"boolean","default":false},
                "result":{"$ref":"#/$defs/result"}
              },
              "if":{"properties":{"enabled":{"const":true}},"required":["enabled"]},
              "then":{"properties":{"result":{
                "x-formkit-option-label-map":{"\(key)":"Enabled","added":"Added"}}}},
              "else":{"properties":{"result":{
                "x-formkit-option-label-map":{"\(key)":"Disabled"}}}}
            }
            """)
            XCTAssertTrue(session.renderPlan.isSupported, key)
            let initial = try field("result", in: session)
            XCTAssertEqual(initial.enumOptions.map(\.title), ["Disabled", "Unchanged", "added"], key)

            session.setBooleanValue(true, for: try field("enabled", in: session))
            let active = try field("result", in: session)
            XCTAssertEqual(active.enumOptions.map(\.title), ["Enabled", "Unchanged", "Added"], key)
            XCTAssertEqual(active.enumOptions.map(\.id), initial.enumOptions.map(\.id), key)
            session.setSelectedEnumChoiceID(active.enumOptions.first?.id, for: active)

            session.setBooleanValue(false, for: try field("enabled", in: session))
            let restored = try field("result", in: session)
            XCTAssertEqual(restored.enumOptions.map(\.title), initial.enumOptions.map(\.title), key)
            XCTAssertEqual(session.selectedEnumChoiceID(for: restored), initial.enumOptions.first?.id, key)
        }
    }

    func testAllOfLabelMapsDoNotInterfereWithRequiredOrPropertyMerging() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: #"""
        {"type":"object",
          "properties":{"result":{"enum":["required","properties","Pass"],
            "x-formkit-option-label-map":{"required":"Original","properties":"Property","Pass":"Passed"}}},
          "required":["result"],
          "allOf":[
            {"properties":{
              "result":{"x-formkit-option-label-map":{"required":"First override","Pass":"Approved"}},
              "notes":{"type":"string"}
            },"required":["notes"]},
            {"properties":{"result":{"x-formkit-option-label-map":{"required":"Final override"}}}}
          ]
        }
        """#)
        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertEqual(Set(session.renderPlan.fields.map(\.propertyKey)), ["result", "notes"])
        XCTAssertTrue(session.renderPlan.fields.allSatisfy(\.isRequired))
        let result = try field("result", in: session)
        XCTAssertEqual(result.enumOptions.map(\.title), ["Final override", "Property", "Approved"])
        XCTAssertFalse(session.validate())
        session.setSelectedEnumChoiceID(result.enumOptions.first?.id, for: result)
        session.setStringValue("Details", for: try field("notes", in: session))
        XCTAssertTrue(session.validate())
    }

    private func field(_ key: String, in session: FormKitSession) throws -> FormKitFieldDescriptor {
        try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == key })
    }
}
