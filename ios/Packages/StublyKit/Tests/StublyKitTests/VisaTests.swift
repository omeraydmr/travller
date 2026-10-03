import XCTest
@testable import StublyKit

final class VisaTests: XCTestCase {
    let cal = TestCalendar.calendar
    let start = TestCalendar.date(2026, 10, 12)
    let end = TestCalendar.date(2026, 10, 17)

    func passport(expires: Date = TestCalendar.date(2031, 1, 1), visas: [HeldVisa] = []) -> Passport {
        Passport(nationality: "TR", type: .ordinary, expiresOn: expires, heldVisas: visas)
    }

    func testSchengenRequiresVisa() {
        let result = VisaAdvisor.assess(countryCode: "PT", passport: passport(), tripStart: start, tripEnd: end, calendar: cal)
        XCTAssertEqual(result.status, .required(zone: .schengen))
        XCTAssertTrue(result.needsAction)
    }

    func testHeldSchengenVisaCoversTrip() {
        let visa = HeldVisa(zone: .schengen, validUntil: TestCalendar.date(2027, 6, 1))
        let result = VisaAdvisor.assess(countryCode: "DE", passport: passport(visas: [visa]), tripStart: start, tripEnd: end,
                                        calendar: cal)
        XCTAssertEqual(result.status, .coveredByHeldVisa(zone: .schengen, until: visa.validUntil))
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertFalse(result.needsAction)
    }

    func testHeldVisaExpiringMidTripWarns() {
        let visa = HeldVisa(zone: .schengen, validUntil: TestCalendar.date(2026, 10, 14))
        let result = VisaAdvisor.assess(countryCode: "FR", passport: passport(visas: [visa]), tripStart: start, tripEnd: end,
                                        calendar: cal)
        XCTAssertTrue(result.warnings.contains(.heldVisaExpiresDuringTrip(zone: .schengen, until: visa.validUntil)))
        XCTAssertTrue(result.needsAction)
    }

    func testVisaFreeAndStayLimit() {
        let short = VisaAdvisor.assess(countryCode: "JP", passport: passport(), tripStart: start, tripEnd: end, calendar: cal)
        XCTAssertEqual(short.status, .notRequired(maxDays: 90))
        XCTAssertFalse(short.needsAction)

        let long = VisaAdvisor.assess(countryCode: "SG", passport: passport(), tripStart: start,
                                      tripEnd: TestCalendar.date(2026, 12, 1), calendar: cal)
        XCTAssertTrue(long.warnings.contains(.stayExceedsLimit(maxDays: 30, tripDays: 51)))
    }

    func testPassportValidity() {
        let soon = TestCalendar.date(2026, 12, 1)
        let schengen = VisaAdvisor.assess(countryCode: "IT", passport: passport(expires: soon), tripStart: start,
                                          tripEnd: end, calendar: cal)
        XCTAssertTrue(schengen.warnings.contains(.passportValidityShort(months: 3, mandatory: true, expiresOn: soon)))

        let expired = VisaAdvisor.assess(countryCode: "JP", passport: passport(expires: TestCalendar.date(2026, 10, 14)),
                                         tripStart: start, tripEnd: end, calendar: cal)
        XCTAssertEqual(expired.warnings, [.passportExpiresDuringTrip(expiresOn: TestCalendar.date(2026, 10, 14))])
        XCTAssertTrue(expired.needsAction)
    }

    func testUnknownDomesticAndMissingPassport() {
        XCTAssertEqual(VisaAdvisor.assess(countryCode: "TR", passport: passport(), tripStart: start, tripEnd: end,
                                          calendar: cal).status, .domestic)
        XCTAssertEqual(VisaAdvisor.assess(countryCode: "AQ", passport: passport(), tripStart: start, tripEnd: end,
                                          calendar: cal).status, .unknown)
        XCTAssertEqual(VisaAdvisor.assess(countryCode: "PT", passport: nil, tripStart: start, tripEnd: end,
                                          calendar: cal).status, .noPassport)
    }

    func testSchengenListHas29Countries() {
        XCTAssertEqual(VisaRules.schengenCountries.count, 29)
    }

    func typed(_ type: PassportType) -> Passport {
        Passport(nationality: "TR", type: type, expiresOn: TestCalendar.date(2031, 1, 1))
    }

    /// Kaynak: Dışişleri Bakanlığı, Türk Vatandaşlarının Tabi Olduğu Vize Uygulamaları (Ekim 2026).
    func testGreenPassportIsVisaFreeInSchengenButNotUK() {
        for type in [PassportType.special, .service, .diplomatic] {
            let schengen = VisaAdvisor.assess(countryCode: "PT", passport: typed(type), tripStart: start, tripEnd: end, calendar: cal)
            XCTAssertEqual(schengen.status, .notRequired(maxDays: 90), "\(type)")
            XCTAssertFalse(schengen.needsAction)
            let uk = VisaAdvisor.assess(countryCode: "GB", passport: typed(type), tripStart: start, tripEnd: end, calendar: cal)
            XCTAssertEqual(uk.status, .required(zone: .uk), "İngiltere tüm türlere vize ister")
        }
    }

    func testTypeSpecificLimits() {
        func status(_ code: String, _ type: PassportType) -> VisaStatus {
            VisaAdvisor.assess(countryCode: code, passport: typed(type), tripStart: start, tripEnd: end, calendar: cal).status
        }
        XCTAssertEqual(status("ME", .ordinary), .notRequired(maxDays: 30))
        XCTAssertEqual(status("ME", .special), .notRequired(maxDays: 90))
        XCTAssertEqual(status("BG", .special), .notRequired(maxDays: 90))
        XCTAssertEqual(status("BG", .diplomatic), .notRequired(maxDays: 30))
        XCTAssertEqual(status("MY", .ordinary), .onArrival(maxDays: 90))
        XCTAssertEqual(status("MY", .service), .notRequired(maxDays: 90))
        XCTAssertEqual(status("ID", .ordinary), .notRequired(maxDays: 30))
        XCTAssertEqual(status("AM", .diplomatic), .eVisa)
        XCTAssertEqual(status("US", .special), .required(zone: .us))
    }

    func testSchengen90of180StillAppliesToGreenPassport() {
        let earlier = Schengen.Stay(start: TestCalendar.date(2026, 7, 1), end: TestCalendar.date(2026, 9, 25), label: "")
        let result = VisaAdvisor.assess(countryCode: "IT", passport: typed(.special), tripStart: start, tripEnd: end,
                                        otherSchengenStays: [earlier], calendar: cal)
        XCTAssertTrue(result.warnings.contains { if case .schengenOverstay = $0 { return true }; return false })
        XCTAssertTrue(result.needsAction)
    }

    func testCrewVisaNeedFollowsPassportTypes() {
        let green = Member(name: "A", passport: typed(.special))
        let burgundy = Member(name: "B", passport: typed(.ordinary))
        XCTAssertFalse(VisaRules.requiresVisa(countryCode: "FR", members: [green]))
        XCTAssertTrue(VisaRules.requiresVisa(countryCode: "FR", members: [green, burgundy]))
        XCTAssertTrue(VisaRules.requiresVisa(countryCode: "FR", members: []), "Pasaport bilgisi yoksa bordo sayılır")
        XCTAssertTrue(VisaRules.requiresVisa(countryCode: "FR", members: [green, Member(name: "C")]),
                      "Pasaportu girilmemiş kişi bordo sayılır")
    }

    func testDatasetCoversMostCountries() {
        XCTAssertGreaterThan(VisaRules.entries.count, 190)
        func status(_ code: String, _ type: PassportType = .ordinary) -> VisaStatus {
            VisaAdvisor.assess(countryCode: code, passport: typed(type), tripStart: start, tripEnd: end, calendar: cal).status
        }
        XCTAssertEqual(status("TH"), .notRequired(maxDays: 30), "15 Eylül 2026'dan itibaren 30 gün")
        XCTAssertEqual(status("KR"), .notRequired(maxDays: 90))
        XCTAssertEqual(status("AU"), .required(zone: nil))
        XCTAssertEqual(status("MV"), .onArrival(maxDays: 30))
        XCTAssertEqual(status("SA"), .eVisa)
        XCTAssertEqual(status("VN"), .eVisa)
        XCTAssertEqual(status("VN", .special), .notRequired(maxDays: 90))
        XCTAssertEqual(status("MX", .diplomatic), .notRequired(maxDays: 90))
        XCTAssertEqual(status("MX", .special), .required(zone: nil))
        XCTAssertEqual(status("AD"), .required(zone: .schengen), "Andorra'ya Schengen vizesiyle girilir")
        XCTAssertEqual(status("GB", .special), .required(zone: .uk), "Elle doğrulanan kayıt önceliklidir")
        XCTAssertNotNil(VisaRules.entry(for: "TH")?.officialText)
        XCTAssertNotNil(VisaRules.entry(for: "PT")?.officialText, "Elle doğrulanan kayıt resmî metni de taşır")
    }

    func testRuleCodes() {
        XCTAssertEqual(VisaRules.rule("free:42"), .visaFree(maxDays: 42))
        XCTAssertEqual(VisaRules.rule("arrival:"), .visaOnArrival(maxDays: nil))
        XCTAssertEqual(VisaRules.rule("required:schengen"), .visaRequired(zone: .schengen))
        XCTAssertNil(VisaRules.rule("?"))
    }
}
