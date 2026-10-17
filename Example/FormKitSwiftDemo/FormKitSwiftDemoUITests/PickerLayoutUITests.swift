import XCTest

final class PickerLayoutUITests: XCTestCase {
    @MainActor
    func testFiveLineOptionsWrapAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITEST_PICKER_LAYOUT",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"
        ]
        app.launch()

        let first = app.buttons["json_form_field_condition_option_string:Very good"]
        let last = app.buttons["json_form_field_condition_option_string:Not applicable"]
        for _ in 0..<8 where !first.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(first.isHittable)
        XCTAssertTrue(last.isHittable)
        XCTAssertEqual(first.frame.minY, last.frame.minY, accuracy: 1)
        XCTAssertEqual(first.frame.width, last.frame.width, accuracy: 1)
        XCTAssertEqual(first.frame.height, last.frame.height, accuracy: 1)
        XCTAssertGreaterThan(first.frame.height, 44)
        let initialFrame = last.frame
        last.tap()
        XCTAssertTrue(last.isSelected)
        XCTAssertEqual(last.frame.height, initialFrame.height, accuracy: 1)
        XCTAssertEqual(last.frame.width, initialFrame.width, accuracy: 1)
        last.tap()
        XCTAssertFalse(last.isSelected)
    }

    @MainActor
    func testLineOptionsChoiceSelectsWithoutOpeningMenuAndRespectsReadOnlyMode() {
        let app = XCUIApplication()
        app.launch()

        let draft = app.buttons["json_form_field_status_option_string:Draft"]
        let review = app.buttons["json_form_field_status_option_string:Needs Review"]
        let complete = app.buttons["json_form_field_status_option_string:Complete"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertTrue(review.exists)
        XCTAssertTrue(complete.exists)
        XCTAssertFalse(app.buttons["json_form_field_status_picker"].exists)
        XCTAssertTrue(draft.isSelected)
        XCTAssertEqual(draft.frame.width, review.frame.width, accuracy: 1)
        XCTAssertEqual(draft.frame.width, complete.frame.width, accuracy: 1)
        XCTAssertEqual(draft.frame.minY, complete.frame.minY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(draft.frame.height, 44)

        let initialHeight = review.frame.height
        review.tap()
        XCTAssertTrue(review.isSelected)
        XCTAssertFalse(draft.isSelected)
        XCTAssertEqual(review.frame.height, initialHeight, accuracy: 1)
        review.tap()
        XCTAssertTrue(review.isSelected)

        app.buttons["JSON"].tap()
        let json = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "\"status\" : \"Needs Review\"")
        ).firstMatch
        XCTAssertTrue(json.exists)

        app.buttons["Read Only"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertFalse(draft.isEnabled)
        XCTAssertFalse(review.isEnabled)
        XCTAssertFalse(complete.isEnabled)
    }

    @MainActor
    func testWrappedPickersStayLeadingAlignedWhenSelectionChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_PICKER_LAYOUT"]
        app.launch()

        let station = app.buttons["json_form_field_station_picker"]
        XCTAssertTrue(station.waitForExistence(timeout: 5))
        let leading = station.frame.minX
        let identifiers = [
            "json_form_field_traverse_picker",
            "json_form_field_elevation_picker",
            "json_form_field_enabled_picker",
            "json_form_field_date_date_state_picker"
        ]
        for identifier in identifiers {
            let picker = app.buttons[identifier]
            XCTAssertTrue(picker.exists, app.debugDescription)
            XCTAssertEqual(picker.frame.minX, leading, accuracy: 1, identifier)
        }

        let traverse = app.buttons[identifiers[0]]
        for selection in ["Requires further inspection before operation", "Pass"] {
            traverse.tap()
            app.buttons[selection].tap()
            let selected = NSPredicate(format: "value == %@ OR label CONTAINS %@", selection, selection)
            XCTAssertEqual(XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: selected, object: traverse)],
                timeout: 5
            ), .completed)
            XCTAssertEqual(traverse.frame.minX, leading, accuracy: 1)
        }
    }
}
