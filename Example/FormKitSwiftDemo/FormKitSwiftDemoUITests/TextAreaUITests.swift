import XCTest

final class TextAreaUITests: XCTestCase {
    @MainActor
    func testNarrativeHasRoomAndPreservesNewlinesAfterReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_TEXT_AREA", "-AppleLanguages", "(en)"]
        app.launch()
        let subject = app.textFields["json_form_field_subject_input"]
        let narrative = app.textFields["json_form_field_description_input"]
        XCTAssertTrue(narrative.waitForExistence(timeout: 5))
        let emptyHeight = narrative.frame.height
        XCTAssertGreaterThan(emptyHeight, subject.frame.height + 10)

        let text = "First line of the native narrative.\n"
            + "Second line with enough detail to wrap across the phone several times. "
            + String(repeating: "Keep the access route clear. ", count: 5)
        narrative.tap()
        narrative.typeText(text)
        app.buttons["demo_text_area_blur"].tap()
        let json = app.staticTexts["demo_text_area_json"]
        let committed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "\\nSecond line"), object: json
        )
        XCTAssertEqual(XCTWaiter.wait(for: [committed], timeout: 5), .completed)
        app.buttons["demo_text_area_reopen"].tap()
        XCTAssertEqual(narrative.value as? String, text)
        XCTAssertGreaterThan(narrative.frame.height, emptyHeight)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "text-area-multiline-reopened"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
