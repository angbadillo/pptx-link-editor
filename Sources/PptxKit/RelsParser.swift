import Foundation

/// Parser ligero de ficheros `.rels` (Open Packaging Conventions).
///
/// No reconstruye el XML: lee atributos con expresiones regulares y, al editar,
/// hace un reemplazo *quirúrgico* del atributo `Target` dejando intacto todo lo demás.
enum RelsParser {

    struct Relationship {
        let id: String
        let type: String
        let target: String
        let targetMode: String
    }

    private static let relRegex = try! NSRegularExpression(
        pattern: "<Relationship\\b[^>]*?/?>", options: [.caseInsensitive])

    static func relationships(in xml: String) -> [Relationship] {
        let ns = xml as NSString
        let matches = relRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        return matches.map { m in
            let tag = ns.substring(with: m.range)
            return Relationship(
                id: attribute("Id", in: tag) ?? "",
                type: attribute("Type", in: tag) ?? "",
                target: xmlUnescape(attribute("Target", in: tag) ?? ""),
                targetMode: attribute("TargetMode", in: tag) ?? "")
        }
    }

    /// Reemplaza el `Target` de la relación con `relId` por `newTarget` (ya sin escapar).
    static func replacingTarget(in xml: String, relId: String, with newTarget: String) -> String {
        let ns = xml as NSString
        let matches = relRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        // Recorremos de atrás hacia delante para no invalidar los rangos al sustituir.
        var result = xml
        for m in matches.reversed() {
            let tag = ns.substring(with: m.range)
            guard attribute("Id", in: tag) == relId else { continue }
            let newTag = replacingTargetAttribute(in: tag, with: xmlEscape(newTarget))
            let r = Range(m.range, in: result)!
            result.replaceSubrange(r, with: newTag)
        }
        return result
    }

    /// Convierte la relación `relId` en una relación INTERNA a un paquete embebido
    /// (workbook). Sustituye la etiqueta entera: tipo `package`, sin `TargetMode`.
    static func makeInternalEmbedding(in xml: String, relId: String, target: String) -> String {
        let ns = xml as NSString
        let matches = relRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        var result = xml
        for m in matches.reversed() {
            let tag = ns.substring(with: m.range)
            guard attribute("Id", in: tag) == relId else { continue }
            let newTag = "<Relationship Id=\"\(relId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/package\" Target=\"\(xmlEscape(target))\"/>"
            let r = Range(m.range, in: result)!
            result.replaceSubrange(r, with: newTag)
        }
        return result
    }

    // MARK: - Internos

    private static func attribute(_ name: String, in tag: String) -> String? {
        // Soporta comillas dobles y simples.
        for quote in ["\"", "'"] {
            let pattern = "\\b\(name)\\s*=\\s*\(quote)([^\(quote)]*)\(quote)"
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let ns = tag as NSString
                if let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)),
                   m.numberOfRanges >= 2 {
                    return ns.substring(with: m.range(at: 1))
                }
            }
        }
        return nil
    }

    private static func replacingTargetAttribute(in tag: String, with escapedValue: String) -> String {
        for quote in ["\"", "'"] {
            let pattern = "(\\bTarget\\s*=\\s*\(quote))[^\(quote)]*(\(quote))"
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let ns = tag as NSString
                let range = NSRange(location: 0, length: ns.length)
                if re.firstMatch(in: tag, range: range) != nil {
                    let tmpl = "$1" + NSRegularExpression.escapedTemplate(for: escapedValue) + "$2"
                    return re.stringByReplacingMatches(in: tag, range: range, withTemplate: tmpl)
                }
            }
        }
        return tag
    }

    static func xmlEscape(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "&", with: "&amp;")
        r = r.replacingOccurrences(of: "<", with: "&lt;")
        r = r.replacingOccurrences(of: ">", with: "&gt;")
        r = r.replacingOccurrences(of: "\"", with: "&quot;")
        r = r.replacingOccurrences(of: "'", with: "&apos;")
        return r
    }

    static func xmlUnescape(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "&quot;", with: "\"")
        r = r.replacingOccurrences(of: "&apos;", with: "'")
        r = r.replacingOccurrences(of: "&lt;", with: "<")
        r = r.replacingOccurrences(of: "&gt;", with: ">")
        r = r.replacingOccurrences(of: "&amp;", with: "&")
        return r
    }
}
