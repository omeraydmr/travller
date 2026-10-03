import XCTest
@testable import StublyKit

final class SharedAlbumTests: XCTestCase {
    let a = Member(name: "Ömer")
    let b = Member(name: "Elif")
    let c = Member(name: "Can")

    func trip() -> Trip {
        Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
             startDate: TestCalendar.date(2026, 10, 20), endDate: TestCalendar.date(2026, 10, 24), members: [a, b, c])
    }

    func photo(_ owner: Member, _ key: String, minutes: Double = 0) -> AlbumPhoto {
        AlbumPhoto(ownerID: owner.id, fileName: "\(key).jpg",
                   takenAt: TestCalendar.date(2026, 10, 21).addingTimeInterval(minutes * 60), sourceKey: key)
    }

    func testAlbumOpensOnlyWithMutualConsent() {
        var value = trip()
        SharedAlbum.consent(a.id, in: &value)
        XCTAssertFalse(SharedAlbum.isActive(value), "Tek onay yetmez")
        XCTAssertFalse(SharedAlbum.canView(a.id, in: value))
        SharedAlbum.consent(b.id, in: &value)
        XCTAssertTrue(SharedAlbum.isActive(value))
        XCTAssertTrue(SharedAlbum.canView(a.id, in: value))
        XCTAssertFalse(SharedAlbum.canView(c.id, in: value), "Onay vermeyen göremez")
        SharedAlbum.consent(a.id, in: &value)
        XCTAssertEqual(value.albumConsents?.count, 2, "Aynı kişi iki kez onay vermez")
    }

    func testWithdrawRemovesOwnPhotosAndClosesAlbum() {
        var value = trip()
        SharedAlbum.consent(a.id, in: &value)
        SharedAlbum.consent(b.id, in: &value)
        value.albumPhotos = [photo(a, "x", minutes: 10), photo(b, "y", minutes: 5)]
        XCTAssertEqual(SharedAlbum.visiblePhotos(in: value).map(\.sourceKey), ["y", "x"])

        SharedAlbum.withdraw(b.id, in: &value)
        XCTAssertFalse(SharedAlbum.isActive(value))
        XCTAssertEqual(value.albumPhotos?.map(\.sourceKey), ["x"])
    }

    func testPhotosOfRemovedMemberAreHidden() {
        var value = trip()
        SharedAlbum.consent(a.id, in: &value)
        SharedAlbum.consent(b.id, in: &value)
        SharedAlbum.consent(c.id, in: &value)
        value.albumPhotos = [photo(c, "z")]
        value.members.removeAll { $0.id == c.id }
        XCTAssertTrue(SharedAlbum.visiblePhotos(in: value).isEmpty)
    }

    func testPendingSourcesSkipPresentAndExcluded() {
        var value = trip()
        value.albumPhotos = [photo(a, "1"), photo(b, "2")]
        XCTAssertEqual(SharedAlbum.pendingSources(["1", "2", "3", "4"], owner: a.id, in: value, excluded: ["4"]), ["2", "3"])
    }

    func testConcurrentConsentsBothSurviveMerge() {
        var base = trip()
        base.updatedAt = TestCalendar.date(2026, 9, 1)
        var mine = base
        SharedAlbum.consent(a.id, in: &mine)
        mine.albumPhotos = [photo(a, "1")]
        mine.updatedAt = TestCalendar.date(2026, 9, 2)
        var theirs = base
        SharedAlbum.consent(b.id, in: &theirs)
        theirs.updatedAt = TestCalendar.date(2026, 9, 3)
        let merged = mine.merged(with: theirs)
        XCTAssertTrue(SharedAlbum.isActive(merged), "İki cihazdaki onay birleşmede kaybolmaz")
        XCTAssertEqual(merged.albumPhotos?.count, 1)

        var withdrawn = merged
        SharedAlbum.withdraw(a.id, in: &withdrawn)
        withdrawn.recordDeletions(since: merged)
        withdrawn.updatedAt = TestCalendar.date(2026, 9, 4)
        let again = withdrawn.merged(with: mine)
        XCTAssertFalse(SharedAlbum.hasConsented(a.id, in: again), "Geri çekilen onay eski kopyadan geri gelmez")
        XCTAssertNil(again.albumPhotos)
    }

    func testSourceKeyIsStableAndOpaque() {
        let key = SharedAlbum.sourceKey(for: "ABC-123/L0/001")
        XCTAssertEqual(key, SharedAlbum.sourceKey(for: "ABC-123/L0/001"))
        XCTAssertNotEqual(key, SharedAlbum.sourceKey(for: "ABC-123/L0/002"))
        XCTAssertFalse(key.contains("ABC"))
    }
}
