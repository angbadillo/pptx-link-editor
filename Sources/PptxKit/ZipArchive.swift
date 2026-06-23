import Foundation
import Compression

/// Errores que puede producir el manejo del contenedor ZIP.
public enum ZipError: Error, CustomStringConvertible {
    case notAZip
    case unsupportedZip64
    case corruptCentralDirectory
    case entryNotFound(String)
    case decompressionFailed(String)
    case embeddingFailed(String)

    public var description: String {
        switch self {
        case .notAZip: return "El fichero no es un ZIP válido (no se encontró el directorio central)."
        case .unsupportedZip64: return "El fichero usa ZIP64 (>4GB), no soportado."
        case .corruptCentralDirectory: return "El directorio central del ZIP está dañado."
        case .entryNotFound(let n): return "No se encontró la entrada \(n) en el ZIP."
        case .decompressionFailed(let n): return "Fallo al descomprimir la entrada \(n)."
        case .embeddingFailed(let n): return "El gráfico \(n) no tiene datos cacheados para incrustar."
        }
    }
}

/// Una entrada (fichero) dentro del contenedor ZIP.
///
/// Guardamos los bytes *crudos* tal y como vienen en el ZIP original (`compressedData`).
/// Las entradas que no se tocan se vuelven a escribir byte a byte sin recomprimir,
/// que es la clave para que PowerPoint no detecte el .pptx como dañado.
public final class ZipEntry {
    public let name: String
    public internal(set) var method: UInt16          // 0 = stored, 8 = deflate
    public internal(set) var crc32: UInt32
    public internal(set) var compressedData: Data     // bytes crudos almacenados en el ZIP
    public internal(set) var uncompressedSize: UInt32
    public let dosTime: UInt16
    public let dosDate: UInt16
    public let externalAttributes: UInt32
    public let versionMadeBy: UInt16

    init(name: String, method: UInt16, crc32: UInt32, compressedData: Data,
         uncompressedSize: UInt32, dosTime: UInt16, dosDate: UInt16,
         externalAttributes: UInt32, versionMadeBy: UInt16) {
        self.name = name
        self.method = method
        self.crc32 = crc32
        self.compressedData = compressedData
        self.uncompressedSize = uncompressedSize
        self.dosTime = dosTime
        self.dosDate = dosDate
        self.externalAttributes = externalAttributes
        self.versionMadeBy = versionMadeBy
    }

    /// Devuelve el contenido descomprimido de la entrada.
    public func data() throws -> Data {
        switch method {
        case 0:
            return compressedData
        case 8:
            return try Deflate.inflate(compressedData, expectedSize: Int(uncompressedSize), name: name)
        default:
            throw ZipError.decompressionFailed(name)
        }
    }

    /// Reemplaza el contenido de la entrada (recomprimiendo con deflate si conviene).
    public func replace(with newData: Data) {
        let deflated = Deflate.deflate(newData)
        if let d = deflated, d.count < newData.count {
            self.compressedData = d
            self.method = 8
        } else {
            self.compressedData = newData
            self.method = 0
        }
        self.uncompressedSize = UInt32(newData.count)
        self.crc32 = CRC32.checksum(newData)
    }
}

/// Lector / escritor de contenedores ZIP centrado en la preservación fiel del contenido.
public final class ZipArchive {
    public private(set) var entries: [ZipEntry]

    init(entries: [ZipEntry]) {
        self.entries = entries
    }

    /// Crea un contenedor vacío (para construir un .xlsx desde cero, p. ej.).
    public init() { self.entries = [] }

    public func entry(named name: String) -> ZipEntry? {
        entries.first { $0.name == name }
    }

    /// Añade una entrada nueva con el contenido dado (se comprime con deflate si conviene).
    /// Si ya existía una con ese nombre, la reemplaza.
    public func addEntry(name: String, data: Data) {
        if let existing = entry(named: name) {
            existing.replace(with: data)
            return
        }
        let e = ZipEntry(name: name, method: 0, crc32: 0, compressedData: Data(),
                         uncompressedSize: 0, dosTime: 0, dosDate: 0x21,
                         externalAttributes: 0, versionMadeBy: 20)
        e.replace(with: data)
        entries.append(e)
    }

    // MARK: - Lectura

    public static func read(data: Data) throws -> ZipArchive {
        let bytes = [UInt8](data)
        guard let eocd = findEOCD(bytes) else { throw ZipError.notAZip }

        let totalEntries = readU16(bytes, eocd + 10)
        let cdOffset = Int(readU32(bytes, eocd + 16))
        let cdSize = Int(readU32(bytes, eocd + 12))

        if cdOffset == 0xFFFF_FFFF || cdSize == 0xFFFF_FFFF || totalEntries == 0xFFFF {
            throw ZipError.unsupportedZip64
        }

        var entries: [ZipEntry] = []
        var p = cdOffset
        for _ in 0..<totalEntries {
            guard p + 46 <= bytes.count, readU32(bytes, p) == 0x0201_4b50 else {
                throw ZipError.corruptCentralDirectory
            }
            let versionMadeBy = readU16(bytes, p + 4)
            let method = readU16(bytes, p + 10)
            let dosTime = readU16(bytes, p + 12)
            let dosDate = readU16(bytes, p + 14)
            let crc = readU32(bytes, p + 16)
            let compSize = Int(readU32(bytes, p + 20))
            let uncompSize = readU32(bytes, p + 24)
            let nameLen = Int(readU16(bytes, p + 28))
            let extraLen = Int(readU16(bytes, p + 30))
            let commentLen = Int(readU16(bytes, p + 32))
            let externalAttrs = readU32(bytes, p + 38)
            let localOffset = Int(readU32(bytes, p + 42))

            guard p + 46 + nameLen <= bytes.count else { throw ZipError.corruptCentralDirectory }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)

            // Localizar el inicio de los datos leyendo la cabecera local (su extra puede diferir).
            guard localOffset + 30 <= bytes.count, readU32(bytes, localOffset) == 0x0403_4b50 else {
                throw ZipError.corruptCentralDirectory
            }
            let localNameLen = Int(readU16(bytes, localOffset + 26))
            let localExtraLen = Int(readU16(bytes, localOffset + 28))
            let dataStart = localOffset + 30 + localNameLen + localExtraLen
            guard dataStart + compSize <= bytes.count else { throw ZipError.corruptCentralDirectory }
            let compData = Data(bytes[dataStart..<(dataStart + compSize)])

            entries.append(ZipEntry(name: name, method: UInt16(method), crc32: crc,
                                    compressedData: compData, uncompressedSize: uncompSize,
                                    dosTime: UInt16(dosTime), dosDate: UInt16(dosDate),
                                    externalAttributes: externalAttrs, versionMadeBy: UInt16(versionMadeBy)))

            p += 46 + nameLen + extraLen + commentLen
        }
        return ZipArchive(entries: entries)
    }

    // MARK: - Escritura

    /// Reconstruye un ZIP válido conservando nombres, orden, fechas y método de
    /// compresión de cada entrada. Limpia el bit de "data descriptor" porque
    /// escribimos siempre crc y tamaños en la cabecera local.
    public func write() -> Data {
        var out = Data()
        var central = Data()

        for e in entries {
            let nameBytes = Array(e.name.utf8)
            let localOffset = UInt32(out.count)

            // --- Cabecera local ---
            out.appendU32(0x0403_4b50)
            out.appendU16(20)                 // version needed
            out.appendU16(0)                  // general purpose flag (sin data descriptor)
            out.appendU16(e.method)
            out.appendU16(e.dosTime)
            out.appendU16(e.dosDate)
            out.appendU32(e.crc32)
            out.appendU32(UInt32(e.compressedData.count))
            out.appendU32(e.uncompressedSize)
            out.appendU16(UInt16(nameBytes.count))
            out.appendU16(0)                  // extra field length
            out.append(contentsOf: nameBytes)
            out.append(e.compressedData)

            // --- Entrada del directorio central ---
            central.appendU32(0x0201_4b50)
            central.appendU16(e.versionMadeBy)
            central.appendU16(20)             // version needed
            central.appendU16(0)              // flags
            central.appendU16(e.method)
            central.appendU16(e.dosTime)
            central.appendU16(e.dosDate)
            central.appendU32(e.crc32)
            central.appendU32(UInt32(e.compressedData.count))
            central.appendU32(e.uncompressedSize)
            central.appendU16(UInt16(nameBytes.count))
            central.appendU16(0)              // extra
            central.appendU16(0)              // comment
            central.appendU16(0)              // disk number
            central.appendU16(0)              // internal attrs
            central.appendU32(e.externalAttributes)
            central.appendU32(localOffset)
            central.append(contentsOf: nameBytes)
        }

        let cdOffset = UInt32(out.count)
        let cdSize = UInt32(central.count)
        out.append(central)

        // --- End of Central Directory ---
        out.appendU32(0x0605_4b50)
        out.appendU16(0)                      // disk number
        out.appendU16(0)                      // disk with CD
        out.appendU16(UInt16(entries.count))
        out.appendU16(UInt16(entries.count))
        out.appendU32(cdSize)
        out.appendU32(cdOffset)
        out.appendU16(0)                      // comment length
        return out
    }

    // MARK: - Helpers de lectura binaria

    private static func findEOCD(_ b: [UInt8]) -> Int? {
        // El EOCD mide 22 bytes mínimo y puede llevar comentario al final.
        let minLen = 22
        guard b.count >= minLen else { return nil }
        let start = max(0, b.count - minLen - 0xFFFF)
        var i = b.count - minLen
        while i >= start {
            if readU32(b, i) == 0x0605_4b50 { return i }
            i -= 1
        }
        return nil
    }

    private static func readU16(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) | (Int(b[o + 1]) << 8)
    }
    private static func readU32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }
}

// MARK: - Append little-endian

private extension Data {
    mutating func appendU16(_ v: UInt16) {
        append(UInt8(v & 0xFF)); append(UInt8((v >> 8) & 0xFF))
    }
    mutating func appendU32(_ v: UInt32) {
        append(UInt8(v & 0xFF)); append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF)); append(UInt8((v >> 24) & 0xFF))
    }
}

// MARK: - DEFLATE crudo vía framework Compression

enum Deflate {
    /// Comprime con DEFLATE crudo (RFC 1951), el formato que espera el método 8 del ZIP.
    static func deflate(_ data: Data) -> Data? {
        if data.isEmpty { return Data() }
        let dstCap = data.count + 64
        var dst = Data(count: dstCap)
        let written = dst.withUnsafeMutableBytes { (dstRaw: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(
                    dstRaw.bindMemory(to: UInt8.self).baseAddress!, dstCap,
                    srcRaw.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        dst.removeSubrange(written..<dst.count)
        return dst
    }

    /// Descomprime DEFLATE crudo conociendo el tamaño original.
    static func inflate(_ data: Data, expectedSize: Int, name: String) throws -> Data {
        if expectedSize == 0 { return Data() }
        var dst = Data(count: expectedSize)
        let written = dst.withUnsafeMutableBytes { (dstRaw: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(
                    dstRaw.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    srcRaw.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ZipError.decompressionFailed(name) }
        return dst
    }
}
