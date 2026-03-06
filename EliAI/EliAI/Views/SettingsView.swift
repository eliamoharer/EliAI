import Foundation
import SwiftUI

struct SettingsView: View {
    var modelDownloader: ModelDownloader?
    var llmEngine: LLMEngine?
    private let responseStyleKey = AppConfiguration.Keys.responseStyle
    private let samplingPresetKey = AppConfiguration.Keys.samplingPreset

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

                Section("Generation Preset") {
                    Picker(
                        "Sampling",
                        selection: Binding(
                            get: {
                                UserDefaults.standard.string(forKey: samplingPresetKey)
                                    ?? SamplingControlPreset.modelDefault.rawValue
                            },
                            set: { UserDefaults.standard.set($0, forKey: samplingPresetKey) }
                        )
                    ) {
                        ForEach(SamplingControlPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset.rawValue)
                        }
                    }

                    Text(selectedSamplingPreset.details)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(currentSamplingSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
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

    private var selectedSamplingPreset: SamplingControlPreset {
        SamplingControlPreset(
            rawValue: UserDefaults.standard.string(forKey: samplingPresetKey)
                ?? SamplingControlPreset.modelDefault.rawValue
        ) ?? .modelDefault
    }

    private var currentSamplingSummary: String {
        let base = llmEngine?.activeProfile.sampling ?? ModelProfile.lfm25.sampling
        let effective = selectedSamplingPreset.apply(to: base)
        let temperature = String(format: "%.2f", effective.temperature)
        let repeatPenalty = String(format: "%.2f", effective.repeatPenalty)
        return "Temperature \(temperature), top-k \(effective.topK), repeat penalty \(repeatPenalty)."
    }
}
