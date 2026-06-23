import Foundation
import PptxKit

/// Una fila editable de la tabla: enlace externo con su valor original y el nuevo.
struct LinkRow: Identifiable {
    let id: String
    let kind: String
    let ownerPart: String
    let originalTarget: String
    let isChartData: Bool       // ¿es el libro de datos de un gráfico? (se puede incrustar)
    var newTarget: String

    var isModified: Bool { newTarget != originalTarget }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var rows: [LinkRow] = []
    @Published var embedIds: Set<String> = []
    @Published var fileURL: URL?
    @Published var findText = ""
    @Published var replaceText = ""
    @Published var status = "Open a .pptx file to get started."
    @Published var hasLoaded = false

    private var originalData: Data?

    var modifiedCount: Int { rows.filter { $0.isModified && !embedIds.contains($0.id) }.count }
    var embedCount: Int { embedIds.count }
    var pendingChanges: Int { modifiedCount + embedCount }

    /// Chart-data links (the ones that can be embedded).
    var chartRows: [LinkRow] { rows.filter { $0.isChartData } }
    var hasChartLinks: Bool { !chartRows.isEmpty }
    var allChartsEmbedded: Bool { hasChartLinks && chartRows.allSatisfy { embedIds.contains($0.id) } }

    func isEmbedding(_ id: String) -> Bool { embedIds.contains(id) }

    func toggleEmbed(_ id: String) {
        if embedIds.contains(id) { embedIds.remove(id) } else { embedIds.insert(id) }
    }

    /// Marks every chart link to have its data embedded.
    func embedAllCharts() {
        for r in chartRows { embedIds.insert(r.id) }
        status = "\(embedIds.count) chart(s) will be embedded. Click “Save copy…” to write the file."
    }

    var fileName: String { fileURL?.lastPathComponent ?? "—" }

    /// Carga un .pptx y detecta sus enlaces externos.
    func open(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let doc = try PptxDocument(data: data, url: url)
            let links = try doc.externalLinks()
            self.originalData = data
            self.fileURL = url
            self.embedIds = []
            self.rows = links.map {
                LinkRow(id: $0.id, kind: $0.kind, ownerPart: $0.ownerPart,
                        originalTarget: $0.target,
                        isChartData: $0.partName.contains("/charts/"),
                        newTarget: $0.target)
            }
            self.hasLoaded = true
            if links.isEmpty {
                status = "No external data links found in this file."
            } else {
                let charts = links.filter { $0.partName.contains("/charts/") }.count
                status = charts > 0
                    ? "\(links.count) external link(s) found · \(charts) chart(s) can be embedded."
                    : "\(links.count) external link(s) found."
            }
        } catch {
            hasLoaded = false
            rows = []
            status = "Could not open the file: \(error)"
        }
    }

    /// Applies a text find/replace across all paths.
    func applyFindReplace() {
        guard !findText.isEmpty else { return }
        var count = 0
        for i in rows.indices where rows[i].newTarget.contains(findText) {
            rows[i].newTarget = rows[i].newTarget.replacingOccurrences(of: findText, with: replaceText)
            count += 1
        }
        status = count == 0
            ? "The search text doesn't appear in any path."
            : "Replaced in \(count) path(s)."
    }

    /// Revierte una fila a su valor original.
    func revert(_ id: String) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].newTarget = rows[i].originalTarget
    }

    /// Reverts all paths to their original value and cancels pending embeds.
    func revertAll() {
        for i in rows.indices { rows[i].newTarget = rows[i].originalTarget }
        embedIds.removeAll()
        status = "Changes discarded."
    }

    /// Guarda un nuevo .pptx con los cambios. Reaplica siempre desde los bytes
    /// originales para no acumular recompresiones.
    func save(to url: URL) {
        guard let originalData else { return }
        do {
            let doc = try PptxDocument(data: originalData)
            var edits: [String: String] = [:]
            for row in rows where row.isModified && !embedIds.contains(row.id) {
                edits[row.id] = row.newTarget
            }
            let out = try doc.save(edits: edits, embed: embedIds)
            try out.write(to: url)
            var parts: [String] = []
            if !embedIds.isEmpty { parts.append("\(embedIds.count) chart(s) embedded") }
            if !edits.isEmpty { parts.append("\(edits.count) path(s) edited") }
            let detail = parts.isEmpty ? "no changes" : parts.joined(separator: ", ")
            status = "Saved: \(url.lastPathComponent) (\(detail))."
        } catch {
            status = "Error saving: \(error)"
        }
    }
}
