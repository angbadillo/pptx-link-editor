import Foundation

/// Datos cacheados extraídos de un `chartN.xml`, listos para reconstruir un libro Excel.
struct ChartData {
    var sheetName: String
    /// Celdas a rellenar: referencia A1 -> (valor, ¿numérico?)
    var cells: [String: (value: String, isNumeric: Bool)]
    var isEmpty: Bool { cells.isEmpty }
}

/// Extrae los datos que el gráfico lleva cacheados dentro de su XML.
///
/// Cada serie referencia celdas vía `<c:f>` (p. ej. `Sheet1!$B$2:$B$4`) y guarda los
/// valores en `<c:numCache>` / `<c:strCache>`. Recorremos TODAS las referencias
/// (`<c:numRef>` y `<c:strRef>`), de modo que sirve para cualquier tipo de gráfico.
enum ChartDataExtractor {

    private static let refRegex = try! NSRegularExpression(
        pattern: "<c:(numRef|strRef)\\b.*?</c:\\1>", options: [.dotMatchesLineSeparators])
    private static let fRegex = try! NSRegularExpression(
        pattern: "<c:f>(.*?)</c:f>", options: [.dotMatchesLineSeparators])
    private static let ptRegex = try! NSRegularExpression(
        pattern: "<c:pt\\b[^>]*\\bidx=\"(\\d+)\"[^>]*>\\s*<c:v>(.*?)</c:v>", options: [.dotMatchesLineSeparators])

    static func extract(from chartXML: String) -> ChartData {
        let ns = chartXML as NSString
        var cells: [String: (String, Bool)] = [:]
        var sheetName: String?
        var sheetVotes: [String: Int] = [:]

        for m in refRegex.matches(in: chartXML, range: NSRange(location: 0, length: ns.length)) {
            let block = ns.substring(with: m.range)
            let isNumeric = block.hasPrefix("<c:numRef")

            guard let f = firstGroup(fRegex, in: block) else { continue }
            let unescapedF = RelsParser.xmlUnescape(f)
            guard let (sheet, refCells) = parseFormula(unescapedF) else { continue }
            if let sheet { sheetVotes[sheet, default: 0] += 1 }

            // Puntos cacheados idx -> valor
            let bns = block as NSString
            for pm in ptRegex.matches(in: block, range: NSRange(location: 0, length: bns.length)) {
                guard let idx = Int(bns.substring(with: pm.range(at: 1))) else { continue }
                let value = RelsParser.xmlUnescape(bns.substring(with: pm.range(at: 2)))
                if idx < refCells.count {
                    cells[refCells[idx]] = (value, isNumeric)
                }
            }
        }
        sheetName = sheetVotes.max { $0.value < $1.value }?.key
        return ChartData(sheetName: sheetName ?? "Sheet1", cells: cells)
    }

    // MARK: - Parseo de fórmulas/celdas

    /// `Sheet1!$B$2:$B$4` -> ("Sheet1", ["B2","B3","B4"])  (en orden de idx)
    static func parseFormula(_ formula: String) -> (sheet: String?, cells: [String])? {
        var sheet: String?
        var ref = formula
        if let bang = formula.firstIndex(of: "!") {
            sheet = String(formula[..<bang])
            ref = String(formula[formula.index(after: bang)...])
            // Quitar comillas de nombres tipo 'Hoja 1'
            if sheet!.hasPrefix("'") && sheet!.hasSuffix("'") && sheet!.count >= 2 {
                sheet = String(sheet!.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
        }
        ref = ref.replacingOccurrences(of: "$", with: "")
        let parts = ref.split(separator: ":").map(String.init)
        guard let first = parts.first, let (c1, r1) = parseCell(first) else { return nil }
        if parts.count == 1 {
            return (sheet, [cellName(col: c1, row: r1)])
        }
        guard parts.count >= 2, let (c2, r2) = parseCell(parts[1]) else { return nil }

        var result: [String] = []
        let (colLo, colHi) = (min(c1, c2), max(c1, c2))
        let (rowLo, rowHi) = (min(r1, r2), max(r1, r2))
        // Enumeración: por columnas dentro de cada fila (suficiente para rangos 1-D
        // tanto verticales como horizontales, que es lo habitual en gráficos).
        if colLo == colHi {
            for r in rowLo...rowHi { result.append(cellName(col: colLo, row: r)) }
        } else if rowLo == rowHi {
            for c in colLo...colHi { result.append(cellName(col: c, row: rowLo)) }
        } else {
            for r in rowLo...rowHi { for c in colLo...colHi { result.append(cellName(col: c, row: r)) } }
        }
        return (sheet, result)
    }

    /// "B12" -> (col:2, row:12)
    static func parseCell(_ s: String) -> (col: Int, row: Int)? {
        var col = 0, i = s.startIndex
        while i < s.endIndex, s[i].isLetter {
            col = col * 26 + (Int(s[i].uppercased().unicodeScalars.first!.value) - 64)
            i = s.index(after: i)
        }
        let rowStr = String(s[i...])
        guard col > 0, let row = Int(rowStr) else { return nil }
        return (col, row)
    }

    static func cellName(col: Int, row: Int) -> String {
        var n = col, letters = ""
        while n > 0 {
            let rem = (n - 1) % 26
            letters = String(UnicodeScalar(65 + rem)!) + letters
            n = (n - 1) / 26
        }
        return "\(letters)\(row)"
    }

    private static func firstGroup(_ re: NSRegularExpression, in s: String) -> String? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
