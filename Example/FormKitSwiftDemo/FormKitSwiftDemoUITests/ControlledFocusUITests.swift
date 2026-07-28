import XCTest

final class ControlledFocusUITests: XCTestCase {
    @MainActor
    func testControlledFocusCommitsAndSynchronizesNextAndDone() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_CONTROLLED_FOCUS"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["formkit_form"].waitForExistence(timeout: 5))

        app.buttons["demo_focus_site"].tap()
        XCTAssertEqual(app.staticTexts["demo_focus_value"].label, "#/site")
        app.typeText(" Updated")
        app.buttons["demo_clear_focus"].tap()
        XCTAssertEqual(app.staticTexts["demo_focus_value"].label, "none")
        XCTAssertTrue(app.staticTexts["demo_instance_json"].label.contains("North Yard Updated"))

        app.buttons["demo_focus_site"].tap()
        keyboardButton(named: "next", in: app).tap()
        XCTAssertEqual(app.staticTexts["demo_focus_value"].label, "#/inspector")
        app.typeText(" Updated")

        keyboardButton(named: "done", in: app).tap()
        XCTAssertEqual(app.staticTexts["demo_focus_value"].label, "none")

        let instanceJSON = app.staticTexts["demo_instance_json"].label
        XCTAssertTrue(instanceJSON.contains("Ada Updated"))
    }

    @MainActor
    func testClearingFocusCommitsBeforeRemovingArrayRow() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_ROW_REMOVAL"]
        app.launch()

        let firstNote = app.textFields["json_form_field_notes_0_input"]
        XCTAssertTrue(firstNote.waitForExistence(timeout: 5))
        firstNote.tap()
        firstNote.typeText(" Updated")

        firstNote.swipeLeft()
        app.buttons["Remove"].tap()

        let remainingNote = app.textFields["json_form_field_notes_0_input"]
        let predicate = NSPredicate(format: "value == %@", "Second")
        expectation(for: predicate, evaluatedWith: remainingNote)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["demo_instance_json"].label.contains("Updated"))
    }

    @MainActor
    private func keyboardButton(named label: String, in app: XCUIApplication) -> XCUIElement {
        app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }
}
