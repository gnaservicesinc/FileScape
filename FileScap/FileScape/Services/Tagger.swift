import Foundation
import AppKit
import UniformTypeIdentifiers

struct TagResult {
    let style: TagStyle
}

final class Tagger {
    static let shared = Tagger()
    private let registry = TagRegistry.shared
    private var magicBudget: Int = 200 // per batch

    func beginBatch() { magicBudget = 200 }

    func tag(for node: FileNode) -> TagResult {
        let url = node.url
        let isDirectory = node.isDirectory
        let isPackage = node.isPackage
        let uti = node.uti
        let fileExtension = node.fileExtension
        let approxSize = node.sizeBytes

        if isDirectory && !isPackage {
            return TagResult(style: registry.styleFor(tag: "folder", family: "folder"))
        }
        if isPackage {
            return TagResult(style: registry.styleFor(tag: "app", family: "app"))
        }
        // Extension/UTI first (fast)
        if let fam = registry.familyForExt(fileExtension) {
            let tag = registry.normalizedExt(fileExtension) ?? (fileExtension ?? "other")
            return TagResult(style: registry.styleFor(tag: tag, family: fam))
        }
        if let uti, let ut = UTType(uti) {
            if ut.conforms(to: .image) { return TagResult(style: registry.styleFor(tag: uti, family: "image")) }
            if ut.conforms(to: .audiovisualContent) { return TagResult(style: registry.styleFor(tag: uti, family: "video")) }
            if ut.conforms(to: .archive) { return TagResult(style: registry.styleFor(tag: uti, family: "archive")) }
            if ut.conforms(to: .text) { return TagResult(style: registry.styleFor(tag: uti, family: "text")) }
            if ut.conforms(to: .sourceCode) { return TagResult(style: registry.styleFor(tag: uti, family: "code")) }
        }
        // Try magic (budgeted, small files only)
        if magicBudget > 0, approxSize > 0, approxSize <= 5_000_000, let magic = magicFamily(url: url) {
            magicBudget -= 1
            return TagResult(style: registry.styleFor(tag: magic.tag, family: magic.family))
        }
        // Heuristic content sniffing of text/code
        if magicBudget > 0, approxSize > 0, approxSize <= 2_000_000, let sniff = sniffTextCode(url: url) {
            magicBudget -= 1
            return TagResult(style: registry.styleFor(tag: sniff.tag, family: sniff.family))
        }
        return TagResult(style: registry.styleFor(tag: "other", family: "other"))
    }

    // MARK: Magic numbers
    private func magicFamily(url: URL) -> (tag: String, family: String)? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let data = fh.readData(ofLength: 16)
        if data.count >= 8 {
            let bytes = [UInt8](data.prefix(16))
            // PNG
            let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            if bytes.starts(with: png) { return ("png", "image") }
            // JPEG
            if bytes[0] == 0xFF && bytes[1] == 0xD8 { return ("jpeg", "image") }
            // GIF
            if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 { return ("gif", "image") }
            // PDF
            if let s = String(data: data.prefix(5), encoding: .ascii), s == "%PDF-" { return ("pdf", "document") }
            // ZIP/JAR/AAB/IPA/APK/OOXML etc.
            if bytes[0] == 0x50 && bytes[1] == 0x4B { return ("zip", "archive") }
            // 7z
            let s7: [UInt8] = [0x37,0x7A,0xBC,0xAF,0x27,0x1C]
            if bytes.starts(with: s7) { return ("7z", "archive") }
            // RAR
            let rar: [UInt8] = [0x52,0x61,0x72,0x21,0x1A,0x07]
            if bytes.starts(with: rar) { return ("rar", "archive") }
            // GZ
            if bytes[0] == 0x1F && bytes[1] == 0x8B { return ("gz", "archive") }
            // Mach-O (exec, dylib): check first 4 bytes
            if data.count >= 4 {
                let v = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
                let machoMagic: [UInt32] = [0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE]
                if machoMagic.contains(v) { return ("mach-o", "binary") }
            }
        }
        return nil
    }

    // MARK: Sniff text vs code and flavors
    private func sniffTextCode(url: URL) -> (tag: String, family: String)? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let data = fh.readData(ofLength: 4096)
        guard !data.isEmpty else { return nil }
        // BOM
        if data.starts(with: [0xEF,0xBB,0xBF]) { return ("utf8-text", "text") }
        if data.starts(with: [0xFF,0xFE]) { return ("utf16le-text", "text") }
        if data.starts(with: [0xFE,0xFF]) { return ("utf16be-text", "text") }
        // ASCII ratio
        let sample = data
        let printable = sample.filter { b in
            (0x09...0x0D).contains(b) || (0x20...0x7E).contains(b)
        }
        let ratio = Double(printable.count) / Double(sample.count)
        if ratio > 0.95 { return ("text", "text") }
        return nil
    }
}
