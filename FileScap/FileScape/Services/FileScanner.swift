import Foundation

enum FileScannerError: Error {
    case invalidRoot
}

final class FileScanner {
    struct Options {
        var includeHidden: Bool = false
        var followSymlinks: Bool = false
        var maxDepth: Int = 3
        var packageAsFiles: Bool = true
        var skipPaths: Set<String> = []
        var fileCountLimit: Int = 500_000
    }

    static func scan(root url: URL, options: Options = Options()) throws -> FileNode {
        guard FileManager.default.fileExists(atPath: url.path) else { throw FileScannerError.invalidRoot }
        var visited: Set<String> = []
        var remainingCount = options.fileCountLimit
        let node = try buildNode(url: url, depth: 0, options: options, visited: &visited, remainingCount: &remainingCount)
        return node
    }

    private static func buildNode(url: URL,
                                  depth: Int,
                                  options: Options,
                                  visited: inout Set<String>,
                                  remainingCount: inout Int) throws -> FileNode {
        if remainingCount <= 0 { throw NSError(domain: "FileScanner", code: 1) }
        remainingCount -= 1

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .typeIdentifierKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .creationDateKey,
            .contentAccessDateKey,
            .contentModificationDateKey,
            .isHiddenKey
        ]

        let rv = try url.resourceValues(forKeys: keys)
        let name = url.lastPathComponent

        if let isHidden = rv.isHidden, isHidden && options.includeHidden == false, depth > 0 {
            // Skip hidden items except the root
            return FileNode(url: url,
                            name: name,
                            isDirectory: rv.isDirectory ?? false,
                            isPackage: rv.isPackage ?? false,
                            fileExtension: url.pathExtension,
                            uti: rv.typeIdentifier,
                            sizeBytes: 0,
                            creationDate: rv.creationDate,
                            modificationDate: rv.contentModificationDate,
                            accessDate: rv.contentAccessDate,
                            children: [])
        }

        // Avoid cycles via resolved path when not following symlinks
        let resolvedPath = (try? url.resolvingSymlinksInPath().path) ?? url.path
        if !options.followSymlinks {
            if visited.contains(resolvedPath) { return emptyNode(url: url, name: name, rv: rv) }
            visited.insert(resolvedPath)
        }

        let isDir = rv.isDirectory ?? false
        let isPkg = rv.isPackage ?? false
        let treatAsFile = (!isDir) || (isPkg && options.packageAsFiles)

        if treatAsFile {
            // Prefer allocated size if available; fall back to logical file size.
            let allocatedSize64: Int64? = (rv.totalFileAllocatedSize as NSNumber?)?.int64Value
            let fileSize64: Int64? = rv.fileSize.flatMap { Int64($0) }
            let size: Int64 = allocatedSize64 ?? fileSize64 ?? 0

            return FileNode(url: url,
                            name: name,
                            isDirectory: isDir,
                            isPackage: isPkg,
                            fileExtension: url.pathExtension,
                            uti: rv.typeIdentifier,
                            sizeBytes: size,
                            creationDate: rv.creationDate,
                            modificationDate: rv.contentModificationDate,
                            accessDate: rv.contentAccessDate,
                            children: [])
        }

        // Directory: enumerate children unless depth exceeded
        var childNodes: [FileNode] = []
        var total: Int64 = 0

        if depth < options.maxDepth {
            let fm = FileManager.default
            let opts: FileManager.DirectoryEnumerationOptions = options.includeHidden ? [] : [.skipsHiddenFiles]
            if let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: opts) {
                for childURL in items {
                    if options.skipPaths.contains(childURL.path) { continue }
                    do {
                        let child = try buildNode(url: childURL, depth: depth + 1, options: options, visited: &visited, remainingCount: &remainingCount)
                        childNodes.append(child)
                        total &+= child.sizeBytes
                    } catch {
                        // Skip problems and continue
                        continue
                    }
                }
            }
        }

        return FileNode(url: url,
                        name: name,
                        isDirectory: isDir,
                        isPackage: isPkg,
                        fileExtension: url.pathExtension,
                        uti: rv.typeIdentifier,
                        sizeBytes: total,
                        creationDate: rv.creationDate,
                        modificationDate: rv.contentModificationDate,
                        accessDate: rv.contentAccessDate,
                        children: childNodes)
    }

    private static func emptyNode(url: URL, name: String, rv: URLResourceValues) -> FileNode {
        FileNode(url: url,
                 name: name,
                 isDirectory: rv.isDirectory ?? false,
                 isPackage: rv.isPackage ?? false,
                 fileExtension: url.pathExtension,
                 uti: rv.typeIdentifier,
                 sizeBytes: 0,
                 creationDate: rv.creationDate,
                 modificationDate: rv.contentModificationDate,
                 accessDate: rv.contentAccessDate,
                 children: [])
    }
}
