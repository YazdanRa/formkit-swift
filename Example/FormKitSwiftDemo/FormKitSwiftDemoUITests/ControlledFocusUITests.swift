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
        app.textFields["json_form_field_site_input"].typeText(" Updated!")
        app.buttons["demo_focus_temperature"].tap()
        XCTAssertEqual(app.staticTexts["demo_focus_value"].label, "#/temperature")
        waitForInstanceJSON(containing: "North Yard Updated", in: app)
        app.buttons["demo_clear_focus"].tap()
        XCTAssertEqual(app.staticTexts["demo_focus_value"].label, "none")

        app.buttons["demo_focus_site"].tap()
        app.textFields["json_form_field_site_input"].typeText(" Again")
        app.buttons["demo_clear_focus"].tap()
        XCTAssertEqual(app.staticTexts["demo_focus_value"].label, "none")
        waitForInstanceJSON(containing: "Again", in: app)

        app.buttons["demo_focus_site"].tap()
        app.textFields["json_form_field_site_input"].typeText("\nContinued")
        XCTAssertEqual(app.staticTexts["demo_focus_value"].label, "#/site")
        formKitSubmitButton(named: "Next", in: app).tap()
        XCTAssertEqual(app.staticTexts["demo_focus_value"].label, "#/temperature")
        XCTAssertGreaterThan(app.textFields["json_form_field_site_input"].frame.height, 24)
        waitForInstanceJSON(containing: "\\nContinued", in: app)
        app.textFields["json_form_field_temperature_input"].typeText("-")
        app.textFields["json_form_field_temperature_input"].typeText("1")

        keyboardButton(named: "next", in: app).tap()
        XCTAssertEqual(app.staticTexts["demo_focus_value"].label, "#/inspector")
        app.textFields["json_form_field_inspector_input"].typeText(" Updated!")

        formKitSubmitButton(named: "Done", in: app).tap()
        XCTAssertEqual(app.staticTexts["demo_focus_value"].label, "none")

        waitForInstanceJSON(containing: "\"temperature\" : -1", in: app)
        waitForInstanceJSON(containing: "Ada Updated", in: app)
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

    @MainActor
    private func formKitSubmitButton(named label: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["formkit_keyboard_submit"]
        XCTAssertTrue(button.waitForExistence(timeout: 2))
        XCTAssertEqual(button.label, label)
        return button
    }

    @MainActor
    private func waitForInstanceJSON(containing text: String, in app: XCUIApplication) {
        let instanceJSON = app.staticTexts["demo_instance_json"]
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: instanceJSON)],
            timeout: 5
        )
        XCTAssertEqual(result, .completed, instanceJSON.label)
    }
}
