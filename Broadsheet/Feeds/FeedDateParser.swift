import Foundation

/// Parses the date formats feeds actually publish.
///
/// RSS specifies RFC 822 and Atom specifies RFC 3339, but real feeds emit
/// single-digit days, missing seconds, named zones, and bare dates. Each format is
/// tried in order and `nil` is returned rather than substituting "now", because a
/// wrong timestamp silently reorders the reader's day.
public enum FeedDateParser {
    private static let rfc822Formats = [
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm zzz",
        "EEE, d MMM yyyy HH:mm:ss zzz",
        "EEE, d MMM yyyy HH:mm zzz",
        "dd MMM yyyy HH:mm:ss zzz",
        "d MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss Z"
    ]

    private static let fallbackFormats = [
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd"
    ]

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = iso8601WithFractionalSeconds.date(from: trimmed) { return date }
        if let date = iso8601.date(from: trimmed) { return date }

        for format in rfc822Formats {
            if let date = makeFormatter(format).date(from: trimmed) { return date }
        }
        for format in fallbackFormats {
            if let date = makeFormatter(format).date(from: trimmed) { return date }
        }

        return nil
    }
}
