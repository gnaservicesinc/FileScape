import Foundation

struct FileNode: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let fileExtension: String?
    let uti: String?
    let sizeBytes: Int64
    let creationDate: Date?
    let modificationDate: Date?
    let accessDate: Date?
    var children: [FileNode]

    init(id: UUID = UUID(),
         url: URL,
         name: String,
         isDirectory: Bool,
         isPackage: Bool,
         fileExtension: String?,
         uti: String?,
         sizeBytes: Int64,
         creationDate: Date?,
         modificationDate: Date?,
         accessDate: Date?,
         children: [FileNode] = []) {
        self.id = id
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.fileExtension = fileExtension?.lowercased()
        self.uti = uti
        self.sizeBytes = sizeBytes
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.accessDate = accessDate
        self.children = children
    }
}

extension FileNode {
    var displayName: String { name }
    var path: String { url.path }
    var isFile: Bool { !isDirectory || isPackage }
}

