import Foundation
import Combine
import SceneKit
import AppKit

@MainActor
final class ExplorerViewModel: ObservableObject {
    @Published var rootURL: URL? = nil
    @Published var includeHidden: Bool = false
    @Published var isScanning: Bool = false
    @Published var rootNode: FileNode? = nil
    @Published var scene: SCNScene = SCNScene()
    @Published var selected: FileNode? = nil
    @Published var errorMessage: String? = nil

    private let builder = SceneBuilder()

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.title = "Choose a folder to visualize"

        if panel.runModal() == .OK, let url = panel.url {
            rootURL = url
            Task { await rescan() }
        }
    }

    func rescan() async {
        guard let url = rootURL else { return }
        isScanning = true
        errorMessage = nil
        defer { isScanning = false }
        do {
            let options = FileScanner.Options(includeHidden: includeHidden, followSymlinks: false, maxDepth: 2, packageAsFiles: true)
            let node = try FileScanner.scan(root: url, options: options)
            rootNode = node
            rebuildScene()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rebuildScene() {
        guard let rootNode else {
            scene = SCNScene()
            return
        }
        scene = builder.makeScene(for: rootNode)
    }

    func select(byPath path: String) {
        guard let root = rootNode else { return }
        selected = findNode(in: root, path: path)
    }

    private func findNode(in node: FileNode, path: String) -> FileNode? {
        if node.url.path == path { return node }
        for child in node.children {
            if let found = findNode(in: child, path: path) { return found }
        }
        return nil
    }

    func revealSelectedInFinder() {
        guard let url = selected?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openSelected() {
        guard let url = selected?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func trashSelected() {
        guard let url = selected?.url else { return }
        do {
            var resultingURL: NSURL? = nil
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            // After deletion, rescan to refresh
            Task { await rescan() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

