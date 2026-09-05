import XCTest

final class PickerLayoutUITests: XCTestCase {
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
