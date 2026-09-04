import XCTest
@testable import FormKitSwift

extension FormKitRendererTests {
    func testToolContextExposesVisibleFieldsAndCurrentValues() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: supportedSchema,
            instanceJSON: populatedInstance
        )

        let context = session.makeToolContext(focusedPointers: ["/contact/email"])

        XCTAssertEqual(context.title, "Project Intake")
        XCTAssertEqual(context.revision, 0)
        XCTAssertEqual(context.fields.map(\.pointer), [
            "/contact/fullName",
            "/contact/email",
            "/contact/website",
            "/contact/sendUpdates",
            "/visitDate",
            "/priority"
        ])
        XCTAssertTrue(try XCTUnwrap(context.fields.first { $0.pointer == "/contact/email" }).isLocked)
        XCTAssertEqual(try XCTUnwrap(context.fields.first { $0.pointer == "/visitDate" }).valueFormat, "YYYY-MM-DD")
        XCTAssertEqual(context.currentValues["/contact/fullName"], .string("Taylor Jordan"))
        XCTAssertEqual(context.currentValues["/contact/sendUpdates"], .boolean(false))
    }

    func testToolTemporalValuesAreNormalizedAndValidatedAtTheSessionBoundary() throws {
        let schema =
            """
            {
              "type": "object",
              "properties": {
                "startTime": { "type": "string", "format": "time" },
                "startedAt": { "type": "string", "format": "date-time" }
              }
            }
            """
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: "{}")
        let context = session.makeToolContext()

        let timeFormat = try XCTUnwrap(context.fields.first { $0.pointer == "/startTime" }?.valueFormat)
        let dateTimeFormat = try XCTUnwrap(context.fields.first { $0.pointer == "/startedAt" }?.valueFormat)
        XCTAssertTrue(timeFormat.contains("23:59"))
        XCTAssertTrue(dateTimeFormat.contains("explicit offset"))

        let applied = session.applyToolEdits([
            .init(pointer: "/startTime", operation: .set, value: .string("10:30:00.123z")),
            .init(pointer: "/startedAt", operation: .set, value: .string("2026-09-03t10:30:00+23:59"))
        ], baseRevision: 0)

        XCTAssertTrue(applied.rejectedEdits.isEmpty)
        XCTAssertEqual(session.makeToolContext().currentValues["/startTime"], .string("10:30:00.123Z"))
        XCTAssertEqual(session.makeToolContext().currentValues["/startedAt"], .string("2026-09-03T10:30:00.000+23:59"))
        XCTAssertTrue(session.validate())

        let rejected = session.applyToolEdits([
            .init(pointer: "/startTime", operation: .set, value: .string("10:30:00+24:00")),
            .init(pointer: "/startedAt", operation: .set, value: .string("2026-02-30T10:30:00Z"))
        ], baseRevision: applied.revision)

        XCTAssertEqual(rejected.rejectedEdits.map(\.reason), ["invalid_format", "invalid_format"])
    }

    func testToolLocalTemporalValuesRespectSeasonalOffsetsAndDSTOverlaps() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let referenceDate = try XCTUnwrap(FormKitRenderer.dateTimeFallbackFormatter.date(from: "2026-09-04T12:00:00Z"))
        let apia = try XCTUnwrap(TimeZone(identifier: "Pacific/Apia"))
        XCTAssertEqual(
            FormKitRenderer.normalizedToolTemporalValue(
                from: "2011-12-30",
                type: .date,
                referenceDate: referenceDate,
                timeZone: apia
            ),
            "2011-12-30"
        )
        XCTAssertEqual(
            FormKitRenderer.normalizedToolTemporalValue(
                from: "10:30",
                type: .time,
                referenceDate: referenceDate,
                timeZone: timeZone
            ),
            "14:30:00Z"
        )
        XCTAssertNil(
            FormKitRenderer.normalizedToolTemporalValue(
                from: "2026-11-01T01:30",
                type: .dateTime,
                referenceDate: referenceDate,
                timeZone: timeZone
            )
        )
        let lordHowe = try XCTUnwrap(TimeZone(identifier: "Australia/Lord_Howe"))
        XCTAssertNil(
            FormKitRenderer.normalizedToolTemporalValue(
                from: "2026-04-05T01:45",
                type: .dateTime,
                referenceDate: referenceDate,
                timeZone: lordHowe
            )
        )
        XCTAssertEqual(
            FormKitRenderer.normalizedToolTemporalValue(
                from: "2026-11-01t01:30:00-04:00",
                type: .dateTime,
                referenceDate: referenceDate,
                timeZone: timeZone
            ),
            "2026-11-01T01:30:00.000-04:00"
        )
    }

    func testToolEditsApplySetClearAndRejectLockedPointers() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: supportedSchema,
            instanceJSON: populatedInstance
        )

        let result = session.applyToolEdits(
            [
                .init(pointer: "/contact/fullName", operation: .set, value: .string("Avery Stone")),
                .init(pointer: "/contact/website", operation: .clear),
                .init(pointer: "/contact/email", operation: .set, value: .string("locked@example.com"))
            ],
            baseRevision: 0,
            lockedPointers: ["/contact/email"]
        )

        XCTAssertEqual(result.revision, 2)
        XCTAssertEqual(result.appliedEdits.map(\.pointer), ["/contact/fullName", "/contact/website"])
        XCTAssertEqual(result.rejectedEdits.map(\.reason), ["field_locked"])
        XCTAssertEqual(session.stringValue(for: tryUnwrapField("fullName", in: session)), "Avery Stone")
        XCTAssertEqual(session.stringValue(for: tryUnwrapField("website", in: session)), "")
    }

    func testToolEditsRejectRevisionConflictWithoutChangingForm() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: supportedSchema,
            instanceJSON: populatedInstance
        )

        let result = session.applyToolEdits(
            [.init(pointer: "/contact/fullName", operation: .set, value: .string("Avery Stone"))],
            baseRevision: 9
        )

        XCTAssertEqual(result.revision, 0)
        XCTAssertTrue(result.appliedEdits.isEmpty)
        XCTAssertEqual(result.rejectedEdits.map(\.reason), ["revision_conflict"])
        XCTAssertEqual(session.stringValue(for: tryUnwrapField("fullName", in: session)), "Taylor Jordan")
    }
}

extension FormKitRendererTests {
    func testOnDemandValidationDoesNotRevalidateAfterFieldEdits() throws {
        let schema =
            """
            {
              "type": "object",
              "properties": {
                "name": {
                  "type": "string",
                  "title": "Name"
                }
              },
              "required": ["name"]
            }
            """

        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: "{}",
            validationBehavior: .onDemandOnly
        )
        let nameField = tryUnwrapField("name", in: session)

        XCTAssertFalse(session.validate())
        XCTAssertEqual(session.errorMessages(for: nameField), ["This field is required."])

        session.setStringValue("Taylor", for: nameField)

        XCTAssertTrue(session.errorMessages(for: nameField).isEmpty)
        XCTAssertNil(session.validationStatusMessage)
        XCTAssertTrue(session.validate())
    }
}
