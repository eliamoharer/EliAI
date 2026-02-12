import SwiftUI

struct SettingsView: View {
    // We need access to modelDownloader here too
    // In a real app, use EnvironmentObject
    var modelDownloader: ModelDownloader? 
    // Made optional to keep previews working easily, or passed from FileExplorerView
    
    var body: some View {
        Form {
            Section(header: Text("Model Information")) {
                if let downloader = modelDownloader {
                    Text("Model: \(downloader.activeModelName)")
                    
                    if downloader.localModelURL != nil {
                        HStack {
                            Text("Status: Loaded & Ready")
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    } else if downloader.isDownloading {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Status: Downloading...")
                                .foregroundColor(.orange)
                            ProgressView(value: downloader.downloadProgress)
                            Text("\(Int(downloader.downloadProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        HStack {
                            Text("Status: Not Downloaded")
                                .foregroundColor(.red)
                            Spacer()
                            Button("Download Qwen 3") {
                                downloader.downloadModel()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    if let error = downloader.error {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                } else {
                    Text("Model service not available")
                        .foregroundColor(.gray)
                }
            }
            
            Section(header: Text("Storage")) {
                Button("Clear Chat History") {
                    // This is handled via ChatManager
                }
                .foregroundColor(.red)
                
                if let downloader = modelDownloader, downloader.isDownloading {
                     Button("Cancel Download") {
                        downloader.cancelDownload()
                     }
                     .foregroundColor(.red)
                }
            }
            
            Section(header: Text("About")) {
                HStack {
                    Text("EliAI")
                    Spacer()
                    Text("Feb 2026 Edition")
                        .foregroundColor(.gray)
                }
                Text("Powered by LLM.swift & Qwen 3")
            }
        }
        .navigationTitle("Settings")
    }
}
