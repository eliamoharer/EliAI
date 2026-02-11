import Foundation

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    var children: [FileItem]?
    let path: URL
}
