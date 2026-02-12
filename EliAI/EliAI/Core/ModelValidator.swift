import Foundation

enum ModelValidationError: LocalizedError, Equatable {
    case fileMissing
    case notGGUFExtension
    case fileTooSmall(actualBytes: Int64, minimumBytes: Int64)
    case invalidMagic

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            return "Model file does not exist."
        case .notGGUFExtension:
            return "Selected file is not a .gguf model."
        case let .fileTooSmall(actualBytes, minimumBytes):
            return "Model is too small (\(actualBytes) bytes). Minimum expected size is \(minimumBytes) bytes."
        case .invalidMagic:
            return "File is not a valid GGUF model (invalid magic bytes)."
        }
    }
}

struct ModelValidationReport: Equatable {
    let url: URL
    let fileSizeBytes: Int64
    let profile: ModelProfile
    let metadataHints: Set<String>
    let warnings: [String]
}

enum ModelValidator {
    static let defaultMinimumBytes: Int64 = 8 * 1024 * 1024
    private static let ggufMagic = Data([0x47, 0x47, 0x55, 0x46])

    static func validateModel(
        at url: URL,
        minimumBytes: Int64 = defaultMinimumBytes
    ) throws -> ModelValidationReport {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ModelValidationError.fileMissing
        }

        guard url.pathExtension.lowercased() == "gguf" else {
            throw ModelValidationError.notGGUFExtension
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size >= minimumBytes else {
            throw ModelValidationError.fileTooSmall(actualBytes: size, minimumBytes: minimumBytes)
        }

        let header = try readPrefix(of: url, bytes: 4)
        guard header == ggufMagic else {
            throw ModelValidationError.invalidMagic
        }

        let metadataHints = detectMetadataHints(url: url, fileSize: size)
        let profile = ModelProfile.fromHints(fileName: url.lastPathComponent, metadataHints: metadataHints)

        var warnings: [String] = []
        if !metadataHints.contains("chat_template") {
            warnings.append("Model metadata did not expose tokenizer chat-template hints; falling back to profile prompt formatter.")
        }

        return ModelValidationReport(
            url: url,
            fileSizeBytes: size,
            profile: profile,
            metadataHints: metadataHints,
            warnings: warnings
        )
    }

    private static func readPrefix(of url: URL, bytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: bytes) ?? Data()
    }

    private static func detectMetadataHints(url: URL, fileSize: Int64) -> Set<String> {
        let window = 2 * 1024 * 1024
        let prefix = (try? readChunk(url: url, offset: 0, length: window)) ?? Data()
        let suffixOffset = max(0, Int(fileSize) - window)
        let suffix = (try? readChunk(url: url, offset: UInt64(suffixOffset), length: window)) ?? Data()
        let merged = prefix + suffix
        guard !merged.isEmpty else { return [] }

        let text = String(decoding: merged, as: UTF8.self).lowercased()
        var hints = Set<String>()

        if text.contains("qwen") {
            hints.insert("qwen")
        }
        if text.contains("lfm") || text.contains("liquid") {
            hints.insert("lfm")
        }
        if text.contains("tokenizer.chat_template") || text.contains("<|im_start|>") || text.contains("<|start_header_id|>") {
            hints.insert("chat_template")
        }
        if text.contains("general.architecture") {
            hints.insert("architecture")
        }

        return hints
    }

    private static func readChunk(url: URL, offset: UInt64, length: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: length) ?? Data()
    }
}
