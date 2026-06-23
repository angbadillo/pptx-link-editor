import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.hasLoaded {
                if model.rows.isEmpty {
                    emptyMessage("This file has no external data links.")
                } else {
                    linksList
                    Divider()
                    redirectBar
                }
            } else {
                dropZone
            }
            Divider()
            statusBar
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                model.openWithPanel()
            } label: {
                Label("Open .pptx", systemImage: "folder")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.hasLoaded ? model.fileName : "No file open")
                    .font(.headline)
                if model.hasLoaded {
                    Text("\(model.rows.count) link(s) · \(model.embedCount) to embed · \(model.modifiedCount) path(s) edited")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if model.hasLoaded && model.hasChartLinks {
                Button {
                    model.embedAllCharts()
                } label: {
                    Label("Embed all charts", systemImage: "tray.and.arrow.down.fill")
                }
                .tint(.green)
                .disabled(model.allChartsEmbedded)
                .help("Embed every chart's data so the presentation no longer depends on external Excel files")
            }

            Button {
                model.saveWithPanel()
            } label: {
                Label("Save copy…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.hasLoaded)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(12)
    }

    // MARK: - Links list

    private var linksList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach($model.rows) { $row in
                    LinkRowView(row: $row,
                                isEmbedding: model.isEmbedding(row.id),
                                onRevert: { model.revert(row.id) },
                                onToggleEmbed: { model.toggleEmbed(row.id) })
                    Divider()
                }
            }
        }
    }

    // MARK: - Secondary: find & replace on paths (for "redirect" workflow)

    private var redirectBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.secondary)
            Text("Find & replace in paths:")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Find (e.g. C:\\Users\\old)", text: $model.findText)
                .textFieldStyle(.roundedBorder)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            TextField("Replace with", text: $model.replaceText)
                .textFieldStyle(.roundedBorder)
            Button("Apply to all") { model.applyFindReplace() }
                .disabled(model.findText.isEmpty)
            Button("Discard changes") { model.revertAll() }
                .disabled(model.pendingChanges == 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.25))
    }

    private func emptyMessage(_ text: String) -> some View {
        VStack {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drag a .pptx file here")
                .font(.title3)
            Text("or use the “Open .pptx” button")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Drag & drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.pathExtension.lowercased() == "pptx" else { return }
            DispatchQueue.main.async { model.open(url: url) }
        }
        return true
    }
}

/// A single link row. For chart links, embedding is the primary action and
/// redirecting to another file is a secondary, collapsible option.
struct LinkRowView: View {
    @Binding var row: LinkRow
    let isEmbedding: Bool
    let onRevert: () -> Void
    let onToggleEmbed: () -> Void

    @State private var showRedirect = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: type + owning part
            VStack(alignment: .leading, spacing: 2) {
                Text(row.kind)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.tint.opacity(0.15))
                    .clipShape(Capsule())
                Text(row.ownerPart)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 190, alignment: .leading)

            // Middle: primary action(s)
            VStack(alignment: .leading, spacing: 8) {
                if isEmbedding {
                    embeddingState
                } else if row.isChartData {
                    chartPrimary
                    redirectDisclosure
                } else {
                    pathEditor   // non-chart links can only be redirected
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isEmbedding ? Color.green.opacity(0.08)
                    : (row.isModified ? Color.orange.opacity(0.06) : Color.clear))
    }

    // MARK: Embedding (primary)

    private var chartPrimary: some View {
        HStack(spacing: 12) {
            Button {
                onToggleEmbed()
            } label: {
                Label("Embed data", systemImage: "tray.and.arrow.down.fill")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .help("Rebuild the chart's data as a tiny workbook inside the .pptx — self-contained, no external file")

            VStack(alignment: .leading, spacing: 1) {
                Text("Make this chart self-contained")
                    .font(.callout.weight(.medium))
                Text("Embeds the chart's data; removes the external dependency.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var embeddingState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Data will be embedded")
                    .font(.callout.weight(.semibold))
                Text("This chart becomes self-contained when you save.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .cancel) {
                onToggleEmbed()
            } label: {
                Label("Cancel", systemImage: "arrow.uturn.backward")
            }
        }
    }

    // MARK: Redirect (secondary)

    private var redirectDisclosure: some View {
        DisclosureGroup(isExpanded: $showRedirect) {
            pathEditor.padding(.top, 6)
        } label: {
            Text("Or redirect to another file")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pathEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Path to the data file", text: $row.newTarget, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button {
                    chooseFile()
                } label: {
                    Label("Browse…", systemImage: "folder")
                }
                .help("Pick the .xlsx on disk and point the link to it. Doesn't copy or embed the file — only updates the link path.")
                Button {
                    onRevert()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .disabled(!row.isModified)
                .help("Revert this path")
            }
            if looksMalformed {
                Label("Unencoded spaces. PowerPoint usually needs them as %20 (use “Browse…”).",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if row.isModified {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.circle.fill").foregroundStyle(.orange)
                    Text("Original: \(row.originalTarget)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }

    /// Warns about an unencoded space (a common "not found" cause in PowerPoint).
    private var looksMalformed: Bool {
        let t = row.newTarget
        return t.lowercased().hasPrefix("file:") && t.contains(" ")
    }

    /// Opens a file picker and fills the path with a valid file:// URI.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let xlsx = UTType(filenameExtension: "xlsx") {
            panel.allowedContentTypes = [xlsx, .spreadsheet, .commaSeparatedText, .data]
        }
        panel.prompt = "Use this file"
        if panel.runModal() == .OK, let url = panel.url {
            row.newTarget = Self.fileURI(for: url)
        }
    }

    /// Builds the standard file:// URI PowerPoint for Mac resolves for LOCAL files:
    ///   file:///Users/user/Desktop/tablas.xlsx  (three slashes, "/" separators, %20 spaces).
    ///
    /// Note: links to `~/Library/CloudStorage/…` (OneDrive, etc.) don't work even with the
    /// right format, due to PowerPoint's sandbox. Use a local folder, or relink from within
    /// PowerPoint itself — or, better, embed the data (the primary action above).
    static func fileURI(for url: URL) -> String {
        url.absoluteString
    }
}
