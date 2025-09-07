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
    @Published var focusNode: FileNode? = nil
    @Published var scene: SCNScene = SCNScene()
    @Published var selected: FileNode? = nil
    @Published var errorMessage: String? = nil
    @Published var searchText: String = ""
    @Published var maxItems: Int = 256
    @Published var roomsMode: Bool = false // rooms disabled per user feedback
    @Published var showInfoPanel: Bool = true
    @Published var enabledKinds: Set<FileKind> = Set(FileKind.allCases)
    @Published var showInlineLabels: Bool = true
    @Published var previewLimit: Int = 20
    @Published var gapScale: Double = 1.0  // 0..2 range used to scale gaps
    @Published var alphaScale: Double = 1.0 // 0..1 transparency intensity
    @Published var exactPackageSizes: Bool = true
    @Published var zoomKey: ZoomKey = .control
    @Published var overlayMessage: String? = nil

    // Aggregate 'Others' for current focus
    private(set) var othersChildren: [FileNode] = []
    private let othersSentinelName = "__filescape_others__"

    private let builder = SceneBuilder()
    private var navStack: [FileNode] = []
    private var scope = SecurityScope()

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.title = "Choose a folder to visualize"

        if panel.runModal() == .OK, let url = panel.url {
            // Manage security-scoped access for sandbox
            scope.begin(for: url)
            rootURL = url
            Task { await rescan() }
        }
    }

    func rescan() async {
        guard let url = rootURL else { return }
        scope.ensure(for: url)
        isScanning = true
        errorMessage = nil
        defer { isScanning = false }
        do {
            let options = FileScanner.Options(includeHidden: includeHidden, followSymlinks: false, maxDepth: 2, packageAsFiles: true, skipPaths: [], fileCountLimit: 500_000, computePackageSizesDeep: exactPackageSizes)
            let node = try FileScanner.scan(root: url, options: options)
            rootNode = node
            navStack = [node]
            focusNode = node
            selected = nil
            rebuildScene()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rebuildScene() {
        guard let focus = focusNode else {
            scene = SCNScene()
            return
        }
        overlayMessage = (focus.children.isEmpty ? "This folder appears empty. If this seems wrong, try toggling Hidden or choose the folder directly to grant access." : nil)
        let children = filteredChildren(from: focus.children)
        let (top, rest) = topAndRest(children: children, limit: maxItems)
        othersChildren = rest
        var display = top
        if !rest.isEmpty {
            let othersNode = FileNode(url: focus.url.appendingPathComponent(othersSentinelName),
                                      name: "Others (\(rest.count))",
                                      isDirectory: true,
                                      isPackage: false,
                                      fileExtension: nil,
                                      uti: nil,
                                      sizeBytes: rest.reduce(0) { $0 &+ $1.sizeBytes },
                                      creationDate: nil,
                                      modificationDate: nil,
                                      accessDate: nil,
                                      children: [])
            display.append(othersNode)
        }

        let matches = matchPaths(for: searchText, in: display)
        let alphaMin = CGFloat(0.05 + (1.0 - alphaScale) * 0.5)
        let alphaMax = CGFloat(0.98 - (1.0 - alphaScale) * 0.4)
        let gapBaseScaled = CGFloat(0.06 * gapScale)
        let gapRangeScaled = CGFloat(0.25 * gapScale)

        let config = SceneBuilder.Config(
            minBlock: 0.2,
            maxBlock: 5.0,
            spacing: 0.6,
            constantHeight: 0.4,
            useAgeForHeight: false,
            ageMaxDays: 365.0,
            maxItems: 256,
            minAlpha: alphaMin,
            maxAlpha: alphaMax,
            gapBase: gapBaseScaled,
            gapRange: gapRangeScaled,
            ringGap: 1.0,
            showLabels: showInlineLabels,
            labelMinRel: 0.12,
            labelMaxChars: 28,
            previewLimit: previewLimit,
            enablePreview: true,
            armSpread: 0.7,
            armPitch: 1.0,
            useFamilyArms: true
        )
        let builder = SceneBuilder(config: config)

        // Preserve current camera transform when rebuilding
        var cameraTransform: SCNMatrix4? = nil
        if let camNode = scene.rootNode.childNodes.first(where: { $0.camera != nil }) {
            cameraTransform = camNode.transform
        }

        scene = builder.makeScene(for: focus,
                                  selectedPath: selected?.url.path,
                                  matchPaths: matches,
                                  childrenOverride: display,
                                  roomsMode: false,
                                  previewProvider: { [weak self] node in
                                      guard let self else { return nil }
                                      return self.previewChildren(for: node)
                                  },
                                  cameraTransformOverride: cameraTransform)
    }

    enum ZoomKey: String, CaseIterable, Identifiable {
        case control, option, command, shift
        var id: String { rawValue }
        var flag: NSEvent.ModifierFlags {
            switch self {
            case .control: return .control
            case .option: return .option
            case .command: return .command
            case .shift: return .shift
            }
        }
        var label: String { rawValue.capitalized }
    }

    deinit { scope.stop() }

    func select(byPath path: String) {
        guard let root = rootNode else { return }
        if path.hasSuffix(othersSentinelName) {
            selected = findInArray(array: breadcrumbs().last?.children ?? [], path: path) ??
                       FileNode(url: URL(fileURLWithPath: path),
                                name: "Others (\(othersChildren.count))",
                                isDirectory: true,
                                isPackage: false,
                                fileExtension: nil,
                                uti: nil,
                                sizeBytes: othersChildren.reduce(0) { $0 &+ $1.sizeBytes },
                                creationDate: nil,
                                modificationDate: nil,
                                accessDate: nil,
                                children: [])
        } else {
            selected = findNode(in: root, path: path)
        }
    }

    private func findNode(in node: FileNode, path: String) -> FileNode? {
        if node.url.path == path { return node }
        for child in node.children {
            if let found = findNode(in: child, path: path) { return found }
        }
        return nil
    }

    private func findInArray(array: [FileNode], path: String) -> FileNode? {
        for n in array { if n.url.path == path { return n } }
        return nil
    }

    func revealSelectedInFinder() {
        guard let url = selected?.url, url.lastPathComponent != othersSentinelName else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openSelected() {
        guard let url = selected?.url, url.lastPathComponent != othersSentinelName else { return }
        NSWorkspace.shared.open(url)
    }

    func trashSelected() {
        guard let url = selected?.url, url.lastPathComponent != othersSentinelName else { return }
        do {
            var resultingURL: NSURL? = nil
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            // After deletion, rescan to refresh
            Task { await rescan() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enterSelectedFolder() {
        guard let s = selected, s.isDirectory else { return }
        if s.url.lastPathComponent == othersSentinelName {
            let synthetic = FileNode(url: s.url, name: s.name, isDirectory: true, isPackage: false, fileExtension: nil, uti: nil, sizeBytes: s.sizeBytes, creationDate: nil, modificationDate: nil, accessDate: nil, children: othersChildren)
            navStack.append(synthetic)
            focusNode = synthetic
            selected = nil
            rebuildScene()
            return
        }
        // On-demand deeper scan for the selected folder
        Task {
            isScanning = true
            defer { isScanning = false }
            do {
                let options = FileScanner.Options(includeHidden: includeHidden, followSymlinks: false, maxDepth: 2, packageAsFiles: true, skipPaths: [], fileCountLimit: 500_000, computePackageSizesDeep: exactPackageSizes)
                let newlyScanned = try FileScanner.scan(root: s.url, options: options)
                navStack.append(newlyScanned)
                focusNode = newlyScanned
                selected = nil
                rebuildScene()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func goUp() {
        guard navStack.count > 1 else { return }
        _ = navStack.popLast()
        focusNode = navStack.last
        selected = nil
        rebuildScene()
    }

    func breadcrumbs() -> [FileNode] {
        navStack
    }

    func goToBreadcrumb(index: Int) {
        guard index >= 0 && index < navStack.count else { return }
        navStack = Array(navStack.prefix(index + 1))
        focusNode = navStack.last
        selected = nil
        rebuildScene()
    }

    private func matchPaths(for query: String, in children: [FileNode]) -> Set<String> {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let lower = q.lowercased()
        let matches = children.filter { $0.name.lowercased().contains(lower) }
        return Set(matches.map { $0.url.path })
    }

    private func filteredChildren(from children: [FileNode]) -> [FileNode] {
        children.filter { node in
            if node.isDirectory { return true }
            let kind = FileKind.from(ext: node.fileExtension, uti: node.uti)
            return enabledKinds.contains(kind)
        }.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func topAndRest(children: [FileNode], limit: Int) -> ([FileNode], [FileNode]) {
        guard children.count > limit else { return (children, []) }
        let top = Array(children.prefix(limit))
        let rest = Array(children.dropFirst(limit))
        return (top, rest)
    }

    // MARK: - Preview children (for packages and large folders)
    private var previewCache: [String: [FileNode]] = [:]
    private func previewChildren(for node: FileNode) -> [FileNode]? {
        if node.isDirectory {
            // For directories we already have children at current focus depth
            return node.children
        }
        if node.isPackage {
            if let cached = previewCache[node.url.path] { return cached }
            // Lightweight one-level scan to preview package contents
            do {
                var visited: Set<String> = []
                var remaining = 50_000
                let fm = FileManager.default
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .typeIdentifierKey, .fileSizeKey, .totalFileAllocatedSizeKey]
                let urls = try fm.contentsOfDirectory(at: node.url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                let children: [FileNode] = urls.prefix(60).compactMap { url in
                    guard let rv = try? url.resourceValues(forKeys: keys) else { return nil }
                    if rv.isDirectory == true && rv.isPackage != true {
                        // Get rough size of immediate directory level (not deep)
                        let s = (try? FileScanner.directorySize(at: url, includeHidden: false, followSymlinks: false, visited: &visited, remainingCount: &remaining)) ?? 0
                        return FileNode(url: url, name: url.lastPathComponent, isDirectory: true, isPackage: false, fileExtension: url.pathExtension, uti: rv.typeIdentifier, sizeBytes: s, creationDate: nil, modificationDate: nil, accessDate: nil, children: [])
                    } else {
                        let allocatedSize64: Int64? = (rv.totalFileAllocatedSize as NSNumber?)?.int64Value
                        let fileSize64: Int64? = rv.fileSize.flatMap { Int64($0) }
                        let size = allocatedSize64 ?? fileSize64 ?? 0
                        return FileNode(url: url, name: url.lastPathComponent, isDirectory: rv.isDirectory ?? false, isPackage: rv.isPackage ?? false, fileExtension: url.pathExtension, uti: rv.typeIdentifier, sizeBytes: size, creationDate: nil, modificationDate: nil, accessDate: nil, children: [])
                    }
                }
                previewCache[node.url.path] = children
                return children
            } catch {
                return nil
            }
        }
        return nil
    }
}
