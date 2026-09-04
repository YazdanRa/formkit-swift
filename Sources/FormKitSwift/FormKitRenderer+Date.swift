import Foundation
import JSONSchema

extension FormKitRenderer {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let dateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static let dateTimeFallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static let timeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static let timeFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func toolValueFormat(for type: FormKitFieldDescriptor.ScalarType) -> String? {
        switch type {
        case .date:
            return "YYYY-MM-DD"
        case .time:
            return "HH:mm or HH:mm:ss in local time, or HH:mm:ss[.fraction](Z|±HH:MM) "
                + "with offset 00:00–23:59; DST overlaps require an explicit offset"
        case .dateTime:
            return "YYYY-MM-DDTHH:mm or YYYY-MM-DDTHH:mm:ss in local time, "
                + "or YYYY-MM-DDTHH:mm:ss[.fraction](Z|±HH:MM) with offset 00:00–23:59; "
                + "DST overlaps require an explicit offset"
        default:
            return nil
        }
    }

    static func normalizedToolTemporalValue(
        from value: String,
        type: FormKitFieldDescriptor.ScalarType,
        referenceDate: Date = .now,
        timeZone: TimeZone = .current
    ) -> String? {
        let canonicalValue = canonicalTemporalValue(value)
        switch type {
        case .date:
            guard parseLocalDate(
                value,
                formats: ["yyyy-MM-dd"],
                referenceDate: referenceDate,
                timeZone: .gmt
            ) != nil else {
                return nil
            }
            return value
        case .time:
            if isCanonicalTime(canonicalValue),
               reanchoredTime(from: canonicalValue, referenceDate: referenceDate, timeZone: timeZone) != nil
            {
                return canonicalValue
            }
            guard let date = parseLocalDate(
                value,
                formats: ["HH:mm", "HH:mm:ss"],
                referenceDate: referenceDate,
                timeZone: timeZone,
                rejectsAmbiguousTime: true
            ) else {
                return nil
            }
            return timeFormatter.string(from: date)
        case .dateTime:
            if isCanonicalDateTime(canonicalValue) {
                return addingFractionalSecondsIfNeeded(to: canonicalValue)
            }
            guard let date = parseLocalDate(
                value,
                formats: ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss"],
                referenceDate: referenceDate,
                timeZone: timeZone,
                rejectsAmbiguousTime: true
            ) else {
                return nil
            }
            return dateTimeFormatter.string(from: date)
        default:
            return nil
        }
    }

    static func reanchoredTime(
        from rawValue: String,
        referenceDate: Date = .now,
        timeZone: TimeZone = .current
    ) -> Date? {
        guard let parsedDate = timeFormatter.date(from: rawValue)
            ?? timeFractionalFormatter.date(from: rawValue)
        else {
            return nil
        }

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let dateComponents = localCalendar.dateComponents([.year, .month, .day], from: referenceDate)

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = .gmt
        let timeComponents = utcCalendar.dateComponents([.hour, .minute, .second, .nanosecond], from: parsedDate)

        var components = DateComponents()
        components.calendar = utcCalendar
        components.timeZone = utcCalendar.timeZone
        components.year = dateComponents.year
        components.month = dateComponents.month
        components.day = dateComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        components.nanosecond = timeComponents.nanosecond

        guard let sameDateUTC = utcCalendar.date(from: components) else {
            return nil
        }

        let candidates = [-1, 0, 1]
            .compactMap { utcCalendar.date(byAdding: .day, value: $0, to: sameDateUTC) }
        let localDateCandidates = candidates.filter {
                localCalendar.dateComponents([.year, .month, .day], from: $0) == dateComponents
            }
        var preferredCandidates = localDateCandidates.isEmpty ? candidates : localDateCandidates
        let referenceOffset = timeZone.secondsFromGMT(for: referenceDate)
        let matchingOffsetCandidates = preferredCandidates.filter {
            timeZone.secondsFromGMT(for: $0) == referenceOffset
        }
        if !matchingOffsetCandidates.isEmpty {
            preferredCandidates = matchingOffsetCandidates
        }
        return preferredCandidates.min {
            abs($0.timeIntervalSince(referenceDate)) < abs($1.timeIntervalSince(referenceDate))
        }
    }

    private static func canonicalTemporalValue(_ value: String) -> String {
        value.replacingOccurrences(of: "t", with: "T").replacingOccurrences(of: "z", with: "Z")
    }

    private static func addingFractionalSecondsIfNeeded(to value: String) -> String {
        let zoneStart = value.hasSuffix("Z")
            ? value.index(before: value.endIndex)
            : value.index(value.endIndex, offsetBy: -6)
        guard !value[..<zoneStart].contains(".") else {
            return value
        }
        return "\(value[..<zoneStart]).000\(value[zoneStart...])"
    }

    private static func isCanonicalDateTime(_ value: String) -> Bool {
        let parts = value.split(separator: "T", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2
            && parseLocalDate(String(parts[0]), formats: ["yyyy-MM-dd"], referenceDate: .now, timeZone: .gmt) != nil
            && isCanonicalTime(String(parts[1]))
            && (dateTimeFormatter.date(from: value) ?? dateTimeFallbackFormatter.date(from: value)) != nil
    }

    private static func isCanonicalTime(_ value: String) -> Bool {
        DefaultFormatValidators.all.first { $0.formatName == "time" }?.validate(value) == true
            && hasExplicitOffset(value)
    }

    private static func hasExplicitOffset(_ value: String) -> Bool {
        if value.hasSuffix("Z") {
            return true
        }
        let suffix = value.suffix(6)
        return suffix.count == 6
            && (suffix.first == "+" || suffix.first == "-")
            && suffix[suffix.index(suffix.startIndex, offsetBy: 3)] == ":"
    }

    private static func parseLocalDate(
        _ value: String,
        formats: [String],
        referenceDate: Date,
        timeZone: TimeZone,
        rejectsAmbiguousTime: Bool = false
    ) -> Date? {
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.defaultDate = referenceDate
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: value),
               formatter.string(from: date) == value,
               !rejectsAmbiguousTime || !isAmbiguousLocalTime(date, timeZone: timeZone)
            {
                return date
            }
        }
        return nil
    }

    private static func isAmbiguousLocalTime(_ date: Date, timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let searchStart = date.addingTimeInterval(-2 * 24 * 60 * 60)
        guard let transition = timeZone.nextDaylightSavingTimeTransition(after: searchStart),
              transition < date.addingTimeInterval(2 * 24 * 60 * 60)
        else {
            return false
        }
        let repeatedDuration = timeZone.secondsFromGMT(for: transition.addingTimeInterval(-1))
            - timeZone.secondsFromGMT(for: transition.addingTimeInterval(1))
        guard repeatedDuration > 0 else {
            return false
        }
        return [repeatedDuration, -repeatedDuration].contains {
            calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date.addingTimeInterval(TimeInterval($0))
            ) == components
        }
    }
}
