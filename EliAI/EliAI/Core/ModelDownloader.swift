import Foundation

@Observable
class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    var downloadProgress: Double = 0.0
    var isDownloading = false
    var error: String?
    var localModelURL: URL?
    var log: String = "Ready to load model." 

    
    private var downloadTask: URLSessionDownloadTask?
    
    override init() {
        super.init()
        checkLocalModel()
        refreshAvailableModels()
    }
    
    // Verified Feb 2026 Working Link (Unsloth Qwen 3 1.7B)
    let modelURLString = "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"
    
    // Persist active model name across launches
    var activeModelName: String {
        get { UserDefaults.standard.string(forKey: "activeModelName") ?? "Qwen3-1.7B-Q4_K_M.gguf" }
        set { 
            UserDefaults.standard.set(newValue, forKey: "activeModelName")
            checkLocalModel() // Re-check whenever the name changes
        }
    }
    
    func checkLocalModel() {
        refreshAvailableModels()
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsURL.appendingPathComponent(activeModelName)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // Validate GGUF Header
            if let fileHandle = try? FileHandle(forReadingFrom: fileURL) {
                if let data = try? fileHandle.read(upToCount: 4), data == Data([0x47, 0x47, 0x55, 0x46]) {
                    self.localModelURL = fileURL
                    self.downloadProgress = 1.0
                    self.log = "Model verified and ready."
                } else {
                    self.error = "Corrupted model detected. Please redownload."
                    self.log = "Failed: Invalid GGUF header."
                    try? FileManager.default.removeItem(at: fileURL)
                    refreshAvailableModels()
                }
                try? fileHandle.close()
            }
        } else {
            self.localModelURL = nil
            self.log = "Ready to load model."
        }
    }
    
    var availableModels: [String] = []
    
    func refreshAvailableModels() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let contents = try? FileManager.default.contentsOfDirectory(atPath: documentsURL.path)
        self.availableModels = contents?.filter { $0.hasSuffix(".gguf") } ?? []
    }
    
    func deleteModel(named name: String) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsURL.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: fileURL)
        if name == activeModelName {
            localModelURL = nil
            activeModelName = "Qwen3-1.7B-Q4_K_M.gguf" // Reset to default
        }
        refreshAvailableModels()
    }
    
    func downloadModel() {
        guard let url = URL(string: modelURLString) else { return }
        
        isDownloading = true
        error = nil
        downloadProgress = 0.0
        log = "Starting download..."
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        isDownloading = false
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func importLocalModel(from sourceURL: URL) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileName = sourceURL.lastPathComponent
        let destinationURL = documentsURL.appendingPathComponent(fileName)
        
        self.updateLog("Starting import from: \(fileName)...")
        self.activeModelName = fileName
        self.isDownloading = true // Use this to show activity
        self.downloadProgress = 0.0
        
        Task {
            do {
                let gotAccess = sourceURL.startAccessingSecurityScopedResource()
                if !gotAccess {
                    self.updateLog("Warning: Could not access security scoped resource. Attempting copy anyway...")
                }
                
                defer {
                    if gotAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }
                
                self.updateLog("Copying file (this may take a moment)...")
                
                // Copy to a temporary location first to ensure atomicity/safety
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("gguf")
                try FileManager.default.copyItem(at: sourceURL, to: tempURL)
                
                // Now move to destination, overwriting if necessary
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                
                await MainActor.run {
                    self.localModelURL = destinationURL
                    self.downloadProgress = 1.0
                    self.isDownloading = false
                    self.error = nil
                    self.updateLog("Import successful! Model ready: \(self.activeModelName)")
                }
            } catch {
                await MainActor.run {
                    self.error = "Import error: \(error.localizedDescription)"
                    self.updateLog("Import failed: \(error.localizedDescription)")
                    self.isDownloading = false
                }
            }
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // If totalBytesExpectedToWrite is -1 (unknown), we can't show accurate progress.
        // HuggingFace usually sends Content-Length.
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async {
                self.downloadProgress = progress
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Check for HTTP errors (e.g. 404, 403, or HTML redirects)
        if let response = downloadTask.response as? HTTPURLResponse {
            if response.statusCode != 200 {
                DispatchQueue.main.async {
                    self.error = "Server error: HTTP \(response.statusCode)"
                    self.log = "Download failed: Server returned error \(response.statusCode)"
                    self.isDownloading = false
                }
                return
            }
        }
        
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            DispatchQueue.main.async {
                self.error = "FileSystem error"
                self.isDownloading = false
            }
            return
        }
        
        let destinationURL = documentsURL.appendingPathComponent(activeModelName)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            DispatchQueue.main.async {
                self.localModelURL = destinationURL
                self.downloadProgress = 1.0
                self.isDownloading = false
                self.error = nil 
                self.log = "Download complete! Model ready."
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "File move error: \(error.localizedDescription)"
                self.isDownloading = false
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.error = "Download failed: \(error.localizedDescription)"
                self.log = "Download failed: \(error.localizedDescription)"
                self.isDownloading = false
                print("Download error: \(error)") // Log to console for debugging
            }
        }
    }
    
    // Helper to update log
    private func updateLog(_ message: String) {
        DispatchQueue.main.async {
            self.log = message
        }
    }
}
