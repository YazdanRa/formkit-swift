import SwiftUI
import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicCardinalityTests: XCTestCase {
    func testDuplicateHydrationCountsUniqueIDsWithoutWritingAndEditsProduceUniqueIDs() {
        for maximum in [1, 2] {
            var value = ["equipment:A", "equipment:A"]
            var writes = 0
            let selection = FormKitDynamicSelection.multiple(Binding(get: { value }, set: {
                writes += 1
                value = $0
            }))
            XCTAssertEqual(selection.ids, ["equipment:A"])
            XCTAssertTrue(selection.canChoose("equipment:B", maximumSelectionCount: maximum))
            XCTAssertEqual(value, ["equipment:A", "equipment:A"])
            XCTAssertEqual(writes, 0)
            selection.choose("equipment:B", isRequired: true, maximumSelectionCount: maximum)
            XCTAssertEqual(value, maximum == 1 ? ["equipment:B"] : ["equipment:A", "equipment:B"])
            XCTAssertEqual(writes, 1)
        }
    }

    func testOversizedDistinctSelectionAllowsRemovalWithoutReplacementOrTruncation() {
        var value = ["equipment:A", "  ", "equipment:C", "equipment:A"]
        var writes = 0
        let selection = FormKitDynamicSelection.multiple(Binding(get: { value }, set: {
            writes += 1
            value = $0
        }))
        XCTAssertEqual(selection.ids, ["equipment:A", "  ", "equipment:C"])
        XCTAssertFalse(selection.canChoose("equipment:B", maximumSelectionCount: 1))
        selection.choose("equipment:B", isRequired: true, maximumSelectionCount: 1)
        XCTAssertEqual(value, ["equipment:A", "  ", "equipment:C", "equipment:A"])
        XCTAssertEqual(writes, 0)
        selection.choose("equipment:C", isRequired: true, maximumSelectionCount: 1)
        XCTAssertEqual(value, ["equipment:A", "  "])
        XCTAssertFalse(selection.canChoose("equipment:B", maximumSelectionCount: 1))
        selection.choose("  ", isRequired: true, maximumSelectionCount: 1)
        XCTAssertEqual(value, ["equipment:A"])
        selection.choose("equipment:B", isRequired: true, maximumSelectionCount: 1)
        XCTAssertEqual(value, ["equipment:B"])
        XCTAssertEqual(writes, 3)
    }
}
