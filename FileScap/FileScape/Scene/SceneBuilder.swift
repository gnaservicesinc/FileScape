import Foundation
import SceneKit
import AppKit
import UniformTypeIdentifiers

final class SceneBuilder {
    struct Config {
        var baseScale: CGFloat = 1.0
        var minBlock: CGFloat = 0.2
        var maxBlock: CGFloat = 5.0
        var spacing: CGFloat = 0.6
        var constantHeight: CGFloat = 0.4
        var useAgeForHeight: Bool = false
        var ageMaxDays: Double = 365.0
        var maxItems: Int = 256
        // Visual tuning
        var minAlpha: CGFloat = 0.25    // small items more transparent
        var maxAlpha: CGFloat = 0.9     // large items more opaque
        var gapBase: CGFloat = 0.06     // base gap added around small items
        var gapRange: CGFloat = 0.22    // how much gap increases as size decreases
        var ringGap: CGFloat = 1.0      // spacing between folder rings
        var showLabels: Bool = true
        var labelMinRel: CGFloat = 0.12 // don't label extremely tiny blocks
        var labelMaxChars: Int = 24
        var previewLimit: Int = 20
        var enablePreview: Bool = true
        // Family arms
        var armSpread: CGFloat = 0.6   // angular width an arm can meander
        var armPitch: CGFloat = 0.9    // vertical rise per one turn (approx)
        var useFamilyArms: Bool = true
    }

    private var config: Config
    private let tagger = Tagger.shared

    init(config: Config = Config()) {
        self.config = config
    }

    typealias PreviewProvider = (FileNode) -> [FileNode]?

    enum AppearKind { case enter, exit }

    func makeScene(for root: FileNode,
                   selectedPath: String? = nil,
                   matchPaths: Set<String> = [],
                   childrenOverride: [FileNode]? = nil,
                   roomsMode: Bool = false,
                   previewProvider: PreviewProvider? = nil,
                   cameraTransformOverride: SCNMatrix4? = nil,
                   appear: AppearKind? = nil) -> SCNScene {
        let scene = SCNScene()
        tagger.beginBatch()

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

        // Build blocks for first-level children (or override)
        let children = childrenOverride ?? root.children
        if !children.isEmpty {
            let container = SCNNode()
            if config.useFamilyArms {
                layoutFamilyArms(children: children, in: container, selectedPath: selectedPath, matchPaths: matchPaths, previewProvider: previewProvider)
            } else {
                layoutRadial(children: children, in: container, selectedPath: selectedPath, matchPaths: matchPaths, previewProvider: previewProvider)
            }
            if let appear { applyAppearAnimation(to: container, kind: appear) }
            scene.rootNode.addChildNode(container)

            // Camera based on content bounds
            let (minV, maxV) = container.boundingBox
            let center = SCNVector3((minV.x + maxV.x)/2, 0, (minV.z + maxV.z)/2)
            let extentX = maxV.x - minV.x
            let extentZ = maxV.z - minV.z
            let radius = max(4.0, sqrt(extentX * extentX + extentZ * extentZ) * 0.6)

            let cam = SCNCamera()
            cam.zNear = 0.01
            cam.zFar = 50_000
            let camNode = SCNNode()
            camNode.camera = cam
            if let t = cameraTransformOverride {
                camNode.transform = t
            } else {
                camNode.position = SCNVector3(center.x, radius * 0.6, center.z + radius * 1.5)
                camNode.look(at: center)
            }
            scene.rootNode.addChildNode(camNode)
            return scene
        }

        // Camera fallback when empty
        let cam = SCNCamera()
        cam.zNear = 0.01
        cam.zFar = 10_000
        let camNode = SCNNode()
        camNode.camera = cam
        if let t = cameraTransformOverride {
            camNode.transform = t
        } else {
            camNode.position = SCNVector3(0, 8, 16)
            camNode.look(at: SCNVector3(0, 0, 0))
        }
        scene.rootNode.addChildNode(camNode)

        return scene
    }

    private func layout(children: [FileNode], in parent: SCNNode, selectedPath: String?, matchPaths: Set<String>, previewProvider: PreviewProvider?) {
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
            let isSelected = (node.url.path == selectedPath)
            let isMatch = matchPaths.contains(node.url.path)
            box.materials = [self.material(for: node, highlighted: isSelected || isMatch, rel: rel, config: config)]

            let n = SCNNode(geometry: box)
            n.name = node.url.path
            let x = CGFloat(col) * spacing - width/2
            let z = CGFloat(row) * spacing - depth/2
            n.position = SCNVector3(x, height/2, z)
            parent.addChildNode(n)

            if config.showLabels && rel >= config.labelMinRel {
                let labelText = labelString(for: node, maxChars: config.labelMaxChars)
                let baseColor = tagger.tag(for: node).style.color
                let label = TextLabelFactory.makeBillboard(text: labelText, fontSize: 9, baseColor: baseColor)
                label.position = SCNVector3(0, Float(height/2 + 0.1), 0)
                n.addChildNode(label)
            }

            if config.enablePreview, let previews = previewProvider?(node), !previews.isEmpty {
                addMiniPreview(children: previews, in: n, side: side, height: height)
            }
        }
    }

    private func layoutRooms(children: [FileNode], in parent: SCNNode, selectedPath: String?, matchPaths: Set<String>, previewProvider: PreviewProvider?) {
        let folders = children.filter { $0.isDirectory }
        let files = children.filter { !$0.isDirectory }

        // Create a floor platform sized relative to counts
        let gridCols = Int(ceil(sqrt(Double(max(1, files.count)))))
        let gridRows = Int(ceil(Double(max(1, files.count)) / Double(gridCols)))
        let spacing = config.spacing + config.maxBlock
        let innerWidth = CGFloat(max(1, gridCols - 1)) * spacing + config.maxBlock
        let innerDepth = CGFloat(max(1, gridRows - 1)) * spacing + config.maxBlock

        let margin: CGFloat = config.maxBlock * 1.5
        let floorWidth = innerWidth + margin * 2
        let floorDepth = innerDepth + margin * 2

        let floor = SCNBox(width: floorWidth, height: 0.1, length: floorDepth, chamferRadius: 0)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, 0.05, 0)
        floorNode.geometry?.firstMaterial = Self.makeMaterial(color: NSColor(calibratedWhite: 0.12, alpha: 1))
        parent.addChildNode(floorNode)

        // Layout files in center grid (with transparency/gaps scaling by size)
        if !files.isEmpty {
            let startX = -innerWidth/2
            let startZ = -innerDepth/2
            let maxBytes = max(1, files.map { $0.sizeBytes }.max() ?? 1)

            for (idx, node) in files.enumerated() {
                let col = idx % gridCols
                let row = idx / gridCols
                let rel = CGFloat(log(Double(node.sizeBytes + 1)) / log(Double(maxBytes + 1)))
                // smaller items get larger relative gaps and more transparency
                let side = max(config.minBlock, rel * config.maxBlock)
                let height = config.constantHeight + rel * (config.maxBlock * 0.7)
                let box = SCNBox(width: side, height: height, length: side, chamferRadius: 0.04)
                let isSelected = (node.url.path == selectedPath)
                let isMatch = matchPaths.contains(node.url.path)
                box.materials = [self.material(for: node, highlighted: isSelected || isMatch, rel: rel, config: config)]
                let n = SCNNode(geometry: box)
                let x = startX + CGFloat(col) * spacing
                let z = startZ + CGFloat(row) * spacing
                n.name = node.url.path
                n.position = SCNVector3(x, height/2 + 0.05, z)
                parent.addChildNode(n)

                if config.showLabels && rel >= config.labelMinRel {
                    let labelText = labelString(for: node, maxChars: config.labelMaxChars)
                    let baseColor = tagger.tag(for: node).style.color
                    let label = TextLabelFactory.makeBillboard(text: labelText, fontSize: 9, baseColor: baseColor)
                    label.position = SCNVector3(0, Float(height/2 + 0.1), 0)
                    n.addChildNode(label)
                }

                if config.enablePreview, let previews = previewProvider?(node), !previews.isEmpty {
                    addMiniPreview(children: previews, in: n, side: side, height: height)
                }
            }
        }

        // Layout folders along the perimeter, possibly multiple rings to avoid solid wall
        if !folders.isEmpty {
            let foldersMax = max(1, folders.map { $0.sizeBytes }.max() ?? 1)

            var rx = floorWidth/2 - margin/2 - config.maxBlock
            var rz = floorDepth/2 - margin/2 - config.maxBlock
            var index = 0
            while index < folders.count && rx > config.maxBlock && rz > config.maxBlock {
                var angle: CGFloat = 0
                // approximate circumference using average radius
                let rAvg = max(1.0, (rx + rz) / 2)
                while index < folders.count && angle < CGFloat.pi * 2 {
                    let node = folders[index]
                    let rel = CGFloat(log(Double(node.sizeBytes + 1)) / log(Double(foldersMax + 1)))
                    let side = max(config.maxBlock * 0.5, rel * config.maxBlock * 1.1)
                    let height = config.constantHeight + rel * (config.maxBlock * 1.1)
                    let gap = config.gapBase + (1 - rel) * config.gapRange
                    let step = (side + gap) / rAvg

                    let x = cos(angle) * rx
                    let z = sin(angle) * rz
                    let box = SCNBox(width: side, height: height, length: side, chamferRadius: 0.06)
                    let isSelected = (node.url.path == selectedPath)
                    let isMatch = matchPaths.contains(node.url.path)
                    box.materials = [self.material(for: node, highlighted: isSelected || isMatch, rel: rel, config: config)]
                    let n = SCNNode(geometry: box)
                    n.name = node.url.path
                    n.position = SCNVector3(Float(x), Float(height/2 + 0.05), Float(z))
                    parent.addChildNode(n)

                    if config.showLabels && rel >= config.labelMinRel {
                        let labelText = labelString(for: node, maxChars: config.labelMaxChars)
                        let baseColor = tagger.tag(for: node).style.color
                        let label = TextLabelFactory.makeBillboard(text: labelText, fontSize: 9, baseColor: baseColor)
                        label.position = SCNVector3(0, Float(height/2 + 0.1), 0)
                        n.addChildNode(label)
                    }

                    if config.enablePreview, let previews = previewProvider?(node), !previews.isEmpty {
                        addMiniPreview(children: previews, in: n, side: side, height: height)
                    }

                    angle += step
                    index += 1
                }
                rx -= config.ringGap
                rz -= config.ringGap
            }
        }
    }

    private func material(for node: FileNode, highlighted: Bool, rel: CGFloat, config: Config) -> SCNMaterial {
        var color = tagger.tag(for: node).style.color
        let alpha = max(0.05, min(1.0, config.minAlpha + rel * (config.maxAlpha - config.minAlpha)))
        color = color.withAlphaComponent(alpha)
        let m = SceneBuilder.makeMaterial(color: color)
        m.transparency = alpha
        m.blendMode = SCNBlendMode.alpha
        // Small items are rougher and less metallic; big ones shinier
        m.metalness.contents = CGFloat(0.05 + 0.25 * rel)
        m.roughness.contents = CGFloat(0.8 - 0.5 * rel)
        if highlighted {
            m.emission.contents = NSColor.white.withAlphaComponent(0.35)
        }
        return m
    }

    private func labelString(for node: FileNode, maxChars: Int) -> String {
        let size = ByteCountFormatter.string(fromByteCount: node.sizeBytes, countStyle: .file)
        var name = node.displayName
        if name.count > maxChars { name = String(name.prefix(maxChars - 1)) + "…" }
        let ext = node.fileExtension?.uppercased() ?? (node.isDirectory ? "FOLDER" : "FILE")
        return "\(name)  •  \(ext)  •  \(size)"
    }

    private func addMiniPreview(children: [FileNode], in parentNode: SCNNode, side: CGFloat, height: CGFloat) {
        // Grid of tiny boxes on top surface to hint internal composition
        let limit = min(Int(config.previewLimit), max(1, children.count))
        let sorted = Array(children.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit))
        let cols = Int(ceil(sqrt(Double(sorted.count))))
        let rows = Int(ceil(Double(sorted.count) / Double(cols)))
        let cellSide = max(0.05, (side * 0.9) / CGFloat(cols))
        let startX = -((CGFloat(cols) * cellSide) / 2) + cellSide/2
        let startZ = -((CGFloat(rows) * cellSide) / 2) + cellSide/2
        let totalMax = max(1, sorted.map { $0.sizeBytes }.max() ?? 1)

        for (idx, node) in sorted.enumerated() {
            let col = idx % cols
            let row = idx / cols
            let rel = CGFloat(log(Double(node.sizeBytes + 1)) / log(Double(totalMax + 1)))
            let h = max(0.03, rel * (height * 0.7))
            let box = SCNBox(width: cellSide * 0.9, height: h, length: cellSide * 0.9, chamferRadius: 0.01)
            box.materials = [self.material(for: node, highlighted: false, rel: rel, config: config)]
            let n = SCNNode(geometry: box)
            let x = startX + CGFloat(col) * cellSide
            let z = startZ + CGFloat(row) * cellSide
            // Place inside the top section (beneath surface) since parent may be transparent
            n.position = SCNVector3(x, height/2 - h/2 - 0.02, z)
            parentNode.addChildNode(n)
        }
    }

    private static func makeMaterial(color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .physicallyBased
        m.metalness.contents = 0.1
        m.roughness.contents = 0.6
        return m
    }

    // New radial layout that clusters big items near the center
    private func layoutRadial(children: [FileNode], in parent: SCNNode, selectedPath: String?, matchPaths: Set<String>, previewProvider: PreviewProvider?) {
        guard !children.isEmpty else { return }
        let sorted = children.sorted { $0.sizeBytes > $1.sizeBytes }
        let maxBytes = max(1, sorted.map { $0.sizeBytes }.max() ?? 1)

        var nodesPlaced: [SCNNode] = []
        func relFor(_ n: FileNode) -> CGFloat {
            CGFloat(log(Double(n.sizeBytes + 1)) / log(Double(maxBytes + 1)))
        }
        func place(_ node: FileNode, radius: CGFloat, angle: CGFloat, ringIndex: Int) {
            let rel = relFor(node)
            let side = max(config.minBlock, rel * config.maxBlock)
            let height = config.constantHeight + rel * (config.maxBlock * 0.7)
            let box = SCNBox(width: side, height: height, length: side, chamferRadius: 0.06)
            let isSelected = (node.url.path == selectedPath)
            let isMatch = matchPaths.contains(node.url.path)
            box.materials = [material(for: node, highlighted: isSelected || isMatch, rel: rel, config: config)]
            let n = SCNNode(geometry: box)
            n.name = node.url.path
            let x = radius * cos(angle)
            let z = radius * sin(angle)
            // Spiral elevation: rise with angle and ring index
            let levelSpacing: CGFloat = config.maxBlock * 0.9
            let turns = (angle / (2 * .pi)) + CGFloat(ringIndex)
            let yElev = turns * levelSpacing
            n.position = SCNVector3(Float(x), Float(height/2 + yElev), Float(z))
            parent.addChildNode(n)
            nodesPlaced.append(n)

            if config.showLabels && rel >= config.labelMinRel {
                let labelText = labelString(for: node, maxChars: config.labelMaxChars)
                let baseColor = tagger.tag(for: node).style.color
                let label = TextLabelFactory.makeBillboard(text: labelText, fontSize: 9, baseColor: baseColor)
                label.position = SCNVector3(0, Float(height/2 + 0.1), 0)
                n.addChildNode(label)
            }
            if config.enablePreview, let previews = previewProvider?(node), !previews.isEmpty {
                addMiniPreview(children: previews, in: n, side: side, height: height)
            }
        }

        // Place largest in center
        place(sorted[0], radius: 0, angle: 0, ringIndex: 0)
        var idx = 1
        var radius: CGFloat = max(config.maxBlock * 1.4, 2.2)
        var ringIndex = 1
        while idx < sorted.count {
            var angle: CGFloat = 0
            while idx < sorted.count && angle < CGFloat.pi * 2 {
                let node = sorted[idx]
                let rel = relFor(node)
                let side = max(config.minBlock, rel * config.maxBlock)
                let gap = max(0.03, config.gapBase + (1 - rel) * config.gapRange)
                let step = max(0.12, (side + gap) / max(radius, 0.5))
                place(node, radius: radius, angle: angle, ringIndex: ringIndex)
                angle += step
                idx += 1
            }
            radius += max(0.6, config.maxBlock * 0.8)
            ringIndex += 1
        }

        // Faint radial connections from center to each node for context
        addConnections(from: SCNVector3(0,0,0), to: nodesPlaced.dropFirst(), parent: parent)
    }

    private func addConnections<S: Sequence>(from origin: SCNVector3, to nodes: S, parent: SCNNode) where S.Element == SCNNode {
        var count = 0
        for n in nodes {
            if count > 256 { break }
            let tgt = n.position
            let dx = tgt.x - origin.x
            let dy = tgt.y - origin.y
            let dz = tgt.z - origin.z
            let dist = CGFloat(sqrt(dx*dx + dy*dy + dz*dz))
            guard dist > 0.01 else { continue }
            let cyl = SCNCylinder(radius: 0.02, height: dist)
            let m = SCNMaterial()
            m.diffuse.contents = NSColor.white.withAlphaComponent(0.12)
            m.lightingModel = .constant
            cyl.materials = [m]
            let node = SCNNode(geometry: cyl)
            node.position = SCNVector3((origin.x + tgt.x)/2, (origin.y + tgt.y)/2, (origin.z + tgt.z)/2)
            node.look(at: n.position)
            node.eulerAngles.x += .pi/2
            parent.addChildNode(node)
            // Pulse the line subtly
            let pulse = SCNAction.sequence([
                .fadeOpacity(to: 0.2, duration: 0.6),
                .fadeOpacity(to: 0.5, duration: 0.6)
            ])
            node.opacity = 0.35
            node.runAction(.repeatForever(pulse))
            count += 1
        }
    }

    private func applyAppearAnimation(to container: SCNNode, kind: AppearKind) {
        let dy: CGFloat = (kind == .enter) ? 0.6 : 0.2
        for child in container.childNodes {
            let original = child.position
            child.position = SCNVector3(original.x, original.y - CGFloat(Float(dy)), original.z)
            child.opacity = 0
            let move = SCNAction.moveBy(x: 0, y: dy, z: 0, duration: 0.45)
            move.timingMode = .easeOut
            let fade = SCNAction.fadeIn(duration: 0.4)
            child.runAction(.group([move, fade]))
        }
    }

    // MARK: - Family-based spiral arms layout
    private func familyFor(node: FileNode) -> String {
        tagger.tag(for: node).style.family
    }

    private func layoutFamilyArms(children: [FileNode], in parent: SCNNode, selectedPath: String?, matchPaths: Set<String>, previewProvider: PreviewProvider?) {
        guard !children.isEmpty else { return }
        // Group by family
        var groups: [String: [FileNode]] = [:]
        for n in children { groups[familyFor(node: n), default: []].append(n) }
        var families = Array(groups.keys)
        families.sort()
        let countArms = max(1, families.count)

        // Largest overall in the center
        let allSorted = children.sorted { $0.sizeBytes > $1.sizeBytes }
        let maxBytes = max(1, allSorted.first?.sizeBytes ?? 1)
        func rel(_ n: FileNode) -> CGFloat { CGFloat(log(Double(n.sizeBytes + 1)) / log(Double(maxBytes + 1))) }

        // Center hub (largest)
        if let hub = allSorted.first {
            _ = place(node: hub, radius: 0, angle: 0, turnOffset: 0, selectedPath: selectedPath, matchPaths: matchPaths, parent: parent, previewProvider: previewProvider, maxBytes: maxBytes)
            // Remove hub from its family group so it's not duplicated
            let fam = familyFor(node: hub)
            groups[fam] = groups[fam]?.filter { $0.url.path != hub.url.path }
        }

        let baseRadius: CGFloat = max(config.maxBlock * 1.6, 2.4)
        var armIndex = 0
        for fam in families {
            guard var items = groups[fam], !items.isEmpty else { armIndex += 1; continue }
            items.sort { $0.sizeBytes > $1.sizeBytes }
            let baseAngle = (2 * CGFloat.pi) * CGFloat(armIndex) / CGFloat(countArms)
            var angle = baseAngle
            var radius = baseRadius
            var turn: CGFloat = 0

            for node in items {
                // Step sizes scale with node size (bigger -> bigger step)
                let r = rel(node)
                let side = max(config.minBlock, r * config.maxBlock)
                let gap = max(0.03, config.gapBase + (1 - r) * config.gapRange)
                let radialStep = max(0.6, side + gap) // push outward by full size + gap
                let angularStep = max(0.06, (side + gap) / max(radius, 0.6)) // arc length based
                angle += min(config.armSpread, angularStep)
                radius += radialStep * 0.25 // gentle outward drift to avoid overlap
                turn += angularStep / (2 * .pi)

                _ = place(node: node, radius: radius, angle: angle, turnOffset: turn + CGFloat(armIndex) * 0.15, selectedPath: selectedPath, matchPaths: matchPaths, parent: parent, previewProvider: previewProvider, maxBytes: maxBytes)
            }

            // Connector dots along the arm
            addConnections(from: SCNVector3(0,0,0), to: parent.childNodes, parent: parent)
            armIndex += 1
        }
    }

    @discardableResult
    private func place(node: FileNode, radius: CGFloat, angle: CGFloat, turnOffset: CGFloat, selectedPath: String?, matchPaths: Set<String>, parent: SCNNode, previewProvider: PreviewProvider?, maxBytes: Int64) -> SCNNode {
        let r = CGFloat(log(Double(node.sizeBytes + 1)) / log(Double(maxBytes + 1)))
        let side = max(config.minBlock, r * config.maxBlock)
        let height = config.constantHeight + r * (config.maxBlock * 0.7)
        let box = SCNBox(width: side, height: height, length: side, chamferRadius: 0.06)
        let isSelected = (node.url.path == selectedPath)
        let isMatch = matchPaths.contains(node.url.path)
        box.materials = [material(for: node, highlighted: isSelected || isMatch, rel: r, config: config)]
        let n = SCNNode(geometry: box)
        n.name = node.url.path
        let x = radius * cos(angle)
        let z = radius * sin(angle)
        let yElev = (turnOffset) * config.armPitch * config.maxBlock
        n.position = SCNVector3(Float(x), Float(height/2 + yElev), Float(z))
        parent.addChildNode(n)

        if config.showLabels && r >= config.labelMinRel {
            let labelText = labelString(for: node, maxChars: config.labelMaxChars)
            let baseColor = tagger.tag(for: node).style.color
            let label = TextLabelFactory.makeBillboard(text: labelText, fontSize: 9, baseColor: baseColor)
            label.position = SCNVector3(0, Float(height/2 + 0.1), 0)
            n.addChildNode(label)
        }
        if config.enablePreview, let previews = previewProvider?(node), !previews.isEmpty {
            addMiniPreview(children: previews, in: n, side: side, height: height)
        }
        return n
    }
}
