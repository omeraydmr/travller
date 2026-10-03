import Compression
import Foundation

/// Bellekteki küçük bir ZIP arşivinden tek dosya okur (Wallet `.pkpass` dosyaları ZIP'tir).
/// Yalnızca saklanmış (0) ve deflate (8) sıkıştırmayı destekler; şifreli ve ZIP64 arşivler desteklenmez.
public struct ZipArchive: Sendable {
    public struct Entry: Hashable, Sendable {
        public var name: String
        var method: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    public let entries: [Entry]
    private let data: Data

    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard let end = Self.endOfCentralDirectory(in: bytes) else { return nil }
        let count = Int(Self.u16(bytes, end + 10))
        var offset = Int(Self.u32(bytes, end + 16))
        var entries: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, Self.u32(bytes, offset) == 0x0201_4B50 else { return nil }
            let nameLength = Int(Self.u16(bytes, offset + 28))
            let extraLength = Int(Self.u16(bytes, offset + 30))
            let commentLength = Int(Self.u16(bytes, offset + 32))
            guard offset + 46 + nameLength <= bytes.count else { return nil }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            entries.append(Entry(name: name, method: Self.u16(bytes, offset + 10),
                                 compressedSize: Int(Self.u32(bytes, offset + 20)),
                                 uncompressedSize: Int(Self.u32(bytes, offset + 24)),
                                 localHeaderOffset: Int(Self.u32(bytes, offset + 42))))
            offset += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
        self.data = Data(bytes)
    }

    /// Adı verilen dosyanın açılmış içeriği; yoksa ya da açılamazsa nil.
    public func contents(of name: String) -> Data? {
        guard let entry = entries.first(where: { $0.name == name }) else { return nil }
        let bytes = [UInt8](data)
        let header = entry.localHeaderOffset
        guard header + 30 <= bytes.count, Self.u32(bytes, header) == 0x0403_4B50 else { return nil }
        let start = header + 30 + Int(Self.u16(bytes, header + 26)) + Int(Self.u16(bytes, header + 28))
        guard start + entry.compressedSize <= bytes.count else { return nil }
        let compressed = Array(bytes[start..<(start + entry.compressedSize)])
        switch entry.method {
        case 0:
            return Data(compressed)
        case 8:
            return Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    /// Ham DEFLATE (RFC 1951) açar; Compression çerçevesinin ZLIB algoritması başlıksız deflate'tir.
    static func inflate(_ source: [UInt8], expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        guard expectedSize <= 32 * 1024 * 1024 else { return nil }
        var output = [UInt8](repeating: 0, count: expectedSize)
        let written = source.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, expectedSize, src.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == expectedSize ? Data(output) : nil
    }

    private static func endOfCentralDirectory(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowest = max(0, bytes.count - 22 - 65_535)
        var index = bytes.count - 22
        while index >= lowest {
            if u32(bytes, index) == 0x0605_4B50 { return index }
            index -= 1
        }
        return nil
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
