import Foundation

public enum TurkishGrammar {
    /// Sayıya üçüncü tekil iyelik eki ekler: 1'i, 2'si, 3'ü, 6'sı, 9'u, 10'u, 12'si, 40'ı, 100'ü, 1000'i.
    /// Ek, sayının okunuşundaki son kelimeye göre belirlenir.
    public static func withPossessive(_ number: Int) -> String {
        "\(number)'\(possessiveSuffix(number))"
    }

    public static func possessiveSuffix(_ number: Int) -> String {
        let n = abs(number)
        if n == 0 { return "ı" }                               // sıfır
        if n % 10 != 0 {
            switch n % 10 {
            case 1, 5, 8: return "i"                            // bir, beş, sekiz
            case 2, 7: return "si"                              // iki, yedi
            case 3, 4: return "ü"                               // üç, dört
            case 6: return "sı"                                 // altı
            default: return "u"                                 // dokuz
            }
        }
        if (n / 10) % 10 != 0 {
            switch (n / 10) % 10 {
            case 1, 3: return "u"                               // on, otuz
            case 2, 5: return "si"                              // yirmi, elli
            case 7, 8: return "i"                               // yetmiş, seksen
            default: return "ı"                                 // kırk, altmış, doksan
            }
        }
        if (n / 100) % 10 != 0 { return "ü" }                  // yüz
        if n % 1_000_000 != 0 { return "i" }                    // bin
        return "u"                                              // milyon
    }
}
