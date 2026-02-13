import SwiftUI

struct SettingsView: View {
    var modelDownloader: ModelDownloader?
    private let responseStyleKey = "responseStyle"

    var body: some View {
        Form {
            if let downloader = modelDownloader {
                Section("Model Source") {
                    Picker(
                        "Download Model",
                        selection: Binding(
                            get: { downloader.selectedRemoteModelID },
                            set: { downloader.selectedRemoteModelID = $0 }
                        )
                    ) {
                        ForEach(downloader.remoteCatalog) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                }

                Section("Model Information") {
                    Text("Active: \(downloader.activeModelName)")

                    if downloader.localModelURL != nil {
                        Label("Model verified and ready", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if downloader.isDownloading {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Downloading...")
                                .foregroundColor(.orange)
                            ProgressView(value: downloader.downloadProgress)
                            Text("\(Int(downloader.downloadProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Label("No valid model selected", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }

                    if let error = downloader.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section("Response Style") {
                    Picker(
                        "Assistant Mode",
                        selection: Binding(
                            get: { UserDefaults.standard.string(forKey: responseStyleKey) ?? "auto" },
                            set: { UserDefaults.standard.set($0, forKey: responseStyleKey) }
                        )
                    ) {
                        Text("Auto").tag("auto")
                        Text("Thinking").tag("thinking")
                        Text("Instruct").tag("instruct")
                    }
                }

                Section("Download") {
                    Button("Download Selected Model") {
                        downloader.downloadModel()
                    }
                    .disabled(downloader.isDownloading)

                    if downloader.isDownloading {
                        Button("Cancel Download", role: .destructive) {
                            downloader.cancelDownload()
                        }
                    }
                }

                Section("Model Library") {
                    if downloader.availableModels.isEmpty {
                        Text("No local models found.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(downloader.availableModels, id: \.self) { model in
                            HStack {
                                Button(model) {
                                    downloader.activeModelName = model
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                if model == downloader.activeModelName {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green)
                                }

                                Button(role: .destructive) {
                                    downloader.deleteModel(named: model)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            } else {
                Section("Model Information") {
                    Text("Model service unavailable.")
                        .foregroundColor(.secondary)
                }
            }

            Section("About") {
                HStack {
                    Text("EliAI")
                    Spacer()
                    Text("Feb 2026")
                        .foregroundColor(.secondary)
                }
                Text("On-device GGUF inference for Qwen 3 and LFM 2.5 profiles.")
            }
        }
        .navigationTitle("Settings")
    }
}
