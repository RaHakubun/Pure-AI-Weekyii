import XCTest
@testable import Weekyii

final class WeekCalculatorTests: XCTestCase {
    func test_weekIdFormat() {
        let date = Date(timeIntervalSince1970: 1738108800)
        let weekId = WeekCalculator().weekId(for: date)
        XCTAssertTrue(weekId.contains("-W"))
    }

    func test_weekRange_isSevenDays() {
        let date = Date()
        let range = WeekCalculator().weekRange(for: date)
        let diff = Calendar(identifier: .iso8601).dateComponents([.day], from: range.start, to: range.end).day ?? 0
        XCTAssertEqual(diff, 6)
    }
}
