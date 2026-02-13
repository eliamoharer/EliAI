import Foundation
import Observation

struct RemoteModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let fileName: String
    let profile: ModelProfile
    let urlString: String
}

@Observable
class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    var downloadProgress: Double = 0.0
    var isDownloading = false
    var error: String?
    var localModelURL: URL?
    var log: String = "Ready to load model."
    var availableModels: [String] = []

    let remoteCatalog: [RemoteModel] = [
        RemoteModel(
            id: "qwen3-1.7b-q4km",
            displayName: "Qwen 3 1.7B (Q4_K_M)",
            fileName: "Qwen3-1.7B-Q4_K_M.gguf",
            profile: .qwen3,
            urlString: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"
        ),
        RemoteModel(
            id: "lfm2.5-1.2b-thinking-q4km",
            displayName: "LFM 2.5 1.2B Thinking (Q4_K_M)",
            fileName: "LFM2.5-1.2B-Thinking-Q4_K_M.gguf",
            profile: .lfm25,
            urlString: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Thinking-GGUF/resolve/main/LFM2.5-1.2B-Thinking-Q4_K_M.gguf"
        ),
        RemoteModel(
            id: "lfm2.5-1.2b-instruct-q4km",
            displayName: "LFM 2.5 1.2B Instruct (Q4_K_M)",
            fileName: "LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
            profile: .lfm25,
            urlString: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
        )
    ]

    var selectedRemoteModelID: String {
        get { UserDefaults.standard.string(forKey: "selectedRemoteModelID") ?? "qwen3-1.7b-q4km" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedRemoteModelID") }
    }

    var selectedRemoteModel: RemoteModel {
        remoteCatalog.first(where: { $0.id == selectedRemoteModelID }) ?? remoteCatalog[0]
    }

    var activeModelName: String {
        get { UserDefaults.standard.string(forKey: "activeModelName") ?? selectedRemoteModel.fileName }
        set {
            UserDefaults.standard.set(newValue, forKey: "activeModelName")
            checkLocalModel()
        }
    }

    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?

    override init() {
        super.init()
        checkLocalModel()
        refreshAvailableModels()
    }

    func checkLocalModel() {
        refreshAvailableModels()
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsURL.appendingPathComponent(activeModelName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            localModelURL = nil
            error = nil
            log = "Ready to load model."
            return
        }

        do {
            let report = try ModelValidator.validateModel(at: fileURL)
            localModelURL = fileURL
            downloadProgress = 1.0
            error = nil
            log = report.warnings.isEmpty
                ? "Model verified (\(report.profile.displayName))."
                : "Model verified with warnings."
            AppLogger.info("Local model verified: \(activeModelName)", category: .model)
        } catch {
            self.error = error.localizedDescription
            self.log = "Invalid model: \(error.localizedDescription)"
            localModelURL = nil
            try? FileManager.default.removeItem(at: fileURL)
            refreshAvailableModels()
            AppLogger.error("Local model failed validation: \(error.localizedDescription)", category: .model)
        }
    }

    func refreshAvailableModels() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let contents = try? FileManager.default.contentsOfDirectory(atPath: documentsURL.path)
        availableModels = (contents?.filter { $0.lowercased().hasSuffix(".gguf") } ?? []).sorted()
    }

    func deleteModel(named name: String) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsURL.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: fileURL)

        if name == activeModelName {
            localModelURL = nil
            if let fallbackURL = fallbackModelURL(excluding: name) {
                activeModelName = fallbackURL.lastPathComponent
            } else {
                activeModelName = selectedRemoteModel.fileName
            }
        }
        refreshAvailableModels()
    }

    func downloadModel() {
        guard let url = URL(string: selectedRemoteModel.urlString) else {
            error = "Remote model URL is invalid."
            log = "Download failed: invalid URL."
            return
        }

        activeModelName = selectedRemoteModel.fileName
        beginDownload(url: url)
    }

    func cancelDownload() {
        downloadTask?.cancel()
        session?.invalidateAndCancel()
        downloadTask = nil
        session = nil
        isDownloading = false
        log = "Download cancelled."
    }

    func importLocalModel(from sourceURL: URL) {
        guard sourceURL.pathExtension.lowercased() == "gguf" else {
            error = "Only .gguf files can be imported."
            log = "Import failed: unsupported file type."
            return
        }

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileName = sourceURL.lastPathComponent
        let destinationURL = documentsURL.appendingPathComponent(fileName)

        updateLog("Starting import from: \(fileName)")
        activeModelName = fileName
        isDownloading = true
        downloadProgress = 0.0
        error = nil

        Task {
            do {
                let gotAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if gotAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("gguf")

                try FileManager.default.copyItem(at: sourceURL, to: tempURL)

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                let report = try ModelValidator.validateModel(at: destinationURL)

                await MainActor.run {
                    localModelURL = destinationURL
                    downloadProgress = 1.0
                    isDownloading = false
                    error = nil
                    updateLog("Import complete: \(report.profile.displayName)")
                    refreshAvailableModels()
                    AppLogger.info("Imported model: \(fileName)", category: .model)
                }
            } catch {
                await MainActor.run {
                    self.error = "Import error: \(error.localizedDescription)"
                    self.log = "Import failed: \(error.localizedDescription)"
                    self.isDownloading = false
                    try? FileManager.default.removeItem(at: destinationURL)
                    self.localModelURL = nil
                    self.refreshAvailableModels()
                    AppLogger.error("Model import failed: \(error.localizedDescription)", category: .model)
                }
            }
        }
    }

    func fallbackModelURL(excluding excludedName: String? = nil) -> URL? {
        refreshAvailableModels()
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }

        for candidate in availableModels where candidate != excludedName {
            let url = documentsURL.appendingPathComponent(candidate)
            if (try? ModelValidator.validateModel(at: url)) != nil {
                return url
            }
        }
        return nil
    }

    private func beginDownload(url: URL) {
        isDownloading = true
        error = nil
        downloadProgress = 0.0
        log = "Starting download..."

        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session?.downloadTask(with: url)
        downloadTask = task
        task?.resume()
        AppLogger.info("Started download for \(selectedRemoteModel.displayName).", category: .model)
    }

    private func updateLog(_ message: String) {
        log = message
    }

    private func completeDownload(at temporaryURL: URL) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            DispatchQueue.main.async {
                self.error = "Filesystem error."
                self.isDownloading = false
            }
            return
        }

        let destinationURL = documentsURL.appendingPathComponent(activeModelName)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            _ = try ModelValidator.validateModel(at: destinationURL)

            DispatchQueue.main.async {
                self.localModelURL = destinationURL
                self.downloadProgress = 1.0
                self.isDownloading = false
                self.error = nil
                self.log = "Download complete! Model ready."
                self.refreshAvailableModels()
                AppLogger.info("Model downloaded and validated: \(self.activeModelName)", category: .model)
            }
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            DispatchQueue.main.async {
                self.error = "Download validation failed: \(error.localizedDescription)"
                self.log = "Downloaded file failed validation."
                self.isDownloading = false
                self.localModelURL = nil
                self.refreshAvailableModels()
                AppLogger.error("Downloaded model failed validation: \(error.localizedDescription)", category: .model)
            }
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.downloadProgress = progress
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let response = downloadTask.response as? HTTPURLResponse, response.statusCode != 200 {
            DispatchQueue.main.async {
                self.error = "Server error: HTTP \(response.statusCode)"
                self.log = "Download failed with HTTP \(response.statusCode)."
                self.isDownloading = false
                AppLogger.error("Download failed with HTTP \(response.statusCode).", category: .model)
            }
            return
        }

        completeDownload(at: location)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            DispatchQueue.main.async {
                self.error = "Download failed: \(error.localizedDescription)"
                self.log = "Download failed: \(error.localizedDescription)"
                self.isDownloading = false
                AppLogger.error("Download task failed: \(error.localizedDescription)", category: .model)
            }
        }
    }
}
