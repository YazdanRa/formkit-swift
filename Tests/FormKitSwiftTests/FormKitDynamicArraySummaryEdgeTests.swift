import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicArraySummaryEdgeTests: XCTestCase {
    func testConditionalCollectionAddsAttentionWithoutBecomingABaseQuestion() throws {
        for behavior in [FormKitConditionalRenderBehavior.hide, .disable] {
            let session = FormKitRenderer(defaultConditionalRenderBehavior: behavior)
                .makeFormSession(schemaJSON: conditionalSchema)
            XCTAssertTrue(session.formSummary().missingRequiredArraySections.isEmpty)
            XCTAssertEqual(session.formSummary().pages.first?.total, 1)
            let enabled = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/first/enabled" })
            session.setBooleanValue(true, for: enabled)
            XCTAssertEqual(session.formSummary().missingRequiredArraySections.map(\.pointer), ["#/first/equipment"])
            XCTAssertEqual(session.formSummary().pages.first?.total, 1)
            XCTAssertEqual(session.formSummary().pages.first?.status, .needsAttention)
            let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/first/equipment" })
            session.setArrayValue([.string("")], for: section)
            XCTAssertTrue(session.formSummary().missingRequiredArraySections.isEmpty)
            XCTAssertEqual(session.formSummary().pages.first?.status, .done)
            session.setBooleanValue(false, for: enabled)
            XCTAssertTrue(session.formSummary().missingRequiredArraySections.isEmpty)
            XCTAssertTrue(session.validate())
        }
    }

    func testOrdinaryAndIncompatibleArraysKeepTheirExistingRowQuestionCounts() throws {
        for (component, items) in [("", #"{"type":"string"}"#),
                                    ("dynamic-options", #"{"type":["string","null"]}"#)]
        {
            let definition = #"""
            {"type":"object","x-formkit-layout":"section-pages","properties":{
              "first":{"type":"object","x-formkit-order":0,"properties":{
                "equipment":{"type":"array","items":ITEMS,"x-formkit-ui-component":"COMPONENT"}}},
              "second":{"type":"object","x-formkit-order":1,"properties":{"note":{"type":"string"}}}}}
            """#
                .replacingOccurrences(of: "ITEMS", with: items)
                .replacingOccurrences(of: "COMPONENT", with: component)
            let session = FormKitRenderer().makeFormSession(
                schemaJSON: definition, instanceJSON: #"{"first":{"equipment":["one","two"]}}"#
            )
            XCTAssertEqual(session.formSummary().pages.first?.total, 2)
            XCTAssertEqual(session.formSummary().pages.first?.answered, 2)
            XCTAssertTrue(session.formSummary().missingRequiredArraySections.isEmpty)
        }
    }

    func testPresentBelowMinimumArrayDoesNotReceiveASiblingRequiredError() throws {
        let definition = #"""
        {"type":"object","required":["equipment","other"],"properties":{
          "other":{"type":"string"},"equipment":{"type":"array","minItems":1,"items":{"type":"string"},
            "x-formkit-ui-component":"dynamic-options"}}}
        """#
        let session = FormKitRenderer().makeFormSession(schemaJSON: definition,
                                                        instanceJSON: #"{"equipment":[]}"#)
        XCTAssertFalse(session.validate())
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/equipment" })
        let errors = session.errorMessages(for: section)
        XCTAssertEqual(errors.count, 1)
        XCTAssertNotEqual(errors.first, "This field is required.")
        XCTAssertTrue(errors.allSatisfy(session.toolValidationMessages().contains))
    }

    private var conditionalSchema: String {
        #"""
        {"type":"object","x-formkit-layout":"section-pages","required":["first"],"properties":{
          "first":{"type":"object","title":"First","x-formkit-order":0,"properties":{
            "enabled":{"type":"boolean","title":"Enable"},
            "equipment":{"type":"array","title":"Equipment","minItems":1,"items":{"type":"string"},
              "x-formkit-ui-component":"dynamic-options"}},
            "if":{"properties":{"enabled":{"const":true}},"required":["enabled"]},
            "then":{"required":["equipment"],"properties":{"equipment":{"type":"array","title":"Equipment",
              "minItems":1,"items":{"type":"string"},"x-formkit-ui-component":"dynamic-options"}}}},
          "second":{"type":"object","title":"Second","x-formkit-order":1,"properties":{"note":{"type":"string"}}}}}
        """#
    }
}
