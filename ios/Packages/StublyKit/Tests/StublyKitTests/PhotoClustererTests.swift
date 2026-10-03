import XCTest
@testable import StublyKit

final class PhotoClustererTests: XCTestCase {
    let cal = TestCalendar.calendar
    let belem = Coordinate(latitude: 38.6916, longitude: -9.2160)
    let alfama = Coordinate(latitude: 38.7118, longitude: -9.1300)

    func photo(_ id: String, _ hour: Int, _ minute: Int, _ coordinate: Coordinate?) -> PhotoClusterer.Photo {
        let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: TestCalendar.date(2026, 10, 13))!
        return PhotoClusterer.Photo(id: id, date: date, coordinate: coordinate)
    }

    func testSplitsByTimeGapAndDistance() {
        let photos = [
            photo("a", 10, 0, belem), photo("b", 10, 20, belem), photo("c", 10, 40, nil),
            // Aynı saatlerde ama 7 km ötede: yeni an.
            photo("d", 11, 0, alfama),
            // 3 saat sonra aynı yerde: yeni an.
            photo("e", 14, 30, alfama),
        ]
        let moments = PhotoClusterer.moments(photos.shuffled())
        XCTAssertEqual(moments.map(\.photoIDs), [["a", "b", "c"], ["d"], ["e"]])
        XCTAssertEqual(moments[0].count, 3)
        XCTAssertNotNil(moments[0].center)
    }

    func testLabelsWithNearestStopOnSameDay() {
        let moments = PhotoClusterer.moments([photo("a", 10, 0, belem), photo("b", 16, 0, alfama), photo("c", 19, 0, nil)])
        let day = TestCalendar.date(2026, 10, 13, 0)
        let otherDay = TestCalendar.date(2026, 10, 14, 0)
        let stops = [
            Stop(day: day, order: 0, name: "Belém Kulesi", kind: .sight, coordinate: Coordinate(latitude: 38.6915, longitude: -9.2158)),
            Stop(day: otherDay, order: 0, name: "Alfama turu", kind: .sight, coordinate: alfama),
        ]
        let labeled = PhotoClusterer.label(moments, stops: stops, calendar: cal)
        XCTAssertEqual(labeled.map(\.stopName), ["Belém Kulesi", nil, nil])
    }

    func testEmptyInput() {
        XCTAssertTrue(PhotoClusterer.moments([]).isEmpty)
    }
}
