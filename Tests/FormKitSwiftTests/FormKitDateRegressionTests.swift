import XCTest
@testable import FormKitSwift

extension FormKitReviewRegressionTests {
    func testDateOnlyValuesRemainOnTheSameDayOutsideUTC() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let formatter = FormKitRenderer.dateFormatter
        XCTAssertEqual(formatter.timeZone, .autoupdatingCurrent)

        let originalTimeZone = formatter.timeZone
        formatter.timeZone = timeZone
        defer { formatter.timeZone = originalTimeZone }

        let session = FormKitRenderer().makeFormSession(
            schemaJSON: #"{"type":"object","properties":{"date":{"type":"string","format":"date"}}}"#,
            instanceJSON: #"{"date":"2026-07-27"}"#
        )
        let field = try XCTUnwrap(session.renderPlan.fields.first)
        let date = session.dateValue(for: field)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 27)
        session.setDateValue(date, for: field)
        XCTAssertEqual(
            try Self.decodeDateJSONObject(session.currentInstanceJSON)["date"] as? String,
            "2026-07-27"
        )
    }

    private static func decodeDateJSONObject(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
