import XCTest

final class SectionPagesUITests: XCTestCase {
    @MainActor
    func testPagesTurnFromTheHeaderFooterAndSectionMenu() {
        let app = launch()
        let jump = app.buttons["formkit_page_jump"]
        let lastUserNavigation = app.staticTexts["demo_pages_last_user_navigation"]

        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        XCTAssertTrue(jump.label.hasPrefix("1 of 3"), jump.label)
        XCTAssertTrue(app.textFields["json_form_field_roomNumber_input"].exists)
        XCTAssertFalse(app.buttons["formkit_page_previous"].isEnabled)

        tapContinue(in: app)
        XCTAssertTrue(jump.label.hasPrefix("2 of 3"), jump.label)
        XCTAssertEqual(lastUserNavigation.label, "page 1")
        XCTAssertFalse(app.textFields["json_form_field_roomNumber_input"].exists)

        app.buttons["formkit_page_previous"].tap()
        XCTAssertTrue(jump.label.hasPrefix("1 of 3"), jump.label)

        jump.tap()
        let summaryRow = app.buttons["Summary"]
        XCTAssertTrue(summaryRow.waitForExistence(timeout: 5))
        summaryRow.tap()
        XCTAssertTrue(app.buttons["formkit_page_row_2"].waitForExistence(timeout: 5))
        XCTAssertEqual(jump.label, "Summary")
        XCTAssertEqual(lastUserNavigation.label, "summary")
        XCTAssertFalse(app.buttons["formkit_page_next"].isEnabled)

        app.buttons["formkit_page_row_2"].tap()
        XCTAssertTrue(jump.label.hasPrefix("3 of 3"), jump.label)
        XCTAssertEqual(lastUserNavigation.label, "page 2")
    }

    @MainActor
    func testHostRevealTurnsThePageWithoutReportingAUserNavigation() {
        let app = launch()
        let jump = app.buttons["formkit_page_jump"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5))

        app.buttons["demo_pages_reveal_lighting"].tap()

        let lightingPass = app.buttons["json_form_field_electrical_lighting_option_string:Pass"]
        XCTAssertTrue(lightingPass.waitForExistence(timeout: 5))
        XCTAssertTrue(jump.label.hasPrefix("3 of 3"), jump.label)
        XCTAssertEqual(app.staticTexts["demo_pages_last_user_navigation"].label, "none")
    }

    @MainActor
    func testAFailedAnswerIsFlaggedOnTheSummary() {
        let app = launch()
        let failed = app.buttons["json_form_field_housekeeping_linens_option_string:Failed"]
        XCTAssertTrue(failed.waitForExistence(timeout: 5))

        failed.tap()
        let observation = app.textFields["json_form_field_housekeeping_linens_observation_input"]
        XCTAssertTrue(observation.waitForExistence(timeout: 5))

        app.buttons["formkit_page_jump"].tap()
        let summaryItem = app.buttons["Summary"]
        XCTAssertTrue(summaryItem.waitForExistence(timeout: 5))
        summaryItem.tap()

        let firstRow = app.buttons["formkit_page_row_0"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        XCTAssertTrue(firstRow.label.contains("Needs attention"), firstRow.label)
        XCTAssertTrue(app.staticTexts["Flagged answers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Housekeeping › Linens clean and pressed"].exists)
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_SECTION_PAGES", "-SECTION_PAGES_HOST_CONTROLS"]
        app.launch()
        return app
    }

    @MainActor
    private func tapContinue(in app: XCUIApplication) {
        let button = app.buttons["formkit_page_continue"]
        for _ in 0..<6 where !button.isHittable {
            app.swipeUp()
        }
        button.tap()
    }
}
