import Foundation

/// Tabla y cálculo de CRC-32 (polinomio 0xEDB88320), tal y como lo usa el formato ZIP.
enum CRC32 {
    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            t[i] = c
        }
        return t
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for byte in raw.bindMemory(to: UInt8.self) {
                let idx = Int((crc ^ UInt32(byte)) & 0xFF)
                crc = table[idx] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
