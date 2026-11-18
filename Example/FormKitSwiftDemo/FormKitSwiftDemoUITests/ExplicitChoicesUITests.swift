import XCTest

final class ExplicitChoicesUITests: XCTestCase {
    @MainActor
    func testFirstLineOptionRequiresAnExplicitTap() {
        checkFirstChoice(usesStockPicker: false)
    }

    @MainActor
    func testFirstStockPickerOptionRequiresAnExplicitTap() {
        checkFirstChoice(usesStockPicker: true)
    }

    @MainActor
    private func checkFirstChoice(usesStockPicker: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_EXPLICIT_CHOICES", "-AppleLanguages", "(en)"]
            + (usesStockPicker ? ["-EXPLICIT_STOCK_PICKER"] : [])
        app.launch()
        let json = app.staticTexts["demo_explicit_json"]
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        XCTAssertFalse(json.label.contains("North"))
        let operatorField = app.textFields["json_form_field_operator_name_input"]
        operatorField.tap()
        operatorField.typeText(" updated")
        app.buttons["demo_explicit_blur"].tap()
        let committed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "updated"),
                                                  object: json)
        XCTAssertEqual(XCTWaiter.wait(for: [committed], timeout: 5), .completed)
        XCTAssertFalse(json.label.contains("North"))
        app.buttons["demo_explicit_reopen"].tap()
        XCTAssertFalse(json.label.contains("North"))
        if usesStockPicker {
            app.buttons["json_form_field_zone_picker"].tap()
            app.buttons["North"].tap()
        } else {
            let first = app.buttons["json_form_field_zone_option_string:North"]
            XCTAssertFalse(first.isSelected)
            first.tap()
        }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "North"),
                                                 object: json)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        app.buttons["demo_explicit_reopen"].tap()
        XCTAssertTrue(json.label.contains("North"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = usesStockPicker ? "required-first-picker-choice" : "required-first-line-choice"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
