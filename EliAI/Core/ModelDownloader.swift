import Foundation

// MARK: - Model Downloader
// Downloads GGUF models from HuggingFace with progress tracking

@Observable
class ModelDownloader: NSObject {
    var isDownloading = false
    var progress: Double = 0
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var error: String?
    var currentModelName: String?

    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var destinationURL: URL?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600 // 1 hour for large models
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Download

    func downloadModel(_ model: ModelInfo, to directory: URL) async throws -> URL {
        guard !isDownloading else {
            throw DownloadError.alreadyDownloading
        }

        let destURL = directory.appendingPathComponent(model.fileName)

        // Check if already downloaded
        if FileManager.default.fileExists(atPath: destURL.path) {
            return destURL
        }

        guard let url = URL(string: model.downloadURL) else {
            throw DownloadError.invalidURL
        }

        await MainActor.run {
            self.isDownloading = true
            self.progress = 0
            self.downloadedBytes = 0
            self.totalBytes = model.sizeBytes
            self.error = nil
            self.currentModelName = model.name
        }

        self.destinationURL = destURL

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.downloadTask = session?.downloadTask(with: url)
            self.downloadTask?.resume()
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        progress = 0
        continuation?.resume(throwing: DownloadError.cancelled)
        continuation = nil
    }

    var formattedProgress: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        let downloaded = formatter.string(fromByteCount: downloadedBytes)
        let total = formatter.string(fromByteCount: totalBytes)
        return "\(downloaded) / \(total)"
    }
}

// MARK: - URLSession Delegate

extension ModelDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destURL = destinationURL else {
            continuation?.resume(throwing: DownloadError.noDestination)
            continuation = nil
            return
        }

        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }

            try FileManager.default.moveItem(at: location, to: destURL)

            DispatchQueue.main.async {
                self.isDownloading = false
                self.progress = 1.0
            }

            continuation?.resume(returning: destURL)
            continuation = nil
        } catch {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.error = error.localizedDescription
            }
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        DispatchQueue.main.async {
            self.downloadedBytes = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                self.totalBytes = totalBytesExpectedToWrite
                self.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.error = error.localizedDescription
            }
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

// MARK: - Errors

enum DownloadError: LocalizedError {
    case alreadyDownloading
    case invalidURL
    case noDestination
    case cancelled
    case fileSizeMismatch

    var errorDescription: String? {
        switch self {
        case .alreadyDownloading: return "A download is already in progress"
        case .invalidURL: return "Invalid download URL"
        case .noDestination: return "No destination path set"
        case .cancelled: return "Download was cancelled"
        case .fileSizeMismatch: return "Downloaded file size does not match expected size"
        }
    }
}
