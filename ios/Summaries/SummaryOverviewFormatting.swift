import Foundation

/// Shared by the saved display copy and the reader. Meeting metadata comes
/// from storage, never inference; generated overview lines become real bullets.
public enum SummaryOverviewFormatting {
    public static func points(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            var point = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in ["• ", "- ", "* "] where point.hasPrefix(prefix) {
                point = String(point.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            return point.isEmpty ? nil : point
        }
    }

    public static func meetingDetails(startedAt: Date, locale: Locale = .current,
                                      timeZone: TimeZone = .current) -> [String] {
        let date = DateFormatter()
        date.locale = locale; date.timeZone = timeZone; date.dateStyle = .long; date.timeStyle = .none
        let time = DateFormatter()
        time.locale = locale; time.timeZone = timeZone; time.dateStyle = .none; time.timeStyle = .short
        let zone = timeZone.abbreviation(for: startedAt) ?? timeZone.identifier
        return ["Date: \(date.string(from: startedAt))", "Time: \(time.string(from: startedAt)) (\(zone))"]
    }
}
