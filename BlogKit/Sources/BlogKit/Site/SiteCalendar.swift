import Foundation

/// 站点时区：日期显示、归档按月分组都按它算，和网站一致（`SITE_TIME_ZONE`）。
/// 按读者本地时区的话，北京时间 10 月 9 日上午发的文章在美国显示成 10 月 8 日，和网页对不上。
public enum SiteCalendar {
  public static let timeZone = TimeZone(identifier: "Asia/Shanghai")!

  public static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }()

  public static func yearMonth(of date: Date) -> YearMonth {
    let components = calendar.dateComponents([.year, .month], from: date)
    return YearMonth(year: components.year!, month: components.month!)
  }

  /// 日期的显示格式：语言跟随界面，时区固定为站点时区
  public static func dateStyle(locale: Locale) -> Date.FormatStyle {
    Date.FormatStyle(date: .long, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone)
  }

  /// "2026年10月" / "October 2026"
  public static func monthStyle(locale: Locale) -> Date.FormatStyle {
    Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).year().month(.wide)
  }

  /// 归档里每篇文章右边的日期："10月9日" / "Oct 9"
  public static func dayStyle(locale: Locale) -> Date.FormatStyle {
    Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).month(.abbreviated).day()
  }
}

/// 年月，"2026-10"
public struct YearMonth: Hashable, Comparable, Sendable, CustomStringConvertible {
  public let year: Int
  public let month: Int

  public init(year: Int, month: Int) {
    self.year = year
    self.month = month
  }

  public init?(_ string: String) {
    let parts = string.split(separator: "-")
    guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
      let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month)
    else { return nil }
    self.init(year: year, month: month)
  }

  public var description: String {
    String(format: "%04d-%02d", year, month)
  }

  /// 这个月第一天的零点（站点时区），用来按语言格式化"2026年10月"
  public var firstDay: Date {
    SiteCalendar.calendar.date(from: DateComponents(year: year, month: month, day: 1))!
  }

  public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
    (lhs.year, lhs.month) < (rhs.year, rhs.month)
  }
}

public struct ArchiveMonth: Hashable, Sendable, Identifiable {
  public let month: YearMonth
  public let items: [ArchiveItem]

  public var id: YearMonth { month }
}

public enum Archive {
  /// 按月分组，保持接口返回的顺序（新的在前）
  public static func group(_ items: [ArchiveItem]) -> [ArchiveMonth] {
    var months: [ArchiveMonth] = []
    for item in items {
      let month = SiteCalendar.yearMonth(of: item.publishedAt)
      if let last = months.last, last.month == month {
        months[months.count - 1] = ArchiveMonth(month: month, items: last.items + [item])
      } else {
        months.append(ArchiveMonth(month: month, items: [item]))
      }
    }
    return months
  }
}
