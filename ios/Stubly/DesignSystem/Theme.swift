import SwiftUI
import StublyKit

// Kartpostal tasarım dili token'ları. Kaynak: design/tokens.json

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }

    static let canvas = Color(light: 0xECECEC, dark: 0x0F1012)
    static let surface = Color(light: 0xF5F5F5, dark: 0x1A1B1E)
    static let tray = Color(light: 0xFFFFFF, dark: 0x24262A)
    static let ink = Color(light: 0x1C1D21, dark: 0xF2F2F3)
    static let ink2 = Color(light: 0x6B6F78, dark: 0xA3A7AF)
    static let ink3 = Color(light: 0xA9ACB3, dark: 0x6E727A)
    static let line = Color(light: 0xE6E6E8, dark: 0x33363B)
    static let track = Color(light: 0xE9E9EB, dark: 0x2C2F34)
    static let success = Color(light: 0x2E8B6A, dark: 0x4CC198)
    /// Siyah birincil butonun üzerindeki metin.
    static let onInk = Color(light: 0xFFFFFF, dark: 0x111214)

    static let stays = Color(hex: 0x3EC58F)
    static let transport = Color(hex: 0x5B78EE)
    static let food = Color(hex: 0xF2814A)
    static let activities = Color(hex: 0xD158D6)
    static let staysTint = Color(light: 0xE3F6EE, dark: 0x183A2E)
    static let transportTint = Color(light: 0xE7ECFD, dark: 0x1E2647)
    static let foodTint = Color(light: 0xFDEDE4, dark: 0x45261A)
    static let activitiesTint = Color(light: 0xF9E6FA, dark: 0x3E1E40)
    static let neutralTint = Color(light: 0xEFEFF1, dark: 0x2C2F34)
}

/// Anlamsal vurgu: kategori renkleri uygulamanın her yerinde aynı anlamı taşır.
enum Accent: CaseIterable {
    case green, blue, orange, purple, gray

    var base: Color {
        switch self {
        case .green: .stays
        case .blue: .transport
        case .orange: .food
        case .purple: .activities
        case .gray: .ink2
        }
    }

    var tint: Color {
        switch self {
        case .green: .staysTint
        case .blue: .transportTint
        case .orange: .foodTint
        case .purple: .activitiesTint
        case .gray: .neutralTint
        }
    }

    /// Durak pinleri ve kişiler için sırayla dönen palet.
    static func cycle(_ index: Int) -> Accent {
        let palette: [Accent] = [.green, .blue, .orange, .purple]
        return palette[((index % palette.count) + palette.count) % palette.count]
    }
}

extension SpendCategory {
    var accent: Accent {
        switch self {
        case .stays: .green
        case .transport: .blue
        case .food: .orange
        case .activities: .purple
        case .other: .gray
        }
    }

    var title: String {
        switch self {
        case .stays: String(localized: "Konaklama")
        case .transport: String(localized: "Ulaşım")
        case .food: String(localized: "Yemek")
        case .activities: String(localized: "Aktivite")
        case .other: String(localized: "Diğer")
        }
    }

    var symbol: String {
        switch self {
        case .stays: "bed.double.fill"
        case .transport: "airplane"
        case .food: "fork.knife"
        case .activities: "ticket.fill"
        case .other: "square.grid.2x2.fill"
        }
    }
}

extension PassportType {
    var title: String {
        switch self {
        case .ordinary: String(localized: "Umuma mahsus (bordo)")
        case .special: String(localized: "Hususi (yeşil)")
        case .service: String(localized: "Hizmet (gri)")
        case .diplomatic: String(localized: "Diplomatik (siyah)")
        }
    }

    var shortTitle: String {
        switch self {
        case .ordinary: String(localized: "Bordo")
        case .special: String(localized: "Yeşil")
        case .service: String(localized: "Gri")
        case .diplomatic: String(localized: "Diplomatik")
        }
    }

    /// Pasaport kapağının renkleri (açık → koyu).
    var coverColors: [Color] {
        switch self {
        case .ordinary: [Color(hex: 0x8A2433), Color(hex: 0x5A1420)]
        case .special: [Color(hex: 0x2F6B45), Color(hex: 0x1B442B)]
        case .service: [Color(hex: 0x6B7078), Color(hex: 0x42464C)]
        case .diplomatic: [Color(hex: 0x2B2B2E), Color(hex: 0x111113)]
        }
    }
}

extension StopKind {
    var title: String {
        switch self {
        case .sight: String(localized: "Manzara")
        case .food: String(localized: "Yemek")
        case .activity: String(localized: "Aktivite")
        case .transport: String(localized: "Ulaşım")
        case .stay: String(localized: "Konaklama")
        }
    }

    var symbol: String {
        switch self {
        case .sight: "binoculars.fill"
        case .food: "cup.and.saucer.fill"
        case .activity: "ticket.fill"
        case .transport: "tram.fill"
        case .stay: "bed.double.fill"
        }
    }
}

extension MemberRole {
    var title: String {
        switch self {
        case .owner: String(localized: "Sahip")
        case .editor: String(localized: "Düzenleyebilir")
        case .viewer: String(localized: "Sadece görür")
        }
    }
}

enum Radius {
    static let module: CGFloat = 32
    static let tray: CGFloat = 24
    static let thumb: CGFloat = 14
}

extension Font {
    static let tDisplay = Font.system(.largeTitle, weight: .semibold)
    static let tHeadline = Font.system(.title, weight: .medium)
    static let tTitle = Font.system(.title2, weight: .medium)
    static let tAmount = Font.system(.title, weight: .semibold)
    static let tBodyStrong = Font.system(.body, weight: .medium)
    static let tBody = Font.system(.subheadline)
    static let tCaption = Font.system(.footnote, weight: .medium)
}
