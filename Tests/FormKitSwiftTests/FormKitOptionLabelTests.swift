import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitOptionLabelTests: XCTestCase {
    func testLabelsChangePresentationWithoutChangingSelectionReopeningOrClearing() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: shippingSchema)
        let field = try XCTUnwrap(session.renderPlan.fields.first)
        XCTAssertEqual(field.enumOptions.map(\.title), [
            "express", "insured", "Express and insured", "economy", "standard", "pickup"
        ])
        let combined = try XCTUnwrap(field.enumOptions.first { $0.value == .string("express|insured") })
        XCTAssertEqual(combined.id, "string:express|insured")
        XCTAssertEqual(field.enumOptions.map(\.color), [
            FormKitOptionColor(hex: "#2563EB"), FormKitOptionColor(hex: "#16A34A"), nil, nil, nil, nil
        ])
        session.setSelectedEnumChoiceID(combined.id, for: field)
        XCTAssertTrue(session.validate())
        XCTAssertEqual(try object(session)["shippingMethod"] as? String, "express|insured")

        let reopened = FormKitRenderer().makeFormSession(
            schemaJSON: shippingSchema, instanceJSON: session.currentInstanceJSON
        )
        let reopenedField = try XCTUnwrap(reopened.renderPlan.fields.first)
        XCTAssertEqual(reopened.selectedEnumChoiceID(for: reopenedField), combined.id)
        XCTAssertEqual(reopenedField.enumOptions, field.enumOptions)
        reopened.setSelectedEnumChoiceID(nil, for: reopenedField)
        XCTAssertNil(try object(reopened)["shippingMethod"])

        for legacy in ["economy", "standard", "pickup"] {
            let old = FormKitRenderer().makeFormSession(
                schemaJSON: shippingSchema, instanceJSON: "{\"shippingMethod\":\"\(legacy)\"}"
            )
            let oldField = try XCTUnwrap(old.renderPlan.fields.first)
            XCTAssertEqual(old.selectedEnumChoiceID(for: oldField), "string:\(legacy)")
            XCTAssertEqual(try object(old)["shippingMethod"] as? String, legacy)
        }
    }

    func testLabelKeysMatchExactValuesAndTrimOnlyPresentationText() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: #"""
        {"type":"object","properties":{"result":{
          "enum":["Pass","pass"," Pass ","Missing"],
          "x-formkit-option-label-map":{"Pass":"Approved","pass":"lowercase"," Pass ":"  Padded  "}
        }}}
        """#)
        XCTAssertTrue(session.renderPlan.isSupported)
        let choices = try XCTUnwrap(session.renderPlan.fields.first).enumOptions
        XCTAssertEqual(choices.map(\.title), ["Approved", "lowercase", "Padded", "Missing"])
        XCTAssertEqual(choices.map(\.value), [.string("Pass"), .string("pass"), .string(" Pass "), .string("Missing")])
        XCTAssertEqual(choices.map(\.id), ["string:Pass", "string:pass", "string: Pass ", "string:Missing"])
    }

    func testScalarLabelKeysUseCanonicalValuesWithoutChangingSerialization() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: #"""
        {"type":"object","properties":{
          "number":{"type":"number","enum":[1.0,1.5],
            "x-formkit-option-label-map":{"1":"One","1.5":"One and a half"}},
          "integer":{"type":"integer","enum":[1,2],
            "x-formkit-option-label-map":{"1":"First","2":"Second"}},
          "boolean":{"type":"boolean","enum":[false,true],
            "x-formkit-option-label-map":{"false":"Disabled","true":"Enabled"}},
          "nullable":{"type":["string","null"],"enum":["null",null],
            "x-formkit-option-label-map":{"null":"No selection"}}
        }}
        """#)
        let fields = Dictionary(uniqueKeysWithValues: session.renderPlan.fields.map { ($0.propertyKey, $0) })
        XCTAssertEqual(fields["number"]?.enumOptions.map(\.title), ["One", "One and a half"])
        XCTAssertEqual(fields["integer"]?.enumOptions.map(\.title), ["First", "Second"])
        XCTAssertEqual(fields["boolean"]?.enumOptions.map(\.title), ["Disabled", "Enabled"])
        XCTAssertEqual(fields["nullable"]?.enumOptions.map(\.title), ["No selection", "No selection"])
        for field in session.renderPlan.fields {
            session.setSelectedEnumChoiceID(field.enumOptions.last?.id, for: field)
        }
        XCTAssertTrue(session.validate())
        let values = try object(session)
        XCTAssertEqual(values["number"] as? Double, 1.5)
        XCTAssertEqual(values["integer"] as? Int, 2)
        XCTAssertEqual(values["boolean"] as? Bool, true)
        XCTAssertTrue(values["nullable"] is NSNull)
    }

    func testMalformedMissingAndBlankLabelsUseTheOriginalTitle() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: #"""
        {"type":"object","properties":{
          "result":{"enum":["A","B","C","D","E","F","G"],
            "x-formkit-option-label-map":{"A":"","B":"  \n ","C":123,"D":null,
              "E":{"title":"Nested"},"F":"Friendly","unknown":"Ignored"}},
          "invalidMap":{"enum":["A","B"],"x-formkit-option-label-map":["First","Second"]},
          "missingMap":{"enum":["A","B"]}
        }}
        """#)
        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertTrue(session.validate())
        let fields = Dictionary(uniqueKeysWithValues: session.renderPlan.fields.map { ($0.propertyKey, $0) })
        XCTAssertEqual(fields["result"]?.enumOptions.map(\.title), ["A", "B", "C", "D", "E", "Friendly", "G"])
        XCTAssertEqual(fields["invalidMap"]?.enumOptions.map(\.title), ["A", "B"])
        XCTAssertEqual(fields["missingMap"]?.enumOptions.map(\.title), ["A", "B"])
    }

    private func object(_ session: FormKitSession) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8)) as? [String: Any])
    }

    private var shippingSchema: String {
        #"""
        {"type":"object","properties":{"shippingMethod":{"type":"string",
          "enum":["express","insured","express|insured","economy","standard","pickup"],
          "x-formkit-ui-component":"line-options-choice",
          "x-formkit-option-color-map":{"express":"#2563EB","insured":"#16A34A"},
          "x-formkit-option-label-map":{"express|insured":"Express and insured"}
        }}}
        """#
    }
}
