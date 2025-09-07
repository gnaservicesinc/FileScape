import Foundation
import SceneKit
import AppKit

enum TextLabelFactory {
    static func makeBillboard(text: String,
                               fontSize: CGFloat = 10,
                               maxWidth: CGFloat = 220,
                               baseColor: NSColor) -> SCNNode {
        // Choose high-contrast text color and subtle translucent background
        let (fg, bg) = contrastingColors(for: baseColor)
        let padding: CGFloat = 4
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: fg
        ]
        let attr = NSAttributedString(string: text, attributes: attributes)
        let size = attr.boundingRect(with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).integral.size
        let imgSize = NSSize(width: min(maxWidth, size.width) + padding * 2, height: size.height + padding * 2)

        let image = NSImage(size: imgSize)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: imgSize)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        bg.setFill()
        path.fill()
        attr.draw(with: NSRect(x: padding, y: padding, width: imgSize.width - padding * 2, height: imgSize.height - padding * 2))
        image.unlockFocus()

        let plane = SCNPlane(width: imgSize.width / 100.0, height: imgSize.height / 100.0)
        let mat = SCNMaterial()
        mat.diffuse.contents = image
        mat.isDoubleSided = true
        mat.transparency = 0.95
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.constraints = [SCNBillboardConstraint()] // always face camera
        return node
    }

    private static func contrastingColors(for color: NSColor) -> (NSColor, NSColor) {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        // Relative luminance
        let L = 0.2126*r + 0.7152*g + 0.0722*b
        let fg: NSColor = (L < 0.5) ? .white : .black
        let bgAlpha: CGFloat = 0.35
        let bg = NSColor(calibratedWhite: (L < 0.5) ? 0.0 : 1.0, alpha: bgAlpha)
        return (fg, bg)
    }
}
