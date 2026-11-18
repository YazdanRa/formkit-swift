import SwiftUI
import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicOptionsPresentationTests: XCTestCase {
    func testDetailIsDisplayOnlyAndDuplicateIDsRemainDistinct() {
        let first = FormKitDynamicOption(id: "opaque-first", label: "Alex", detail: "Example Construction")
        let second = FormKitDynamicOption(id: "opaque-second", label: "Alex", detail: "Example Mechanical")
        let labels = FormKitDynamicOptionsPickerLabels()
        labels.remember([first, second])
        XCTAssertEqual(labels.secondaryLabel(for: first, savedOptions: []), "Example Construction")
        XCTAssertEqual(labels.displayLabel(for: first, savedOptions: []), "Alex, Example Construction")
        XCTAssertEqual(labels.displayLabel(for: second, savedOptions: []), "Alex, Example Mechanical")
        var value: String?
        let selection = FormKitDynamicSelection.single(Binding(get: { value }, set: { value = $0 }))
        selection.choose(second.id, isRequired: false)
        XCTAssertEqual(value, "opaque-second")
        XCTAssertEqual(second.label, "Alex")
        let saved = FormKitDynamicOption(id: second.id, label: "Saved Alex", detail: "Saved company")
        XCTAssertEqual(labels.displayLabel(for: labels.option(for: second.id, savedOptions: [saved]),
                                          savedOptions: [saved]), "Saved Alex, Saved company")
        let withoutDetail = FormKitDynamicOption(id: first.id, label: "Alex", detail: "  ")
        XCTAssertEqual(labels.displayLabel(for: withoutDetail, savedOptions: []), "Alex, opaque-first")
    }

    func testMatchingLabelAndDetailUseOpaqueIDWithoutChangingStoredOption() {
        let first = FormKitDynamicOption(id: "equipment:1", label: "Excavator", detail: "  North yard ")
        let second = FormKitDynamicOption(id: "equipment:2", label: "Excavator", detail: "North yard")
        let labels = FormKitDynamicOptionsPickerLabels()
        labels.remember([first, second])
        XCTAssertEqual(labels.secondaryLabel(for: first, savedOptions: []), "North yard, equipment:1")
        XCTAssertEqual(labels.secondaryLabel(for: second, savedOptions: []), "North yard, equipment:2")
        XCTAssertEqual(labels.displayLabel(for: first, savedOptions: []), "Excavator, North yard, equipment:1")
        XCTAssertEqual(labels.displayLabel(for: second, savedOptions: []), "Excavator, North yard, equipment:2")
        XCTAssertEqual(first.detail, "  North yard ")
        var value: String?
        let selection = FormKitDynamicSelection.single(Binding(get: { value }, set: { value = $0 }))
        selection.choose(second.id, isRequired: false)
        XCTAssertEqual(value, "equipment:2")
        let savedOnly = FormKitDynamicOptionsPickerLabels()
        savedOnly.remember([first])
        XCTAssertEqual(savedOnly.secondaryLabel(for: first, savedOptions: [second]), "North yard, equipment:1")
        let otherYard = FormKitDynamicOption(id: second.id, label: "Excavator", detail: "South yard")
        XCTAssertEqual(savedOnly.secondaryLabel(for: first, savedOptions: [otherYard]), "North yard")
    }
}
