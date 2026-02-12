# EliAI - Local iOS Personal AI

A local, privacy-first personal AI assistant for iOS, powered by `llama.cpp` through `LLM.swift`, with validated `.gguf` support for Qwen 3 and LFM 2.5 profiles.

## Features
- **Local Inference**: Runs completely on-device.
- **Agentic Capabilities**: Can create files, manage tasks, and set memories.
- **Privacy Focus**: No data leaves your device.
- **Unique UI**: Layered interface with a background file system and swipeable chat.
- **Model Safety**: Preflight GGUF validation (magic bytes, minimum size, metadata hints).
- **Model Recovery**: Automatic fallback to another valid local model when load fails.

## Project Structure
- `EliAI/`: Source code (SwiftUI views, Core services).
- `build.sh`: Script to compile the IPA.
- `ExportOptions.plist`: Config for IPA export.

## How to Build

### Option 1: GitHub Actions (Recommended for Windows Users)
Since you are on Windows, the easiest way to get the IPA file is to use GitHub Actions.

1.  **Push** this entire repository to your GitHub account.
2.  Go to the **Actions** tab in your repository.
3.  Select the **Build EliAI IPA** workflow.
4.  Run the workflow manually (or it will run on push).
5.  Once completed, download the **EliAI-IPA** artifact from the run summary page.
6.  Unzip the artifact to get `EliAI.ipa`.

### Option 2: Build on Mac (Local)
If you have access to a Mac:

1.  Open Terminal in the project folder.
2.  Run:
    ```bash
    swift package generate-xcodeproj
    chmod +x build.sh
    ./build.sh
    ```
3.  The `EliAI.ipa` file will be generated in the root directory.

## Installation
Sideload the `EliAI.ipa` file to your iPhone using **AltStore** or **SideStore**.

## CI Pipeline (GitHub Actions)
The workflow now runs:
1. Selects an installed Xcode that includes `iphoneos` SDK
2. Resolves package dependencies
3. Builds release app for generic iOS device
4. Packages unsigned IPA artifact

`LLM.swift` is pinned to a fixed git revision in `project.yml` for deterministic builds.

## First Run
1.  Open the app.
2.  The app can download a preset model (Qwen 3 or LFM 2.5), or import a local `.gguf` file.
3.  Once the indicator turns **Green**, you can start chatting!

## Usage
- **Swipe Up/Down**: Toggle between the Chat and the File System background.
- **Tap Background**: Interact with files (temporarily opaque).
- **Agent Tools**: Ask the AI to "Create a task to buy milk" or "Save a note about my meeting".
