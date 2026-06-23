import Foundation
import PptxKit

// CLI mínimo para validar el núcleo PptxKit sin GUI.
//   pptxcli list <archivo.pptx>
//   pptxcli replace <archivo.pptx> <buscar> <reemplazar> <salida.pptx>

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + msg + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("""
    Uso:
      pptxcli list <archivo.pptx>
      pptxcli replace <archivo.pptx> <buscar> <reemplazar> <salida.pptx>
    """)
    exit(0)
}

let command = args[1]

do {
    switch command {
    case "list":
        guard args.count >= 3 else { fail("falta el archivo") }
        let doc = try PptxDocument(contentsOf: URL(fileURLWithPath: args[2]))
        let links = try doc.externalLinks()
        if links.isEmpty { print("No se encontraron enlaces externos.") }
        for l in links {
            print("[\(l.kind)] \(l.ownerPart)")
            print("    id:     \(l.id)")
            print("    target: \(l.target)")
        }

    case "replace":
        guard args.count >= 6 else { fail("uso: replace <in> <buscar> <reemplazar> <out>") }
        let inURL = URL(fileURLWithPath: args[2])
        let find = args[3], repl = args[4]
        let outURL = URL(fileURLWithPath: args[5])
        let doc = try PptxDocument(contentsOf: inURL)
        let links = try doc.externalLinks()
        var edits: [String: String] = [:]
        for l in links where l.target.contains(find) {
            edits[l.id] = l.target.replacingOccurrences(of: find, with: repl)
        }
        let out = try doc.save(edits: edits)
        try out.write(to: outURL)
        print("Modificados \(edits.count) enlace(s). Guardado en \(outURL.path)")

    case "embed":
        guard args.count >= 4 else { fail("uso: embed <in> <out>  (incrusta TODOS los gráficos vinculados)") }
        let doc = try PptxDocument(contentsOf: URL(fileURLWithPath: args[2]))
        let links = try doc.externalLinks()
        // Solo los que son datos de gráfico (relación dentro de ppt/charts/).
        let chartLinks = links.filter { $0.partName.contains("/charts/") }
        let ids = Set(chartLinks.map(\.id))
        let out = try doc.save(edits: [:], embed: ids)
        try out.write(to: URL(fileURLWithPath: args[3]))
        print("Incrustados \(ids.count) gráfico(s). Guardado en \(args[3])")

    default:
        fail("comando desconocido: \(command)")
    }
} catch {
    fail("\(error)")
}
