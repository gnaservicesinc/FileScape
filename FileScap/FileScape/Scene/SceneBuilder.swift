import Foundation
import SceneKit
import AppKit

enum FileKind {
    case video, image, audio, app, document, code, archive, other

    static func from(ext: String?, uti: String?) -> FileKind {
        let e = (ext ?? "").lowercased()
        let videos = ["mp4","mov","m4v","avi","mkv","wmv","flv","webm","hevc"]
        let images = ["jpg","jpeg","png","gif","tiff","tif","bmp","heic","webp","raw"]
        let audio  = ["mp3","wav","aac","flac","m4a","ogg","aif","aiff"]
        let apps   = ["app","pkg","dmg"]
        let docs   = ["pdf","txt","md","rtf","doc","docx","ppt","pptx","xls","xlsx","pages","numbers","key","epub"]
        let code   = ["swift","c","cpp","h","hpp","m","mm","py","js","ts","java","kt","rb","go","rs","sh","yaml","yml","json","xml","sql"]
        let arch   = ["zip","tar","gz","tgz","7z","rar","xz","bz2"]

        if videos.contains(e) { return .video }
        if images.contains(e) { return .image }
        if audio.contains(e)  { return .audio }
        if apps.contains(e)   { return .app }
        if docs.contains(e)   { return .document }
        if code.contains(e)   { return .code }
        if arch.contains(e)   { return .archive }
        if let uti, uti.contains("application") { return .app }
        return .other
    }
}

final class SceneBuilder {
    struct Config {
        var baseScale: CGFloat = 1.0
        var minBlock: CGFloat = 0.2
        var maxBlock: CGFloat = 5.0
        var spacing: CGFloat = 0.6
        var constantHeight: CGFloat = 0.4
        var useAgeForHeight: Bool = false
        var ageMaxDays: Double = 365.0
    }

    private let config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    func makeScene(for root: FileNode) -> SCNScene {
        let scene = SCNScene()

        // Lighting
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 600
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 900
        let sunNode = SCNNode()
        sunNode.eulerAngles = SCNVector3(-Float.pi/4, Float.pi/4, 0)
        sunNode.light = sun
        scene.rootNode.addChildNode(sunNode)

        // Ground plane
        let ground = SCNFloor()
        ground.reflectivity = 0
        let groundNode = SCNNode(geometry: ground)
        groundNode.geometry?.firstMaterial = Self.makeMaterial(color: NSColor(calibratedWhite: 0.15, alpha: 1))
        scene.rootNode.addChildNode(groundNode)

        // Build blocks for first-level children
        let children = root.children
        if !children.isEmpty {
            let container = SCNNode()
            layout(children: children, in: container)
            scene.rootNode.addChildNode(container)
        }

        // Camera
        let cam = SCNCamera()
        cam.zNear = 0.01
        cam.zFar = 10_000
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 8, 16)
        camNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camNode)

        return scene
    }

    private func layout(children: [FileNode], in parent: SCNNode) {
        let count = children.count
        guard count > 0 else { return }

        let maxBytes = max(1, children.map { $0.sizeBytes }.max() ?? 1)
        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))

        let spacing = config.spacing + config.maxBlock
        let width = CGFloat(cols - 1) * spacing
        let depth = CGFloat(rows - 1) * spacing

        for (idx, node) in children.enumerated() {
            let col = idx % cols
            let row = idx / cols

            let rel = CGFloat(log(Double(node.sizeBytes + 1)) / log(Double(maxBytes + 1)))
            let side = max(config.minBlock, rel * config.maxBlock)
            let height: CGFloat
            if config.useAgeForHeight, let mod = node.modificationDate {
                let days = -min(0, mod.timeIntervalSinceNow) / 86400.0
                let n = min(1.0, days / config.ageMaxDays)
                height = max(0.1, CGFloat((1.0 - n)) * (config.maxBlock * 0.8))
            } else {
                height = config.constantHeight + rel * (config.maxBlock * 0.4)
            }

            let box = SCNBox(width: side, height: height, length: side, chamferRadius: 0.05)
            box.materials = [Self.material(for: node)]

            let n = SCNNode(geometry: box)
            n.name = node.url.path
            let x = CGFloat(col) * spacing - width/2
            let z = CGFloat(row) * spacing - depth/2
            n.position = SCNVector3(x, height/2, z)
            parent.addChildNode(n)
        }
    }

    private static func material(for node: FileNode) -> SCNMaterial {
        let kind = FileKind.from(ext: node.fileExtension, uti: node.uti)
        let color: NSColor
        switch kind {
        case .video:    color = NSColor.systemBlue.withAlphaComponent(0.9)
        case .image:    color = NSColor.systemGreen.withAlphaComponent(0.9)
        case .audio:    color = NSColor.systemTeal.withAlphaComponent(0.9)
        case .app:      color = NSColor.systemRed.withAlphaComponent(0.95)
        case .document: color = NSColor.systemYellow.withAlphaComponent(0.95)
        case .code:     color = NSColor.systemPurple.withAlphaComponent(0.95)
        case .archive:  color = NSColor.brown.withAlphaComponent(0.95)
        case .other:    color = NSColor.systemGray.withAlphaComponent(0.9)
        }
        return makeMaterial(color: color)
    }

    private static func makeMaterial(color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .physicallyBased
        m.metalness.contents = 0.1
        m.roughness.contents = 0.6
        return m
    }
}
