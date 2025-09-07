import Foundation
import AppKit

struct TagStyle {
    let name: String
    let family: String
    let color: NSColor
}

final class TagRegistry {
    static let shared = TagRegistry()

    // Base hues for families (0..1)
    private let familyHue: [String: CGFloat] = [
        "image": 0.55,
        "video": 0.58,
        "audio": 0.48,
        "archive": 0.08,
        "document": 0.15,
        "text": 0.72,
        "code": 0.68,
        "binary": 0.02,
        "app": 0.0,
        "folder": 0.62,
        "other": 0.0
    ]

    // Common extension aliases
    private let aliases: [String: String] = [
        "jpg": "jpeg", "jpe": "jpeg",
        "tif": "tiff",
        "yml": "yaml",
        "htm": "html",
        "mdown": "md", "markdown": "md"
    ]

    // Pre-populated tags -> families
    private let extToFamily: [String: String] = [
        // images
        "png": "image", "jpeg": "image", "gif": "image", "tiff": "image", "bmp": "image", "heic": "image", "webp": "image",
        // video
        "mp4": "video", "mov": "video", "m4v": "video", "mkv": "video", "avi": "video", "webm": "video",
        // audio
        "mp3": "audio", "wav": "audio", "aac": "audio", "flac": "audio", "m4a": "audio", "ogg": "audio",
        // archives
        "zip": "archive", "rar": "archive", "7z": "archive", "gz": "archive", "xz": "archive", "bz2": "archive", "tar": "archive",
        // documents
        "pdf": "document", "rtf": "document", "doc": "document", "docx": "document", "ppt": "document", "pptx": "document", "xls": "document", "xlsx": "document",
        // code / text
        "txt": "text", "md": "text", "log": "text", "json": "text", "xml": "text", "yaml": "text", "csv": "text",
        "c": "code", "cpp": "code", "h": "code", "hpp": "code", "m": "code", "mm": "code", "swift": "code", "py": "code", "rb": "code", "js": "code", "ts": "code", "java": "code", "kt": "code", "go": "code", "rs": "code", "php": "code", "sh": "code", "sql": "code", "html": "code", "css": "code"
    ]

    func styleFor(tag name: String, family: String) -> TagStyle {
        // Generate a unique yet related color for tag within a family
        let baseHue = familyHue[family] ?? 0.0
        var hasher = Hasher()
        hasher.combine(name)
        let hash = hasher.finalize()
        let jitter = CGFloat((abs(hash) % 100)) / 100.0 // 0..1
        let hue = fmod(baseHue + (jitter - 0.5) * 0.14 + 1.0, 1.0) // +/- ~0.07
        let sat: CGFloat = 0.65 + (jitter * 0.2)
        let bri: CGFloat = 0.8
        let color = NSColor(calibratedHue: hue, saturation: sat, brightness: bri, alpha: 1)
        return TagStyle(name: name, family: family, color: color)
    }

    func normalizedExt(_ ext: String?) -> String? {
        guard var e = ext?.lowercased(), !e.isEmpty else { return nil }
        if let alias = aliases[e] { e = alias }
        return e
    }

    func familyForExt(_ ext: String?) -> String? {
        guard let e = normalizedExt(ext) else { return nil }
        return extToFamily[e]
    }
}

