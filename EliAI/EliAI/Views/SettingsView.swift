import Foundation
import SwiftUI

struct SettingsView: View {
    var modelDownloader: ModelDownloader?
    var llmEngine: LLMEngine?
    private let responseStyleKey = AppConfiguration.Keys.responseStyle
    private let samplingTemperatureKey = AppConfiguration.Keys.samplingTemperature
    private let samplingTopKKey = AppConfiguration.Keys.samplingTopK

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

                Section("Sampling") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", clampedTemperature))
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { clampedTemperature },
                                set: { UserDefaults.standard.set(clampTemperature($0), forKey: samplingTemperatureKey) }
                            ),
                            in: 0.0 ... 1.5,
                            step: 0.01
                        )
                        Text("Model default: \(String(format: "%.2f", samplingBase.temperature))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Top-k")
                            Spacer()
                            Text("\(clampedTopK)")
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(clampedTopK) },
                                set: { UserDefaults.standard.set(clampTopK(Int($0.rounded())), forKey: samplingTopKKey) }
                            ),
                            in: 1 ... 200,
                            step: 1
                        )
                        Text("Model default: \(samplingBase.topK)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text("Repeat penalty: \(String(format: "%.2f", samplingBase.repeatPenalty))")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button("Reset To Model Defaults") {
                        UserDefaults.standard.set(samplingBase.temperature, forKey: samplingTemperatureKey)
                        UserDefaults.standard.set(samplingBase.topK, forKey: samplingTopKKey)
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
                Text("On-device GGUF inference for LFM 2.5 and Qwen 3 profiles.")
            }
        }
        .navigationTitle("Settings")
    }

    private var samplingBase: SamplingPreset {
        llmEngine?.activeProfile.sampling ?? ModelProfile.lfm25.sampling
    }

    private var clampedTemperature: Double {
        let storedNumber = UserDefaults.standard.object(forKey: samplingTemperatureKey) as? NSNumber
        return clampTemperature(storedNumber?.doubleValue ?? samplingBase.temperature)
    }

    private var clampedTopK: Int {
        let storedNumber = UserDefaults.standard.object(forKey: samplingTopKKey) as? NSNumber
        return clampTopK(storedNumber?.intValue ?? samplingBase.topK)
    }

    private func clampTemperature(_ value: Double) -> Double {
        min(max(value, 0.0), 1.5)
    }

    private func clampTopK(_ value: Int) -> Int {
        min(max(value, 1), 200)
    }
}
