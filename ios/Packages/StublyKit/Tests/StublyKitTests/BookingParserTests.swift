import XCTest
@testable import StublyKit

final class BookingParserTests: XCTestCase {
    let cal = TestCalendar.calendar
    let now = TestCalendar.date(2026, 9, 1)

    func components(_ date: Date, _ zone: String) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    func testTurkishAirlinesTicketWithTwoSegments() {
        let text = """
        Turkish Airlines e-Bilet
        PNR: XK7Q2M
        TK 1759  İstanbul (IST) → Lizbon (LIS)
        12 Eki 2026  07:40 - 10:15
        Koltuk: 14C
        TK 1760  Lizbon (LIS) → İstanbul (IST)
        18 Eki 2026  11:20 - 17:05
        """
        let result = BookingParser.parse(text, now: now, calendar: cal)
        XCTAssertEqual(result.flights.count, 2)
        let outbound = result.flights[0]
        XCTAssertEqual(outbound.flightNumber, "TK1759")
        XCTAssertEqual(outbound.fromCode, "IST")
        XCTAssertEqual(outbound.toCode, "LIS")
        XCTAssertEqual(outbound.seat, "14C")
        XCTAssertTrue(outbound.hasTimes)
        let dep = components(outbound.departure, "Europe/Istanbul")
        XCTAssertEqual([dep.month, dep.day, dep.hour, dep.minute], [10, 12, 7, 40])
        let arr = components(outbound.arrival, "Europe/Lisbon")
        XCTAssertEqual([arr.hour, arr.minute], [10, 15])

        let segment = outbound.segment()
        XCTAssertEqual(segment.fromCity, "İstanbul")
        XCTAssertEqual(segment.toCity, "Lizbon")
        XCTAssertEqual(segment.arrivalTimeZone, "Europe/Lisbon")

        let inbound = result.flights[1]
        XCTAssertEqual(inbound.flightNumber, "TK1760")
        XCTAssertEqual(inbound.fromCode, "LIS")
        XCTAssertNil(inbound.seat)
        XCTAssertEqual(components(inbound.departure, "Europe/Lisbon").day, 18)
        XCTAssertTrue(result.lodgings.isEmpty)
    }

    func testCompactLineAndDateBeforeNumber() {
        let pegasus = BookingParser.parse("Pegasus\nPC 1201 SAW-BCN 12.10.2026 06:30 09:15", now: now, calendar: cal)
        XCTAssertEqual(pegasus.flights.map(\.flightNumber), ["PC1201"])
        XCTAssertEqual(pegasus.flights.first?.toCode, "BCN")

        let dateFirst = BookingParser.parse("12 October 2026\nLH1301 IST-AMS 08:00 10:05", now: now, calendar: cal)
        XCTAssertEqual(dateFirst.flights.first?.flightNumber, "LH1301")
        XCTAssertEqual(components(dateFirst.flights.first!.departure, "Europe/Istanbul").day, 12)
    }

    func testBookingConfirmationInEnglish() {
        let text = """
        Booking confirmation
        Hotel Alfama Lisbon
        Address: Rua dos Remédios 12, Lisbon
        Check-in: Monday, 12 October 2026 (from 15:00)
        Check-out: Sunday, 18 October 2026 (until 11:00)
        Confirmation number: 4583920175
        """
        let result = BookingParser.parse(text, now: now, calendar: cal)
        XCTAssertTrue(result.flights.isEmpty)
        let lodging = try? XCTUnwrap(result.lodgings.first)
        XCTAssertEqual(lodging?.name, "Hotel Alfama Lisbon")
        XCTAssertEqual(lodging?.address, "Rua dos Remédios 12, Lisbon")
        XCTAssertEqual(lodging?.confirmation, "4583920175")
        XCTAssertEqual(lodging.map { cal.dateComponents([.day, .hour], from: $0.checkIn) }?.day, 12)
        XCTAssertEqual(lodging.map { cal.dateComponents([.day, .hour], from: $0.checkIn) }?.hour, 15)
        XCTAssertEqual(lodging.map { cal.dateComponents([.day, .hour], from: $0.checkOut) }?.day, 18)
        XCTAssertEqual(lodging?.lodging().nights(calendar: cal), 6)
    }

    func testTurkishHotelConfirmation() {
        let text = """
        Otel Rezervasyon Onayı
        Pera Palace Otel
        Giriş: 3 Kas 2026 14:00
        Çıkış: 6 Kas 2026 12:00
        Rezervasyon No: AB12345
        """
        let lodging = BookingParser.parse(text, now: now, calendar: cal).lodgings.first
        XCTAssertEqual(lodging?.name, "Pera Palace Otel")
        XCTAssertEqual(lodging?.confirmation, "AB12345")
        XCTAssertEqual(lodging.map { cal.component(.hour, from: $0.checkOut) }, 12)
    }

    func testDatesWithoutYearRollForward() {
        // Eylül'de okunan "5 Mar" geçmişte kaldığı için gelecek yıl sayılır.
        let tokens = BookingParser.findDates(in: "5 Mar · 20 Eki", now: now, calendar: cal)
        XCTAssertEqual(tokens.map(\.year), [2027, 2026])
        XCTAssertEqual(tokens.map(\.month), [3, 10])
    }

    func testIgnoresTextWithoutBookings() {
        XCTAssertTrue(BookingParser.parse("Merhaba, 7 gece kalacağız. 10 kişiyiz.", now: now, calendar: cal).isEmpty)
    }

    /// Booking.com onay PDF'inin PDFKit metni (kişisel bilgiler değiştirildi). Yazı tipi "i"yi "!" verir.
    static let bookingComPDF = """
    Rezervasyon onayı
    ONAY NUMARASI: 1234.567.890
    PİN KODU: 4321
    Cab!nn Copenhagen
    Adres: 1 Arn! Magnussons Gade,
    Vesterbro, 1577 Køpenhag,
    Dan!marka
    Telefon: +45 33 29 19 00
    GPS koord!natları: N 055°
    39.954, E 12° 33.915
    CHECK-İN
    17
    HAZİRAN
    Çarşamba
    15:00 - 00:00
    CHECK-OUT
    20
    HAZİRAN
    Cumartesi
    00:00 - 11:00
    ODA
    1 /
    GECE
    3
    FİYAT
    1 oda TL 19.560
    F!yat
    yaklaşık TL 24.450
    (2 konuk !ç!n)
    Commodore Oda - İk! Yataklı
    Konuk adı: Test K!ş!
    İptal koşulları:
    Bu rezervasyonu !ptal edersen!z !ade almaya uygun olmayacaksınız.
    """

    func testBookingComTurkishPDF() throws {
        let lodging = try XCTUnwrap(BookingParser.parse(Self.bookingComPDF, now: now, calendar: cal).lodgings.first)
        XCTAssertEqual(lodging.name, "Cabinn Copenhagen")
        XCTAssertEqual(lodging.address, "1 Arni Magnussons Gade, Vesterbro, 1577 Køpenhag, Danimarka")
        XCTAssertEqual(lodging.confirmation, "1234567890")
        XCTAssertEqual(lodging.note, "PIN: 4321 · Toplam: TL 24.450")
        // Yıl yazmıyor; 17 Haziran Çarşamba 2026'ya denk gelir (geçmişte kalsa da).
        XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour], from: lodging.checkIn),
                       DateComponents(year: 2026, month: 6, day: 17, hour: 15))
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: lodging.checkOut), DateComponents(day: 20, hour: 11))
        XCTAssertEqual(lodging.lodging().nights(calendar: cal), 3)
        let coordinate = try XCTUnwrap(lodging.coordinate)
        XCTAssertEqual(coordinate.latitude, 55.6659, accuracy: 0.0001)
        XCTAssertEqual(coordinate.longitude, 12.56525, accuracy: 0.0001)
    }

    func testGlyphRepairOnlyWhenTextIsBroken() {
        XCTAssertEqual(BookingParser.repairGlyphs("Cab!nn !ç!n Dan!marka"), "Cabinn için Danimarka")
        XCTAssertEqual(BookingParser.repairGlyphs("Harika! Görüşürüz!"), "Harika! Görüşürüz!")
    }

    /// Airbnb onay PDF'inin PDFKit metni (ad, adres, kod ve telefon değiştirildi).
    static let airbnbPDF = """
    Call host: +36 70 000 0000
    Sample Side Studios 3/2
    Check-in
    3:00 PM
    Sat, Nov 14
    Checkout
    11:00 AM
    Sun, Nov 15
    Who’s coming
    2 guests
    Test Kişi, Deneme Kişi
    Confirmation code
    HM2TEST0X1
    Budapest, Example utca 1, Budapest, 1088, Hungary
    Hosted by T Host
    Payment details
    Total cost: ₺4,363.46
    """

    func testAirbnbEnglishPDF() throws {
        let lodging = try XCTUnwrap(BookingParser.parse(Self.airbnbPDF, now: now, calendar: cal).lodgings.first)
        XCTAssertEqual(lodging.name, "Sample Side Studios 3/2")
        XCTAssertEqual(lodging.address, "Budapest, Example utca 1, Budapest, 1088, Hungary")
        XCTAssertEqual(lodging.confirmation, "HM2TEST0X1")
        XCTAssertEqual(lodging.note, "Toplam: ₺4,363.46")
        XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour], from: lodging.checkIn),
                       DateComponents(year: 2026, month: 11, day: 14, hour: 15))
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: lodging.checkOut), DateComponents(day: 15, hour: 11))
        XCTAssertNil(lodging.coordinate)
    }

    func testAirbnbTurkishLayout() throws {
        let text = """
        Galata Loft
        Giriş
        15:00
        Cmt, 14 Kas
        Çıkış
        11:00
        Paz, 15 Kas
        Onay kodu
        HMABC12345
        """
        let lodging = try XCTUnwrap(BookingParser.parse(text, now: now, calendar: cal).lodgings.first)
        XCTAssertEqual(lodging.name, "Galata Loft")
        XCTAssertEqual(lodging.confirmation, "HMABC12345")
        XCTAssertEqual(cal.dateComponents([.month, .day, .hour], from: lodging.checkIn), DateComponents(month: 11, day: 14, hour: 15))
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: lodging.checkOut), DateComponents(day: 15, hour: 11))
    }

    func testTwelveHourTimes() {
        XCTAssertEqual(BookingParser.findTimes(in: "3:00 PM · 11:00 AM · 12:30 am · 14:05", excluding: []).map(\.hour), [15, 11, 0, 14])
    }

    func testMatchingTripByDate() {
        let copenhagen = Trip(name: "Kopenhag", destination: Destination(countryCode: "DK", city: "Kopenhag"),
                              startDate: TestCalendar.date(2026, 6, 17), endDate: TestCalendar.date(2026, 6, 20))
        let lisbon = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                          startDate: TestCalendar.date(2026, 9, 30), endDate: TestCalendar.date(2026, 10, 3))
        let result = BookingParser.parse(Self.bookingComPDF, now: now, calendar: cal)
        XCTAssertEqual(result.matchingTrip(in: [lisbon, copenhagen], calendar: cal)?.name, "Kopenhag")
        let airbnb = BookingParser.parse(Self.airbnbPDF, now: now, calendar: cal)
        XCTAssertNil(airbnb.matchingTrip(in: [lisbon, copenhagen], calendar: cal), "14 Kasım hiçbir seyahate düşmez")
    }

    /// Pegasus e-bilet sayfası (web.flypgs.com/travel-document) metni; ad, PNR ve bilet no değiştirildi.
    /// Etiketler Türkçe/İngilizce alt alta, kodlar "( SAW )", dönüş uçuşu gece yarısından sonra iniyor.
    static let pegasusETicket = """
        Uçuş Bilgileriniz
        Flight info
        TEST KISI
        Rezervasyon No\tBilet No\tDüzenleyen\tDüzenlenme Tarihi
        Reservation no.\tTicket no.\tEdit\tEdit date
        AB12CD\t6240000000001\tINTERNET\t28/07/2026
        Nereden
        From
        İstanbul Sabiha Gökçen ( SAW )
        Kalkış Zamanı
        Departure time
        08/08/2026 - 06:30
        Kalkış Terminali
        Departure terminal
        Ana Terminal
        Nereye
        To
        Antalya ( AYT )
        Varış Zamanı
        Arrival time
        08/08/2026 - 07:50
        Varış Terminali
        Arrival terminal
        T1
        Uçuş No
        Flight no.
        PC2002
        Durum
        Status
        F
        Geçerlilik Tarihi
        Expiry date
        08/08/2027
        Koltuk
        Seat
        39E
        Nereden
        From
        Antalya ( AYT )
        Kalkış Zamanı
        Departure time
        09/08/2026 - 22:40
        Nereye
        To
        İstanbul Sabiha Gökçen ( SAW )
        Varış Zamanı
        Arrival time
        10/08/2026 - 00:05
        Uçuş No
        Flight no.
        PC2023
        Geçerlilik Tarihi
        Expiry date
        09/08/2027
        Koltuk
        Seat
        39A
        """

    func testPegasusETicketWithTwoFlights() throws {
        var istanbul = Calendar(identifier: .gregorian)
        istanbul.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let result = BookingParser.parse(Self.pegasusETicket, now: TestCalendar.date(2026, 7, 30), calendar: cal)
        XCTAssertTrue(result.lodgings.isEmpty)
        XCTAssertEqual(result.flights.map(\.flightNumber), ["PC2002", "PC2023"])
        XCTAssertEqual(result.flights.map { "\($0.fromCode)-\($0.toCode)" }, ["SAW-AYT", "AYT-SAW"])
        XCTAssertEqual(result.flights.map(\.seat), ["39E", "39A"])
        XCTAssertTrue(result.flights.allSatisfy(\.hasTimes))
        let back = try XCTUnwrap(result.flights.last)
        XCTAssertEqual(istanbul.dateComponents([.month, .day, .hour, .minute], from: back.departure),
                       DateComponents(month: 8, day: 9, hour: 22, minute: 40))
        XCTAssertEqual(istanbul.dateComponents([.day, .hour, .minute], from: back.arrival), DateComponents(day: 10, hour: 0, minute: 5))
    }
}
