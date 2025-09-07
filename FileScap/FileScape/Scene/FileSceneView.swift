import SwiftUI
import SceneKit
import AppKit

struct FileSceneView: NSViewRepresentable {
    let scene: SCNScene
    var onSelectPath: (String) -> Void = { _ in }

    func makeNSView(context: Context) -> SCNView {
        let v = ClickableSCNView()
        v.scene = scene
        v.backgroundColor = NSColor.black
        v.allowsCameraControl = true
        v.delegateSelect = { path in
            onSelectPath(path)
        }
        return v
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.scene = scene
    }

    final class ClickableSCNView: SCNView {
        var delegateSelect: ((String) -> Void)?

        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            let results = hitTest(p, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])
            if let first = results.first, let name = first.node.name {
                delegateSelect?(name)
            }
            super.mouseDown(with: event)
        }
    }
}

