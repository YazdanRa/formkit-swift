import XCTest

final class PickerLayoutUITests: XCTestCase {
    @MainActor
    func testThreeLineOptionsStackAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITEST_PICKER_LAYOUT",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"
        ]
        app.launch()

        let titles = ["Pass", "Failed", "N/A"]
        let last = app.buttons["json_form_field_condition_option_string:N/A"]
        for _ in 0..<8 where !last.isHittable {
            app.swipeUp()
        }
        var frames: [CGRect] = []
        for title in titles {
            let option = app.buttons["json_form_field_condition_option_string:\(title)"]
            XCTAssertTrue(option.isHittable, title)
            XCTAssertGreaterThanOrEqual(option.frame.height, 44, title)
            XCTAssertGreaterThanOrEqual(option.frame.width, 44, title)
            XCTAssertLessThan(option.frame.height, 180, title)
            XCTAssertGreaterThanOrEqual(option.frame.minX, 0, title)
            XCTAssertLessThanOrEqual(option.frame.maxX, app.frame.maxX, title)
            frames.append(option.frame)
        }
        XCTAssertGreaterThan(try XCTUnwrap(frames.last?.minY), try XCTUnwrap(frames.first?.minY))
        for (index, frame) in frames.enumerated() {
            for other in frames.dropFirst(index + 1) {
                XCTAssertFalse(frame.intersects(other))
            }
        }
        XCTAssertTrue(last.isHittable)
        let initialFrame = last.frame
        last.tap()
        XCTAssertTrue(last.isSelected)
        XCTAssertEqual(last.frame.height, initialFrame.height, accuracy: 1)
        XCTAssertEqual(last.frame.width, initialFrame.width, accuracy: 1)
        last.tap()
        XCTAssertFalse(last.isSelected)
    }

    @MainActor
    func testLineOptionsFollowRightToLeftOrderInNarrowDarkLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_PICKER_LAYOUT", "-UITEST_RTL", "-UITEST_DARK"]
        app.launch()

        let first = app.buttons["json_form_field_condition_option_string:Pass"]
        let second = app.buttons["json_form_field_condition_option_string:Failed"]
        let last = app.buttons["json_form_field_condition_option_string:N/A"]
        for _ in 0..<8 where !last.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(first.isHittable)
        XCTAssertTrue(second.isHittable)
        XCTAssertTrue(last.isHittable)
        XCTAssertGreaterThan(first.frame.minX, second.frame.minX)
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 1)
        XCTAssertLessThanOrEqual(last.frame.maxX, app.frame.maxX)
        let initialFrame = first.frame
        first.tap()
        XCTAssertTrue(first.isSelected)
        XCTAssertEqual(first.frame, initialFrame)
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
        XCTAssertEqual(draft.frame.maxX, review.frame.minX, accuracy: 1)
        XCTAssertEqual(review.frame.maxX, complete.frame.minX, accuracy: 1)
        XCTAssertLessThan(complete.frame.maxX - draft.frame.minX, app.frame.width - 48)
        XCTAssertEqual(draft.frame.minY, complete.frame.minY, accuracy: 1)
        XCTAssertEqual(draft.frame.height, 44, accuracy: 1)
        XCTAssertEqual(review.frame.height, 44, accuracy: 1)

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
