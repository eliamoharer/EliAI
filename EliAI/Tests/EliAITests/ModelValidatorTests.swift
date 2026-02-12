import XCTest
@testable import EliAI

final class ModelValidatorTests: XCTestCase {
    func testRejectsNonGGUFExtension() throws {
        let url = temporaryURL(fileName: "not_model.txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try ModelValidator.validateModel(at: url, minimumBytes: 1)) { error in
            XCTAssertEqual((error as? ModelValidationError), .notGGUFExtension)
        }
    }

    func testRejectsInvalidMagic() throws {
        let url = temporaryURL(fileName: "bad.gguf")
        try Data([0x00, 0x00, 0x00, 0x00, 0x01]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try ModelValidator.validateModel(at: url, minimumBytes: 1)) { error in
            XCTAssertEqual((error as? ModelValidationError), .invalidMagic)
        }
    }

    func testPreflightModelSmoke() throws {
        let url = temporaryURL(fileName: "Qwen3-1.7B-Q4_K_M.gguf")
        let payload = Data([0x47, 0x47, 0x55, 0x46]) + Data(repeating: 0x20, count: 256) + Data("tokenizer.chat_template qwen".utf8)
        try payload.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = try ModelValidator.validateModel(at: url, minimumBytes: 64)
        XCTAssertEqual(report.profile, .qwen3)
        XCTAssertTrue(report.metadataHints.contains("chat_template"))
    }

    func testDetectsLFMProfileFromFileName() throws {
        let url = temporaryURL(fileName: "LFM2.5-7B-Q4_K_M.gguf")
        let payload = Data([0x47, 0x47, 0x55, 0x46]) + Data(repeating: 0x00, count: 128)
        try payload.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = try ModelValidator.validateModel(at: url, minimumBytes: 64)
        XCTAssertEqual(report.profile, .lfm25)
    }

    private func temporaryURL(fileName: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + fileName)
    }
}
