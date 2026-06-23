import Foundation

/// Un enlace externo encontrado dentro del .pptx (relación con `TargetMode="External"`).
public struct ExternalLink: Identifiable, Hashable {
    public let id: String                 // estable: "<parte>#<rId>"
    public let partName: String           // p.ej. ppt/charts/_rels/chart1.xml.rels
    public let relationshipId: String     // p.ej. rId3
    public let relationshipType: String   // URI del tipo de relación
    public let target: String             // valor actual del atributo Target

    /// Human-readable label for the link type.
    public var kind: String {
        let t = relationshipType.lowercased()
        if t.hasSuffix("/hyperlink") { return "Hyperlink" }
        if t.hasSuffix("/oleobject") { return "OLE object (linked data)" }
        if t.hasSuffix("/package") { return "Linked workbook" }
        if t.contains("externallink") { return "External link" }
        if t.hasSuffix("/image") { return "External image" }
        if t.hasSuffix("/audio") || t.hasSuffix("/video") || t.hasSuffix("/media") { return "External media" }
        return "Other"
    }

    /// Parte del documento que contiene la relación (sin el sufijo `_rels/…rels`).
    public var ownerPart: String {
        // ppt/charts/_rels/chart1.xml.rels -> ppt/charts/chart1.xml
        guard let range = partName.range(of: "_rels/") else { return partName }
        var owner = partName
        owner.removeSubrange(range)
        if owner.hasSuffix(".rels") { owner.removeLast(5) }
        return owner
    }
}

/// Documento .pptx cargado en memoria: localiza enlaces externos y los reescribe
/// sin recomprimir el resto del paquete.
public final class PptxDocument {
    private let archive: ZipArchive
    public let url: URL?

    public init(data: Data, url: URL? = nil) throws {
        self.archive = try ZipArchive.read(data: data)
        self.url = url
    }

    public convenience init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        try self.init(data: data, url: url)
    }

    /// Localiza todos los enlaces externos del paquete.
    public func externalLinks() throws -> [ExternalLink] {
        var result: [ExternalLink] = []
        for entry in archive.entries where entry.name.hasSuffix(".rels") {
            let xml = String(decoding: try entry.data(), as: UTF8.self)
            for rel in RelsParser.relationships(in: xml) {
                guard rel.targetMode.lowercased() == "external" else { continue }
                result.append(ExternalLink(
                    id: "\(entry.name)#\(rel.id)",
                    partName: entry.name,
                    relationshipId: rel.id,
                    relationshipType: rel.type,
                    target: rel.target))
            }
        }
        // Orden estable: por parte y luego por rId.
        return result.sorted { ($0.partName, $0.relationshipId) < ($1.partName, $1.relationshipId) }
    }

    /// Incrusta en el .pptx los datos cacheados de los gráficos indicados (por id de
    /// enlace) y aplica además las ediciones de ruta del resto, devolviendo los bytes
    /// del .pptx resultante.
    public func save(edits: [String: String], embed embedIds: Set<String> = []) throws -> Data {
        for linkId in embedIds {
            try embedChartData(linkId: linkId)
        }
        // No reescribir como ruta externa los que ya hemos incrustado.
        let remaining = edits.filter { !embedIds.contains($0.key) }
        return try applyPathEdits(remaining)
    }

    /// Convierte un gráfico vinculado en uno con datos incrustados.
    private func embedChartData(linkId: String) throws {
        guard let hash = linkId.range(of: "#") else { throw ZipError.entryNotFound(linkId) }
        let relsPart = String(linkId[..<hash.lowerBound])           // ppt/charts/_rels/chartN.xml.rels
        let relId = String(linkId[hash.upperBound...])

        // Parte dueña (el gráfico): ppt/charts/chartN.xml
        guard let relsRange = relsPart.range(of: "_rels/") else { throw ZipError.entryNotFound(relsPart) }
        var chartPart = relsPart
        chartPart.removeSubrange(relsRange)
        if chartPart.hasSuffix(".rels") { chartPart.removeLast(5) }

        guard let chartEntry = archive.entry(named: chartPart) else { throw ZipError.entryNotFound(chartPart) }
        let chartXML = String(decoding: try chartEntry.data(), as: UTF8.self)

        let data = ChartDataExtractor.extract(from: chartXML)
        guard !data.isEmpty else { throw ZipError.embeddingFailed(chartPart) }

        // Construir el .xlsx e incrustarlo con un nombre único.
        let xlsx = XlsxBuilder.build(from: data)
        let baseName = (chartPart as NSString).lastPathComponent
            .replacingOccurrences(of: ".xml", with: "")
        let embeddingPath = uniqueEmbeddingPath(base: "Datos_\(baseName)")
        archive.addEntry(name: embeddingPath, data: xlsx)

        // Reescribir la relación: externa -> interna (../embeddings/…)
        guard let relsEntry = archive.entry(named: relsPart) else { throw ZipError.entryNotFound(relsPart) }
        let relTarget = "../embeddings/" + (embeddingPath as NSString).lastPathComponent
        var relsXML = String(decoding: try relsEntry.data(), as: UTF8.self)
        relsXML = RelsParser.makeInternalEmbedding(in: relsXML, relId: relId, target: relTarget)
        relsEntry.replace(with: Data(relsXML.utf8))

        // Declarar la extensión xlsx en [Content_Types].xml si no estuviera.
        try ensureXlsxContentType()
    }

    private func uniqueEmbeddingPath(base: String) -> String {
        var name = "ppt/embeddings/\(base).xlsx"
        var i = 2
        while archive.entry(named: name) != nil {
            name = "ppt/embeddings/\(base)_\(i).xlsx"
            i += 1
        }
        return name
    }

    private func ensureXlsxContentType() throws {
        guard let ct = archive.entry(named: "[Content_Types].xml") else { return }
        var xml = String(decoding: try ct.data(), as: UTF8.self)
        if xml.range(of: "Extension=\"xlsx\"", options: .caseInsensitive) != nil { return }
        let decl = "<Default Extension=\"xlsx\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"/>"
        if let r = xml.range(of: "</Types>") {
            xml.replaceSubrange(r, with: decl + "</Types>")
            ct.replace(with: Data(xml.utf8))
        }
    }

    /// Aplica cambios `id -> nuevoTarget` y devuelve los bytes del .pptx resultante.
    /// Solo se recomprimen los `.rels` modificados; el resto se copia tal cual.
    public func save(edits: [String: String]) throws -> Data {
        try applyPathEdits(edits)
    }

    private func applyPathEdits(_ edits: [String: String]) throws -> Data {
        // Agrupar los cambios por parte (.rels).
        var byPart: [String: [(relId: String, newTarget: String)]] = [:]
        for (linkId, newTarget) in edits {
            guard let hash = linkId.range(of: "#") else { continue }
            let part = String(linkId[..<hash.lowerBound])
            let relId = String(linkId[hash.upperBound...])
            byPart[part, default: []].append((relId, newTarget))
        }

        for (part, changes) in byPart {
            guard let entry = archive.entry(named: part) else { throw ZipError.entryNotFound(part) }
            var xml = String(decoding: try entry.data(), as: UTF8.self)
            for change in changes {
                xml = RelsParser.replacingTarget(in: xml, relId: change.relId, with: change.newTarget)
            }
            entry.replace(with: Data(xml.utf8))
        }
        return archive.write()
    }
}
