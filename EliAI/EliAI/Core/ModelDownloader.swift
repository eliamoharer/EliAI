import Foundation

@Observable
class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    var downloadProgress: Double = 0.0
    var isDownloading = false
    var error: String?
    var localModelURL: URL?
    var log: String = "Ready to load model." // New log property
    
    private var downloadTask: URLSessionDownloadTask?
    
    // Verified Feb 2026 Working Link (Unsloth Qwen 3 1.7B)
    let modelURLString = "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"
    let modelFileName = "Qwen3-1.7B-Q4_K_M.gguf"
    
    func checkLocalModel() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsURL.appendingPathComponent(modelFileName)
        
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
                }
                try? fileHandle.close()
            }
        }
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
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { 
            self.log = "Error: Could not find documents directory."
            return 
        }
        let destinationURL = documentsURL.appendingPathComponent(modelFileName)
        
        self.log = "Starting import from: \(sourceURL.lastPathComponent)..."
        self.isDownloading = true // Use this to show activity
        self.downloadProgress = 0.0
        
        Task {
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    self.log = "Removing existing model file..."
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                let gotAccess = sourceURL.startAccessingSecurityScopedResource()
                if !gotAccess {
                    self.log = "Warning: Could not access security scoped resource. Attempting copy anyway..."
                }
                
                defer {
                    if gotAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }
                
                self.log = "Copying file (this may take a moment)..."
                // Copying large files can block, so we run this on a background thread if possible, 
                // but FileManager isn't async. We rely on Task priority.
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                
                await MainActor.run {
                    self.localModelURL = destinationURL
                    self.downloadProgress = 1.0
                    self.isDownloading = false
                    self.error = nil
                    self.log = "Import successful! Model ready: \(self.modelFileName)"
                }
            } catch {
                await MainActor.run {
                    self.error = "Import error: \(error.localizedDescription)"
                    self.log = "Import failed: \(error.localizedDescription)"
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
        
        let destinationURL = documentsURL.appendingPathComponent(modelFileName)
        
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
