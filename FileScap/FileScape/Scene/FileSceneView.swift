import SwiftUI
import SceneKit
import AppKit

struct FileSceneView: NSViewRepresentable {
    let scene: SCNScene
    var focusPath: String? = nil
    var transitionHint: TransitionHint? = nil
    var onSelectPath: (String) -> Void = { _ in }
    var onActivatePath: (String) -> Void = { _ in }
    var enableFlyControls: Bool = true
    var onBack: () -> Void = {}
    var zoomModifier: NSEvent.ModifierFlags = .control

    enum TransitionHint { case enter, exit }

    func makeNSView(context: Context) -> SCNView {
        let v = ClickableSCNView()
        v.scene = scene
        v.backgroundColor = NSColor.black
        v.allowsCameraControl = true
        v.delegateSelect = { path in
            onSelectPath(path)
        }
        v.delegateActivate = { path in
            onActivatePath(path)
        }
        if enableFlyControls {
            v.setupFly()
        }
        v.onBack = onBack
        v.zoomModifier = zoomModifier
        return v
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        // Preserve camera across scene swaps
        let prevTransform = nsView.pointOfView?.transform
        let sceneChanged = (nsView.scene !== scene)
        nsView.scene = scene
        if let prev = prevTransform {
            let camNode: SCNNode
            if let existing = scene.rootNode.childNodes.first(where: { $0.camera != nil }) {
                camNode = existing
            } else {
                camNode = SCNNode(); camNode.camera = SCNCamera(); scene.rootNode.addChildNode(camNode)
            }
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0
            camNode.transform = prev
            SCNTransaction.commit()
            nsView.pointOfView = camNode
        }
        if sceneChanged, let hint = transitionHint { animateTransition(hint: hint, view: nsView) }
        if context.coordinator.lastFocus != focusPath {
            context.coordinator.lastFocus = focusPath
            if let focusPath { focusCamera(onPath: focusPath, view: nsView) }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastFocus: String? = nil
    }

    final class ClickableSCNView: SCNView {
        var delegateSelect: ((String) -> Void)?
        var delegateActivate: ((String) -> Void)?
        var onBack: () -> Void = {}
        var zoomModifier: NSEvent.ModifierFlags = .control
        private var flyEnabled: Bool = false
        private var flySpeed: Float = 0.6
        private var lastMouseY: CGFloat? = nil
        private var zoomVelocity: Float = 0
        private var zoomTimer: Timer? = nil
        private var moveVelocity: SIMD3<Float> = .zero
        private var moveTimer: Timer? = nil
        private var pressed: Set<Character> = []
        private var hovered: SCNNode? = nil
        private var lastMousePoint: NSPoint? = nil

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }

        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            let results = hitTest(p, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])
            if let first = results.first, let name = first.node.name {
                if event.clickCount >= 2 {
                    delegateActivate?(name)
                } else {
                    delegateSelect?(name)
                }
                first.node.runAction(.sequence([.scale(to: 1.1, duration: 0.08), .scale(to: 1.0, duration: 0.16)]))
            }
            super.mouseDown(with: event)
        }

        override func rightMouseDown(with event: NSEvent) {
            if event.clickCount >= 2 { onBack() }
            else { super.rightMouseDown(with: event) }
        }

        override var acceptsFirstResponder: Bool { true }
        func setupFly() {
            flyEnabled = true
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard flyEnabled else { return }
            let chars = event.charactersIgnoringModifiers ?? ""
            var startTimer = false
            let tapBoost: Float = 0.25
            for c in chars {
                let ch = Character(c.lowercased())
                if ch == "f" { allowsCameraControl.toggle(); continue }
                if pressed.insert(ch).inserted {
                    // Edge: apply a tap boost in that direction
                    var boost = SIMD3<Float>(0,0,0)
                    switch ch {
                    case "w": boost.z += tapBoost
                    case "s": boost.z -= tapBoost
                    case "a": boost.x -= tapBoost
                    case "d": boost.x += tapBoost
                    case "q": boost.y -= tapBoost
                    case "e": boost.y += tapBoost
                    default: break
                    }
                    moveVelocity += boost
                }
                startTimer = true
            }
            if startTimer { startMoveTimer() }
        }

        override func keyUp(with event: NSEvent) {
            guard flyEnabled else { return }
            let chars = event.charactersIgnoringModifiers ?? ""
            for c in chars {
                let ch = Character(c.lowercased())
                _ = pressed.remove(ch)
            }
        }

        private func startMoveTimer() {
            guard moveTimer == nil else { return }
            moveTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] t in
                guard let self, let camNode = self.pointOfView else { t.invalidate(); self?.moveTimer = nil; return }
                let dt: Float = 1.0/60.0
                var accel = SIMD3<Float>(0,0,0)
                let a: Float = 0.8 * (self.pressed.contains("f") ? 2.0 : 1.0)
                if self.pressed.contains("w") { accel.z += a }
                if self.pressed.contains("s") { accel.z -= a }
                if self.pressed.contains("a") { accel.x -= a }
                if self.pressed.contains("d") { accel.x += a }
                if self.pressed.contains("q") { accel.y -= a }
                if self.pressed.contains("e") { accel.y += a }
                // accelerate toward desired direction; decay to coast
                self.moveVelocity += accel * dt
                self.moveVelocity *= 0.92 // friction

                // Mouse thrust: small continuous acceleration from mouse movement
                if let last = self.lastMousePoint, let win = self.window {
                    let loc = win.mouseLocationOutsideOfEventStream
                    let dx = Float(loc.x - last.x), dy = Float(loc.y - last.y)
                    self.moveVelocity += SIMD3<Float>(dx * 0.0005, 0, -dy * 0.0005)
                }

                // Apply motion in camera-local basis
                let tform = camNode.presentation.transform
                let right = SIMD3<Float>(Float(tform.m11), Float(tform.m12), Float(tform.m13))
                let up    = SIMD3<Float>(Float(tform.m21), Float(tform.m22), Float(tform.m23))
                let fwd   = SIMD3<Float>(-Float(tform.m31), -Float(tform.m32), -Float(tform.m33))
                let worldDelta = right * self.moveVelocity.x + up * self.moveVelocity.y + fwd * self.moveVelocity.z
                var pos = SIMD3<Float>(camNode.position)
                pos += worldDelta
                SCNTransaction.begin(); SCNTransaction.animationDuration = 0.0
                camNode.position = SCNVector3(pos)
                SCNTransaction.commit()

                // Node wobble near camera when moving fast
                self.wobbleNearCamera(speed: length(self.moveVelocity))

                if self.pressed.isEmpty && length(self.moveVelocity) < 0.005 { t.invalidate(); self.moveTimer = nil }
            }
        }

        override func mouseMoved(with event: NSEvent) {
            lastMousePoint = event.locationInWindow
            handleZoomDrag(event)
            // Hover wobble
            let p = convert(event.locationInWindow, from: nil)
            let results = hitTest(p, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])
            let node = results.first?.node
            if node !== hovered {
                if let prev = hovered { unhighlight(node: prev); prev.runAction(.scale(to: 1.0, duration: 0.15)) }
                if let n = node { highlight(node: n, level: .hover); n.runAction(.sequence([.scale(to: 1.08, duration: 0.08), .scale(to: 1.0, duration: 0.15)])) }
                hovered = node
            }
            super.mouseMoved(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            handleZoomDrag(event)
            super.mouseDragged(with: event)
        }

        private func handleZoomDrag(_ event: NSEvent) {
            guard event.modifierFlags.contains(zoomModifier), let camNode = pointOfView else { lastMouseY = nil; return }
            let y = event.locationInWindow.y
            if let last = lastMouseY {
                let dy = Float(y - last)
                // Update instantaneous velocity; a timer applies easing/deceleration
                zoomVelocity += dy * 0.04
                startZoomCoast()
            }
            lastMouseY = y
        }

        private func startZoomCoast() {
            guard zoomTimer == nil else { return }
            zoomTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] t in
                guard let self, let camNode = self.pointOfView else { t.invalidate(); self?.zoomTimer = nil; return }
                // Apply velocity along camera forward axis
                let tr = camNode.presentation.transform
                let forward = SIMD3<Float>(-Float(tr.m31), -Float(tr.m32), -Float(tr.m33))
                var pos = SIMD3<Float>(camNode.position)
                pos += forward * (self.zoomVelocity * 0.5 * (1.0/60.0) * 60.0) // scale for feel
                SCNTransaction.begin(); SCNTransaction.animationDuration = 0.0
                camNode.position = SCNVector3(pos)
                SCNTransaction.commit()
                // Decelerate (ease out)
                self.zoomVelocity *= 0.88
                // Wobble near nodes proportional to speed
                self.wobbleNearCamera(speed: abs(self.zoomVelocity) * 0.02)
                if abs(self.zoomVelocity) < 0.01 { t.invalidate(); self.zoomTimer = nil; self.zoomVelocity = 0 }
            }
        }

        private func wobbleNearCamera(speed: Float) {
            guard let scene = self.scene, let cam = self.pointOfView else { return }
            let camPos = cam.presentation.position
            let maxDist: Float = 3.5
            let magBase: Float = min(0.25, max(0.05, speed))

            func applyWobble(to node: SCNNode, amount: Double) {
                let mag = CGFloat(min(0.3, max(0.05, amount)))
                node.runAction(.sequence([
                    .scale(to: 1.0 + mag, duration: 0.06),
                    .scale(to: 1.0, duration: 0.2)
                ]))
                if let m = node.geometry?.firstMaterial, let base = (m.diffuse.contents as? NSColor)?.usingColorSpace(.deviceRGB) {
                    let jitter = CGFloat(Double.random(in: -0.04...0.04))
                    let bright = base.withBrightnessScaled(by: 1.0 + jitter)
                    m.diffuse.contents = bright
                    m.emission.contents = bright.withAlphaComponent(0.25)
                }
            }

            func ripple(from node: SCNNode, magnitude: Double, radius: Float, depth: Int) {
                guard depth > 0 else { return }
                let parent = node.parent
                let siblings = parent?.childNodes ?? []
                var count = 0
                for sib in siblings {
                    guard sib !== node, sib.geometry != nil else { continue }
                    let p = sib.presentation.worldPosition
                    let pn = node.presentation.worldPosition
                    let dx = p.x - pn.x, dy = p.y - pn.y, dz = p.z - pn.z
                    let d2 = dx*dx + dy*dy + dz*dz
                    if d2 < radius*radius {
                        let prox = 1.0 - (sqrt(d2)/radius)
                        let mag = magnitude * Double(prox)
                        applyWobble(to: sib, amount: mag)
                        if mag > 0.02 && count < 12 {
                            count += 1
                            ripple(from: sib, magnitude: mag * 0.5, radius: radius * 0.75, depth: depth - 1)
                        }
                    }
                }
            }

            func visit(node: SCNNode) {
                for child in node.childNodes {
                    if child.geometry != nil {
                        let p = child.presentation.worldPosition
                        let dx = p.x - camPos.x, dy = p.y - camPos.y, dz = p.z - camPos.z
                        let d2 = dx*dx + dy*dy + dz*dz
                        if d2 < maxDist*maxDist {
                            let proximity = 1.0 - sqrt(d2)/maxDist
                            let mag = Double(magBase * proximity)
                            applyWobble(to: child, amount: mag)
                            // push then rubberband back
                            let push = 0.05 * Float(mag)
                            let dist = max(0.0001, sqrt(d2))
                            let dir = SIMD3<Float>(dx/dist, dy/dist, dz/dist)
                            child.runAction(.sequence([
                                .moveBy(x: CGFloat(dir.x * push), y: CGFloat(dir.y * push), z: CGFloat(dir.z * push), duration: 0.06),
                                .moveBy(x: CGFloat(-dir.x * push), y: CGFloat(-dir.y * push), z: CGFloat(-dir.z * push), duration: 0.25)
                            ]))
                            ripple(from: child, magnitude: mag * 0.6, radius: 1.6, depth: 2)
                        }
                    }
                    visit(node: child)
                }
            }
            visit(node: scene.rootNode)
        }

        private enum HighlightLevel { case hover, click }
        private func highlight(node: SCNNode, level: HighlightLevel) {
            guard let m = node.geometry?.firstMaterial else { return }
            let base = (m.diffuse.contents as? NSColor) ?? .white
            let factor: CGFloat = (level == .click) ? 1.14 : 1.08
            let brighter = base.withBrightnessScaled(by: factor)
            m.diffuse.contents = brighter
            m.emission.contents = brighter.withAlphaComponent(level == .click ? 0.55 : 0.35)
        }
        private func unhighlight(node: SCNNode) {
            guard let m = node.geometry?.firstMaterial, let c = m.diffuse.contents as? NSColor else { return }
            m.diffuse.contents = c.withBrightnessScaled(by: 1.0/1.08)
            m.emission.contents = NSColor.clear
        }
    }

    private func focusCamera(onPath path: String, view: SCNView) {
        guard let scene = view.scene else { return }
        guard let node = scene.rootNode.childNode(withName: path, recursively: true) else { return }
        // Ensure there's a camera
        if view.pointOfView == nil {
            let cam = SCNCamera()
            let camNode = SCNNode()
            camNode.camera = cam
            scene.rootNode.addChildNode(camNode)
            view.pointOfView = camNode
        }
        guard let camNode = view.pointOfView else { return }
        // Position camera at an offset from the node and look at it
        let pos = node.presentation.position // SCNVector3 (Float components)
        // boundingBox uses CGFloat on Apple platforms; keep calculations in CGFloat
        let bboxHeight: CGFloat = node.boundingBox.max.y - node.boundingBox.min.y
        let height: CGFloat = max(3.0, bboxHeight + 2.0)
        let offset = SCNVector3(
            pos.x + 6.0,
            pos.y + CGFloat(Float(height)),
            pos.z + 10.0
        )

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.6
        camNode.position = offset
        // Ensure look-at uses SCNVector3
        camNode.look(at: SCNVector3(pos.x, pos.y, pos.z))
        SCNTransaction.commit()
    }

    private func animateTransition(hint: TransitionHint, view: SCNView) {
        guard let scene = view.scene else { return }
        if view.pointOfView == nil {
            let cam = SCNCamera()
            let camNode = SCNNode()
            camNode.camera = cam
            scene.rootNode.addChildNode(camNode)
            view.pointOfView = camNode
        }
        guard let camNode = view.pointOfView else { return }
        // Enter: move camera in; Exit: pull camera back a bit
        let targetPos = camNode.position
        let offset: SCNVector3
        switch hint {
        case .enter:
            offset = SCNVector3(targetPos.x, targetPos.y - 2.0, targetPos.z - 4.0)
        case .exit:
            offset = SCNVector3(targetPos.x, targetPos.y + 2.0, targetPos.z + 4.0)
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        camNode.position = offset
        SCNTransaction.completionBlock = {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            camNode.position = targetPos
            SCNTransaction.commit()
        }
        SCNTransaction.commit()
    }
}

private extension SIMD3 where Scalar == Float {
    static var zero: SIMD3<Float> { SIMD3<Float>(repeating: 0) }
}

private extension SCNVector3 {
    init(_ v: SIMD3<Float>) { self.init(v.x, v.y, v.z) }
}

private func length(_ v: SIMD3<Float>) -> Float {
    return sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
}

private extension NSColor {
    func withBrightnessScaled(by factor: CGFloat) -> NSColor {
        let c = self.usingColorSpace(.deviceRGB) ?? self
        let r = min(1, max(0, c.redComponent * factor))
        let g = min(1, max(0, c.greenComponent * factor))
        let b = min(1, max(0, c.blueComponent * factor))
        return NSColor(deviceRed: r, green: g, blue: b, alpha: c.alphaComponent)
    }
}
