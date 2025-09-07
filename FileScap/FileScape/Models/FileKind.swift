import Foundation
import AppKit

enum FileKind: String, CaseIterable, Hashable {
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

    var displayName: String {
        switch self {
        case .video: return "Video"
        case .image: return "Image"
        case .audio: return "Audio"
        case .app: return "App"
        case .document: return "Doc"
        case .code: return "Code"
        case .archive: return "Archive"
        case .other: return "Other"
        }
    }

    var color: NSColor {
        switch self {
        case .video:    return NSColor.systemBlue
        case .image:    return NSColor.systemGreen
        case .audio:    return NSColor.systemTeal
        case .app:      return NSColor.systemRed
        case .document: return NSColor.systemYellow
        case .code:     return NSColor.systemPurple
        case .archive:  return NSColor.brown
        case .other:    return NSColor.systemGray
        }
    }
}

