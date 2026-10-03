import XCTest
@testable import StublyKit

final class SharePermissionsTests: XCTestCase {
    let owner = Member(name: "Ayşe", role: .owner, cloudUserID: "_owner")
    let editor = Member(name: "Burak", role: .editor, cloudUserID: "_burak")
    let viewer = Member(name: "Can", role: .viewer, cloudUserID: "_can")
    let offline = Member(name: "Deniz", role: .viewer)

    func testDesiredFollowsRolesAndSkipsOwnerAndUnlinked() {
        XCTAssertEqual(SharePermissions.desired(for: [owner, editor, viewer, offline]),
                       ["_burak": .readWrite, "_can": .readOnly])
    }

    func testChangesOnlyForKnownParticipantsWithDifferentAccess() {
        let participants: [String: ShareAccess] = ["_burak": .readWrite, "_can": .readWrite, "_stranger": .readWrite]
        XCTAssertEqual(SharePermissions.changes(members: [owner, editor, viewer], participants: participants),
                       ["_can": .readOnly])
        XCTAssertEqual(SharePermissions.changes(members: [owner, editor], participants: participants), [:])
    }

    func testEffectiveRole() {
        // Kendi seyahatim
        XCTAssertEqual(SharePermissions.effectiveRole(memberRole: nil, shareAccess: nil, isSharedWithMe: false), .owner)
        XCTAssertEqual(SharePermissions.effectiveRole(memberRole: .owner, shareAccess: nil, isSharedWithMe: false), .owner)
        // Paylaşılan seyahat
        XCTAssertEqual(SharePermissions.effectiveRole(memberRole: nil, shareAccess: .readWrite, isSharedWithMe: true), .editor)
        XCTAssertEqual(SharePermissions.effectiveRole(memberRole: nil, shareAccess: .readOnly, isSharedWithMe: true), .viewer)
        XCTAssertEqual(SharePermissions.effectiveRole(memberRole: .editor, shareAccess: .readOnly, isSharedWithMe: true), .viewer,
                       "iCloud salt okunur diyorsa ekipteki rol düzenleyici olsa da görüntüleyici")
        XCTAssertEqual(SharePermissions.effectiveRole(memberRole: .viewer, shareAccess: .readWrite, isSharedWithMe: true), .viewer)
        XCTAssertEqual(SharePermissions.effectiveRole(memberRole: .owner, shareAccess: .readWrite, isSharedWithMe: true), .editor)
    }

    func testCloudUserIDSurvivesCodingAndOldPayloads() throws {
        let data = try JSONEncoder().encode(viewer)
        XCTAssertEqual(try JSONDecoder().decode(Member.self, from: data).cloudUserID, "_can")
        let old = #"{"id":"\#(UUID().uuidString)","name":"Eski","role":"editor","colorIndex":0}"#
        XCTAssertNil(try JSONDecoder().decode(Member.self, from: Data(old.utf8)).cloudUserID)
    }
}
