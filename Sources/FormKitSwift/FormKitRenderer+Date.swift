import Foundation

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
}
