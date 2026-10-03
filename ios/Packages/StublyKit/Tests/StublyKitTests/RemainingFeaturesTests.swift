import XCTest
@testable import StublyKit

final class DepartureChecklistTests: XCTestCase {
    let cal = TestCalendar.calendar

    func trip(_ country: String, currency: String = "EUR") -> Trip {
        Trip(name: "Test", destination: Destination(countryCode: country, city: "Şehir"),
             startDate: TestCalendar.date(2026, 10, 12), endDate: TestCalendar.date(2026, 10, 18), currency: currency)
    }

    func testSchengenTripSuggestsInsuranceAndExitFee() {
        let keys = DepartureChecklist.suggestions(for: trip("PT")).map(\.key)
        XCTAssertTrue(keys.contains("exit-fee"))
        XCTAssertTrue(keys.contains("insurance"))
        XCTAssertTrue(keys.contains("cash"))
        XCTAssertFalse(keys.contains("check-in"), "Uçuş yoksa check-in önerilmez")
        XCTAssertEqual(keys.last, "home", "En yakın tarihli en sonda")
    }

    func testAddedSuggestionIsNotRepeatedAndDueDates() {
        var value = trip("PT")
        let insurance = DepartureChecklist.suggestions(for: value).first { $0.key == "insurance" }!
        value.checklist = [insurance.item()]
        XCTAssertFalse(DepartureChecklist.suggestions(for: value).contains { $0.key == "insurance" })

        // T.C. pasaportuyla Schengen vizesi gerekir: sigorta vize başvurusu için 30 gün önce.
        let item = value.checklistItems[0]
        XCTAssertEqual(item.daysBefore, 30)
        let due = DepartureChecklist.dueDate(of: item, in: value, calendar: cal)!
        XCTAssertEqual(cal.dateComponents([.month, .day], from: due), DateComponents(month: 9, day: 12))
        XCTAssertTrue(DepartureChecklist.isOverdue(item, in: value, now: TestCalendar.date(2026, 9, 13), calendar: cal))
        XCTAssertFalse(DepartureChecklist.isOverdue(item, in: value, now: TestCalendar.date(2026, 9, 12), calendar: cal))
        var done = item
        done.isDone = true
        XCTAssertFalse(DepartureChecklist.isOverdue(done, in: value, now: TestCalendar.date(2026, 9, 13), calendar: cal))
    }

    func testDomesticTripHasNoExitFee() {
        let keys = DepartureChecklist.suggestions(for: trip("TR", currency: "TRY")).map(\.key)
        XCTAssertFalse(keys.contains("exit-fee"))
        XCTAssertFalse(keys.contains("cash"))
    }

    func testChecklistAndRefundsSurviveMerge() {
        var base = trip("FR")
        base.updatedAt = TestCalendar.date(2026, 9, 1)
        var local = base
        local.checklist = [ChecklistItem(title: "eSIM")]
        local.taxRefunds = [TaxRefund(shop: "Galeries", purchaseDate: base.startDate, amount: 50_000, expectedRefund: 5_800)]
        var remote = base
        remote.updatedAt = TestCalendar.date(2026, 9, 2)
        let merged = remote.merged(with: local)
        XCTAssertEqual(merged.checklistItems.map(\.title), ["eSIM"])
        XCTAssertEqual(merged.taxRefundList.count, 1)
    }

    func testChecklistNotificationGroupsByDay() {
        var value = trip("PT")
        value.checklist = [ChecklistItem(title: "eSIM", daysBefore: 3), ChecklistItem(title: "Kart", daysBefore: 3),
                           ChecklistItem(title: "Sigorta", daysBefore: 7, isDone: true)]
        let plan = NotificationPlanner.plan(for: value, now: TestCalendar.date(2026, 9, 1), calendar: cal)
        let todos = plan.filter { $0.id.contains("-todo-") }
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos.first?.title, "Gidiş öncesi 2 iş bugün")
    }
}

final class EmergencyTests: XCTestCase {
    func testNumbers() {
        XCTAssertEqual(EmergencyNumbers.numbers(for: "pt")?.general, "112")
        XCTAssertEqual(EmergencyNumbers.numbers(for: "JP")?.ambulance, "119")
        XCTAssertEqual(EmergencyNumbers.numbers(for: "US")?.general, "911")
        XCTAssertNil(EmergencyNumbers.numbers(for: "ZZ"))
    }

    func testAllergyCardLanguages() {
        XCTAssertEqual(AllergyCard.languages(forCountry: "PT"), ["pt", "en"])
        XCTAssertEqual(AllergyCard.languages(forCountry: "GB"), ["en"])
        XCTAssertEqual(AllergyCard.languages(forCountry: "GE"), ["en"])
        let phrase = AllergyCard.phrase([.peanut, .gluten], language: "de")
        XCTAssertEqual(phrase?.heading, "Ich bin allergisch gegen:")
        XCTAssertEqual(phrase?.items, ["Erdnüsse", "Gluten"])
        XCTAssertNil(AllergyCard.phrase([.peanut], language: "xx"))
    }

    func testEveryAllergenHasEveryLanguage() {
        for allergen in Allergen.allCases {
            for language in AllergyCard.supportedLanguages + ["tr"] {
                XCTAssertNotNil(AllergyCard.names[allergen]?[language], "\(allergen) \(language)")
            }
        }
        XCTAssertEqual(Set(AllergyCard.headings.keys), Set(AllergyCard.supportedLanguages))
    }

    func testEmergencyInfoEmpty() {
        XCTAssertTrue(EmergencyInfo().isEmpty)
        XCTAssertFalse(EmergencyInfo(bloodType: "0 Rh+").isEmpty)
    }
}

final class TaxRefundTests: XCTestCase {
    func testEstimate() {
        // 120 € içinde %20 KDV = 20 €; %70'i = 14 €.
        XCTAssertEqual(TaxRefunds.estimatedRefund(amount: 12_000, countryCode: "FR"), 1_400)
        XCTAssertNil(TaxRefunds.estimatedRefund(amount: 12_000, countryCode: "GB"), "İngiltere'de tax-free yok")
        XCTAssertNil(TaxRefunds.estimatedRefund(amount: 12_000, countryCode: "ZZ"))
        XCTAssertFalse(TaxRefunds.isAvailable(in: "US"))
    }

    func testSummary() {
        let day = TestCalendar.date(2026, 10, 12)
        let summary = TaxRefunds.summary([
            TaxRefund(shop: "A", purchaseDate: day, amount: 1, expectedRefund: 1_000),
            TaxRefund(shop: "B", purchaseDate: day, amount: 1, expectedRefund: 500, status: .validated),
            TaxRefund(shop: "C", purchaseDate: day, amount: 1, expectedRefund: 300, status: .refunded),
        ])
        XCTAssertEqual(summary, TaxRefunds.Summary(expected: 1_500, refunded: 300, toValidate: 1, awaitingPayment: 1))
    }
}

final class TripSummaryTests: XCTestCase {
    func testSummaryNumbers() {
        let cal = TestCalendar.calendar
        let start = TestCalendar.date(2026, 10, 12)
        let a = Member(name: "A")
        let b = Member(name: "B")
        var trip = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"), startDate: start,
                        endDate: TestCalendar.date(2026, 10, 14), members: [a, b])
        trip.stops = [
            Stop(day: start, order: 0, name: "Alfama", kind: .sight, coordinate: Coordinate(latitude: 38.71, longitude: -9.13)),
            Stop(day: start, order: 1, name: "Baixa", kind: .sight, coordinate: Coordinate(latitude: 38.71, longitude: -9.14)),
            Stop(day: start, order: 2, name: "Tram", kind: .transport),
        ]
        trip.expenses = [
            Expense(title: "Otel", amount: 30_000, category: .stays, paidBy: a.id, splitAmong: [a.id, b.id], date: start),
            Expense(title: "Yemek", amount: 10_000, category: .food, paidBy: b.id, splitAmong: [a.id, b.id], date: start),
            Expense(title: "Ödeme", amount: 5_000, category: .other, paidBy: b.id, splitAmong: [a.id], date: start,
                    isTransfer: true),
        ]
        let summary = TripSummary.make(trip, calendar: cal)
        XCTAssertEqual(summary.days, 3)
        XCTAssertEqual(summary.nights, 2)
        XCTAssertEqual(summary.travellers, 2)
        XCTAssertEqual(summary.totalSpent, 40_000, "Transferler harcama sayılmaz")
        XCTAssertEqual(summary.perPerson, 20_000)
        XCTAssertEqual(summary.topCategory, .stays)
        XCTAssertEqual(summary.highlights, ["Alfama", "Baixa"])
        XCTAssertGreaterThan(summary.routeMeters, 500)
    }
}

final class ChecklistDisplayTests: XCTestCase {
    func testChecklistDisplayTextFollowsSuggestionUnlessEdited() throws {
        var trip = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: TestCalendar.date(2026, 10, 10), endDate: TestCalendar.date(2026, 10, 13))
        let suggestion = try XCTUnwrap(DepartureChecklist.suggestions(for: trip).first { $0.key == "exit-fee" })
        var stored = suggestion.item()
        stored.title = "Eski dildeki başlık"
        trip.checklist = [stored]
        XCTAssertEqual(DepartureChecklist.displayText(of: stored, in: trip).title, suggestion.title,
                       "Öneriden gelen madde güncel dildeki metinle gösterilir")
        stored.textEdited = true
        XCTAssertEqual(DepartureChecklist.displayText(of: stored, in: trip).title, "Eski dildeki başlık")
        let custom = ChecklistItem(title: "Kediye mama bırak")
        XCTAssertEqual(DepartureChecklist.displayText(of: custom, in: trip).title, "Kediye mama bırak")
    }
}
