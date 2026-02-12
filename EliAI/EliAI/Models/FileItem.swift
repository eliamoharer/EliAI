import Foundation

struct FileItem: Identifiable, Hashable {
    var id: String { path.path }
    let name: String
    let isDirectory: Bool
    var children: [FileItem]?
    let path: URL
}
