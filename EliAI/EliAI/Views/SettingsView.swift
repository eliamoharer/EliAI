import Foundation
import SwiftUI

struct SettingsView: View {
    var modelDownloader: ModelDownloader?
    var llmEngine: LLMEngine?
    private let responseStyleKey = AppConfiguration.Keys.responseStyle
    private let samplingTemperatureKey = AppConfiguration.Keys.samplingTemperature
    private let samplingTopKKey = AppConfiguration.Keys.samplingTopK
    @State private var temperatureInput: String = ""
    @State private var topKInput: String = ""
    @State private var samplingStatusMessage: String = ""
    @State private var samplingStatusIsError = false
    @State private var isApplyingSampling = false

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
                        Text("Temperature")
                        TextField("0.10", text: $temperatureInput)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                        Text("Range: 0.00 to 1.50")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Model default: \(String(format: "%.2f", samplingBase.temperature))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Top-k")
                        TextField("50", text: $topKInput)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                        Text("Range: 1 to 200")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Model default: \(samplingBase.topK)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text("Repeat penalty: \(String(format: "%.2f", samplingBase.repeatPenalty))")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button(isApplyingSampling ? "Saving..." : "Save Values + Reload Model") {
                        Task { await saveSamplingAndReload() }
                    }
                    .disabled(isApplyingSampling)

                    Button("Reset Inputs To Model Defaults") {
                        temperatureInput = String(format: "%.2f", samplingBase.temperature)
                        topKInput = "\(samplingBase.topK)"
                        samplingStatusMessage = ""
                    }

                    if !samplingStatusMessage.isEmpty {
                        Text(samplingStatusMessage)
                            .font(.caption)
                            .foregroundColor(samplingStatusIsError ? .red : .secondary)
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
        .onAppear {
            syncSamplingInputsFromStoredValues()
        }
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

    private func syncSamplingInputsFromStoredValues() {
        let defaults = UserDefaults.standard
        let storedTemperature = (defaults.object(forKey: samplingTemperatureKey) as? NSNumber)?.doubleValue
        let storedTopK = (defaults.object(forKey: samplingTopKKey) as? NSNumber)?.intValue

        let temperature = clampTemperature(storedTemperature ?? samplingBase.temperature)
        let topK = clampTopK(storedTopK ?? samplingBase.topK)

        temperatureInput = String(format: "%.2f", temperature)
        topKInput = "\(topK)"
    }

    private func parseTemperatureInput() -> Double? {
        let normalized = temperatureInput
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private func parseTopKInput() -> Int? {
        let normalized = topKInput
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if let intValue = Int(normalized) {
            return intValue
        }
        if let doubleValue = Double(normalized) {
            return Int(doubleValue.rounded())
        }
        return nil
    }

    @MainActor
    private func saveSamplingAndReload() async {
        guard let parsedTemperature = parseTemperatureInput() else {
            samplingStatusMessage = "Enter a valid temperature."
            samplingStatusIsError = true
            return
        }
        guard let parsedTopK = parseTopKInput() else {
            samplingStatusMessage = "Enter a valid top-k."
            samplingStatusIsError = true
            return
        }

        let temperature = clampTemperature(parsedTemperature)
        let topK = clampTopK(parsedTopK)

        UserDefaults.standard.set(temperature, forKey: samplingTemperatureKey)
        UserDefaults.standard.set(topK, forKey: samplingTopKKey)
        temperatureInput = String(format: "%.2f", temperature)
        topKInput = "\(topK)"

        guard let engine = llmEngine, engine.isLoaded else {
            samplingStatusMessage = "Values saved. Load a model to apply them."
            samplingStatusIsError = false
            return
        }

        isApplyingSampling = true
        defer { isApplyingSampling = false }

        let reloaded = await engine.reloadCurrentModel()
        if reloaded {
            samplingStatusMessage = "Values saved and model reloaded."
            samplingStatusIsError = false
        } else {
            samplingStatusMessage = "Values saved, but model reload failed."
            samplingStatusIsError = true
        }
    }
}
