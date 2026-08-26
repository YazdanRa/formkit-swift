import XCTest
@testable import FormKitSwift

extension FormKitReviewRegressionTests {
    func testLegacyRendererConformanceUsesNewOverrideOverload() {
        let renderer: any FormKitRendering = LegacyFormKitRenderer()

        let session = renderer.makeFormSession(
            schemaJSON: #"{"type":"object"}"#,
            instanceJSON: nil,
            defaultConditionalRenderBehavior: nil,
            conditionalRenderBehaviorOverrides: [:],
            validationBehavior: .revalidateAfterFirstAttempt
        )

        XCTAssertTrue(session.renderPlan.isSupported)
    }
}

@MainActor
private struct LegacyFormKitRenderer: FormKitRendering {
    func makeFormSession(
        schemaJSON: String,
        instanceJSON: String?,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior?,
        validationBehavior: FormKitValidationBehavior
    ) -> FormKitSession {
        FormKitRenderer().makeFormSession(
            schemaJSON: schemaJSON,
            instanceJSON: instanceJSON,
            defaultConditionalRenderBehavior: defaultConditionalRenderBehavior,
            validationBehavior: validationBehavior
        )
    }
}
