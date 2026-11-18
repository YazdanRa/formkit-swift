import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitOptionLabelToolTests: XCTestCase {
    func testMappedLabelsCannotShadowCanonicalToolValues() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: #"""
        {"type":"object","properties":{"result":{"enum":["A","B"],
          "x-formkit-option-label-map":{"A":"B"}
        }}}
        """#)
        XCTAssertEqual(session.makeToolContext().fields.first?.enumOptions, ["A", "B"])
        let result = session.applyToolEdits([.init(pointer: "/result", operation: .set, value: .string("B"))])
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        XCTAssertEqual(result.appliedEdits.first?.value, .string("B"))
        XCTAssertEqual(result.context.currentValues["/result"], .string("B"))
        XCTAssertEqual(try object(session)["result"] as? String, "B")
    }

    func testDisplayLabelsAreNotNewToolAliasesAndExistingBooleanAliasesRemain() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: #"""
        {"type":"object","properties":{
          "result":{"enum":["A","B"],"x-formkit-option-label-map":{"A":"Friendly"}},
          "enabled":{"type":"boolean","enum":[false,true],
            "x-formkit-option-label-map":{"false":"No","true":"Yes"}}
        }}
        """#)
        let result = session.applyToolEdits([.init(pointer: "/result", operation: .set, value: .string("Friendly"))])
        XCTAssertEqual(result.rejectedEdits.first?.reason, "invalid_choice")
        XCTAssertNil(try object(session)["result"])
        let enabled = try XCTUnwrap(session.makeToolContext().fields.first { $0.pointer == "/enabled" })
        XCTAssertEqual(enabled.enumOptions, [
            FormKitFieldDescriptor.PrimitiveValue.boolean(false).title,
            FormKitFieldDescriptor.PrimitiveValue.boolean(true).title
        ])
        let alias = FormKitFieldDescriptor.PrimitiveValue.boolean(true).title
        let applied = session.applyToolEdits([.init(pointer: "/enabled", operation: .set, value: .string(alias))])
        XCTAssertTrue(applied.rejectedEdits.isEmpty)
        XCTAssertEqual(applied.context.currentValues["/enabled"], .boolean(true))
    }

    func testCombinedAndLegacyValuesRoundtripThroughToolsWithoutPresentationLabels() throws {
        let schema = #"""
        {"type":"object","properties":{"priority":{"type":"string",
          "enum":["Critical","Schedule Impact","Critical|Schedule Impact","High","Medium","Low"],
          "x-formkit-option-label-map":{"Critical|Schedule Impact":"Critical and Schedule Impact"}
        }}}
        """#
        for value in ["Critical|Schedule Impact", "High", "Medium", "Low"] {
            let session = FormKitRenderer().makeFormSession(schemaJSON: schema)
            XCTAssertEqual(session.makeToolContext().fields.first?.enumOptions, [
                "Critical", "Schedule Impact", "Critical|Schedule Impact", "High", "Medium", "Low"
            ])
            let result = session.applyToolEdits([.init(pointer: "/priority", operation: .set, value: .string(value))])
            XCTAssertTrue(result.rejectedEdits.isEmpty, value)
            XCTAssertEqual(result.appliedEdits.first?.value, .string(value))
            XCTAssertEqual(try object(session)["priority"] as? String, value)
            let reopened = FormKitRenderer().makeFormSession(
                schemaJSON: schema, instanceJSON: session.currentInstanceJSON
            )
            XCTAssertEqual(reopened.makeToolContext().currentValues["/priority"], .string(value))
            let cleared = reopened.applyToolEdits([.init(pointer: "/priority", operation: .clear)])
            XCTAssertTrue(cleared.rejectedEdits.isEmpty)
            XCTAssertNil(try object(reopened)["priority"])
        }
    }

    func testExactCanonicalValueWinsBeforeExistingCaseInsensitiveAliases() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: #"""
        {"type":"object","properties":{"result":{"enum":["a","A"],
          "x-formkit-option-label-map":{"a":"First","A":"Second"}
        }}}
        """#)
        let result = session.applyToolEdits([.init(pointer: "/result", operation: .set, value: .string("A"))])
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        XCTAssertEqual(try object(session)["result"] as? String, "A")
    }

    private func object(_ session: FormKitSession) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8)) as? [String: Any])
    }
}
