import Foundation

/// iCloud paylaşımındaki katılımcı izni (CloudKit `CKShare.ParticipantPermission` karşılığı).
public enum ShareAccess: String, Codable, Hashable, Sendable {
    case readOnly, readWrite
}

/// Ekip rolleri ile iCloud paylaşım izinlerini uyumlu tutar.
///
/// Uygulamadaki rol arayüzü kısıtlar; iCloud izni ise sunucuda zorlar: "sadece görür" kişinin
/// cihazı değiştirilmiş olsa bile seyahat kaydına yazamaz.
public enum SharePermissions {
    /// Ekipteki rollere göre katılımcıların olması gereken izni (iCloud kullanıcı adı → izin).
    /// Sahip ve iCloud kimliği bilinmeyen kişiler listede yer almaz.
    public static func desired(for members: [Member]) -> [String: ShareAccess] {
        var result: [String: ShareAccess] = [:]
        for member in members where member.role != .owner {
            guard let id = member.cloudUserID, !id.isEmpty else { continue }
            result[id] = member.role == .viewer ? .readOnly : .readWrite
        }
        return result
    }

    /// Şu anki katılımcı izinlerinden değişmesi gerekenler. Ekipte eşleşmeyen katılımcılara dokunulmaz.
    public static func changes(members: [Member], participants: [String: ShareAccess]) -> [String: ShareAccess] {
        desired(for: members).filter { id, access in
            guard let current = participants[id] else { return false }
            return current != access
        }
    }

    /// Bu cihazdaki kullanıcının seyahatteki geçerli rolü.
    /// - Parameters:
    ///   - memberRole: ekipte kendisi varsa rolü.
    ///   - shareAccess: başkasının seyahatine katıldıysa iCloud'daki izni.
    ///   - isSharedWithMe: seyahat başkasına ait ve bize paylaşılmış mı.
    public static func effectiveRole(memberRole: MemberRole?, shareAccess: ShareAccess?, isSharedWithMe: Bool) -> MemberRole {
        let base = memberRole ?? (isSharedWithMe ? .editor : .owner)
        // Başkasının seyahatinde sahip olunamaz; iCloud salt okunur diyorsa görüntüleyicisin.
        if isSharedWithMe, shareAccess == .readOnly { return .viewer }
        if isSharedWithMe, base == .owner { return .editor }
        return base
    }
}
