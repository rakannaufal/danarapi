import Foundation

enum MonthPeriod {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return value
    }
    static func start(_ date: Date) -> Date { calendar.date(from: calendar.dateComponents([.year, .month], from: date))! }
    static func end(_ date: Date) -> Date { calendar.date(byAdding: .month, value: 1, to: start(date))! }
    static func key(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-01"
        return formatter.string(from: date)
    }
    static func dateKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
