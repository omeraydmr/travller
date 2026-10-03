import XCTest
@testable import StublyKit

final class PeopleTests: XCTestCase {
    let cal = TestCalendar.calendar

    func testIBANValidationAndFormatting() {
        XCTAssertTrue(IBAN.isValid("TR33 0006 1005 1978 6457 8413 26"))
        XCTAssertTrue(IBAN.isValid("tr330006100519786457841326"))
        XCTAssertFalse(IBAN.isValid("TR33 0006 1005 1978 6457 8413 27"))
        XCTAssertFalse(IBAN.isValid("TR33 0006 1005"))
        XCTAssertTrue(IBAN.isValid("DE89 3704 0044 0532 0130 00"))
        XCTAssertEqual(IBAN.formatted("tr330006100519786457841326"), "TR33 0006 1005 1978 6457 8413 26")
    }

    func testVisitedCountries() {
        let now = TestCalendar.date(2026, 10, 1)
        var past = Trip(name: "Roma", destination: Destination(countryCode: "IT", city: "Roma"),
                        startDate: TestCalendar.date(2026, 5, 1), endDate: TestCalendar.date(2026, 5, 4))
        past.status = .planned
        let future = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                          startDate: TestCalendar.date(2026, 11, 1), endDate: TestCalendar.date(2026, 11, 4))
        var draft = past
        draft.destination.countryCode = "FR"
        draft.status = .draft
        let domestic = Trip(name: "Kapadokya", destination: Destination(countryCode: "TR", city: "Nevşehir"),
                            startDate: TestCalendar.date(2026, 4, 1), endDate: TestCalendar.date(2026, 4, 3))
        let visited = TravelStats.visitedCountries(trips: [past, future, draft, domestic], extra: ["de", "IT"], now: now, calendar: cal)
        XCTAssertEqual(visited, ["DE", "IT"])
    }

    func testVisaApplicationsMergeOnePerMemberAndRemind() {
        let member = Member(name: "Elif")
        var a = Trip(name: "Berlin", destination: Destination(countryCode: "DE", city: "Berlin"),
                     startDate: TestCalendar.date(2026, 12, 1), endDate: TestCalendar.date(2026, 12, 5), members: [member])
        a.updatedAt = TestCalendar.date(2026, 10, 1)
        var b = a
        b.updatedAt = TestCalendar.date(2026, 10, 2)
        a.visaApplications = [VisaApplication(memberID: member.id, center: "Eski")]
        b.visaApplications = [VisaApplication(memberID: member.id, status: .appointmentBooked,
                                              appointment: TestCalendar.date(2026, 10, 20, 10), center: "VFS İstanbul")]
        let merged = a.merged(with: b)
        XCTAssertEqual(merged.visaApplications?.count, 1)
        XCTAssertEqual(merged.visaApplication(for: member.id)?.center, "VFS İstanbul")

        let plan = NotificationPlanner.plan(for: merged, now: TestCalendar.date(2026, 10, 1), calendar: cal)
        XCTAssertTrue(plan.contains { $0.title == "Yarın vize randevusu: Elif" && $0.body.hasPrefix("Saat 10:00 · VFS İstanbul") })
        XCTAssertTrue(plan.contains { $0.title == "Vize randevusu 2 saat sonra" && $0.link?.section == "visa" })
    }

    func testDocumentsMergeAndOldMembersDecodeWithoutIBAN() throws {
        var a = Trip(name: "X", destination: Destination(countryCode: "PT", city: "Lizbon"), startDate: .now, endDate: .now)
        a.updatedAt = TestCalendar.date(2026, 10, 1)
        var b = a
        b.updatedAt = TestCalendar.date(2026, 10, 2)
        a.documents = [TravelDocument(title: "Sigorta", kind: .insurance, fileName: "a.pdf")]
        b.documents = [TravelDocument(title: "Bilet", kind: .ticket, fileName: "b.pdf")]
        XCTAssertEqual(Set(a.merged(with: b).documentList.map(\.title)), ["Sigorta", "Bilet"])

        let json = #"{"id":"\#(UUID().uuidString)","name":"Can","role":"editor","colorIndex":1}"#
        let member = try JSONDecoder().decode(Member.self, from: Data(json.utf8))
        XCTAssertNil(member.iban)
    }
}
