import XCTest
@testable import StublyKit

final class OnboardingTests: XCTestCase {
    func testPreferredSectionFollowsFirstInterest() {
        var preferences = TravelPreferences(companion: .friends)
        XCTAssertEqual(preferences.preferredSection, "crew", "İlgi yoksa kalabalık seyahatte ekip")
        preferences.toggle(.visa)
        preferences.toggle(.money)
        XCTAssertEqual(preferences.interests, [.visa, .money])
        XCTAssertEqual(preferences.preferredSection, "visa")
        preferences.toggle(.visa)
        XCTAssertEqual(preferences.preferredSection, "money")
        XCTAssertEqual(TravelPreferences(companion: .solo).preferredSection, "plan")
        XCTAssertEqual(TravelPreferences().preferredSection, "plan")
    }

    func testPreferencesRoundTrip() throws {
        let preferences = TravelPreferences(companion: .family, frequency: .often, interests: [.packing, .memories])
        let decoded = try JSONDecoder().decode(TravelPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded, preferences)
    }

    func testProfileNameValidation() {
        XCTAssertEqual(ProfileDraft.validName("  Ömer   Aydemir "), "Ömer Aydemir")
        XCTAssertNil(ProfileDraft.validName(" "))
        XCTAssertNil(ProfileDraft.validName("A"))
        XCTAssertNil(ProfileDraft.validName("Ben"))
        XCTAssertNil(ProfileDraft.validName(String(repeating: "x", count: 41)))
    }
}
