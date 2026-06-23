import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct PPTXLinkEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("PPTX Link Editor") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 480)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open .pptx…") { model.openWithPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Save copy…") { model.saveWithPanel() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.hasLoaded)
            }
        }
    }
}

/// Asegura que la app se comporte como aplicación normal (icono en el Dock, ventana al frente).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

// MARK: - Paneles de archivo

extension AppModel {
    static var pptxType: UTType { UTType(filenameExtension: "pptx") ?? .data }

    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.pptxType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func saveWithPanel() {
        guard hasLoaded else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.pptxType]
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? "presentation"
        panel.nameFieldStringValue = "\(base)_edited.pptx"
        panel.prompt = "Save"
        if panel.runModal() == .OK, let url = panel.url {
            save(to: url)
        }
    }
}
