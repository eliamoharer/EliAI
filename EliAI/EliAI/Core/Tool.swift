import Foundation

protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [String] { get } // E.g. "path, content"
    func execute(arguments: [String: String]) async throws -> String
}

extension Tool {
    var signatureString: String {
        return "\(name)(\(parameters.joined(separator: ", ")))"
    }
}
