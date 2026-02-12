import Foundation

@Observable
class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    var downloadProgress: Double = 0.0
    var isDownloading = false
    var error: String?
    var localModelURL: URL?
    
    private var downloadTask: URLSessionDownloadTask?
    
    // HY-1.8B-2Bit-GGUF
    let modelURLString = "https://huggingface.co/AngelSlim/HY-1.8B-2Bit-GGUF/resolve/main/hy-1.8b-2bit.gguf"
    let modelFileName = "hy-1.8b-2bit.gguf"
    
    func checkLocalModel() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsURL.appendingPathComponent(modelFileName)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            self.localModelURL = fileURL
            self.downloadProgress = 1.0
        }
    }
    
    func downloadModel() {
        guard let url = URL(string: modelURLString) else { return }
        
        isDownloading = true
        error = nil
        downloadProgress = 0.0
        
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
        let destinationURL = documentsURL.appendingPathComponent(modelFileName)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            if sourceURL.startAccessingSecurityScopedResource() {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                sourceURL.stopAccessingSecurityScopedResource()
            } else {
                // Try copying directly if not security scoped (e.g. from same app sandbox, unlikely but possible)
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
            
            self.localModelURL = destinationURL
            self.downloadProgress = 1.0
            self.error = nil
        } catch {
            self.error = "Import error: \(error.localizedDescription)"
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
                self.isDownloading = false
                print("Download error: \(error)") // Log to console for debugging
            }
        }
    }
}
