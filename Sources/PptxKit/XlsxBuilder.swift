import Foundation

/// Construye un libro Excel (.xlsx) mínimo pero válido a partir de las celdas extraídas
/// de un gráfico. Suficiente para que PowerPoint lo incruste y permita «Editar datos».
enum XlsxBuilder {

    static func build(from chart: ChartData) -> Data {
        let sheetXML = worksheet(for: chart)
        let archive = ZipArchive()
        archive.addEntry(name: "[Content_Types].xml", data: Data(contentTypes.utf8))
        archive.addEntry(name: "_rels/.rels", data: Data(rootRels.utf8))
        archive.addEntry(name: "xl/workbook.xml", data: Data(workbook(sheetName: chart.sheetName).utf8))
        archive.addEntry(name: "xl/_rels/workbook.xml.rels", data: Data(workbookRels.utf8))
        archive.addEntry(name: "xl/styles.xml", data: Data(styles.utf8))
        archive.addEntry(name: "xl/worksheets/sheet1.xml", data: Data(sheetXML.utf8))
        return archive.write()
    }

    // MARK: - Hoja de cálculo

    private static func worksheet(for chart: ChartData) -> String {
        // Agrupar celdas por fila.
        var rows: [Int: [(col: Int, ref: String, value: String, numeric: Bool)]] = [:]
        for (ref, payload) in chart.cells {
            guard let (col, row) = ChartDataExtractor.parseCell(ref) else { continue }
            rows[row, default: []].append((col, ref, payload.value, payload.isNumeric))
        }

        var body = ""
        for row in rows.keys.sorted() {
            let cells = rows[row]!.sorted { $0.col < $1.col }
            body += "<row r=\"\(row)\">"
            for c in cells {
                if c.numeric, isFiniteNumber(c.value) {
                    body += "<c r=\"\(c.ref)\"><v>\(c.value)</v></c>"
                } else {
                    body += "<c r=\"\(c.ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(c.value))</t></is></c>"
                }
            }
            body += "</row>"
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(body)</sheetData></worksheet>
        """
    }

    private static func isFiniteNumber(_ s: String) -> Bool {
        Double(s) != nil
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Partes fijas

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
    """

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static func workbook(sheetName: String) -> String {
        let safe = sheetName.replacingOccurrences(of: "&", with: "&amp;")
                            .replacingOccurrences(of: "<", with: "&lt;")
                            .replacingOccurrences(of: "\"", with: "&quot;")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="\(safe)" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
    }

    private static let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
    """

    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
    """
}
