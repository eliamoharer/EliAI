# EliAI - Local iOS Personal AI

A local, privacy-first personal AI assistant for iOS, powered by the **HY-1.8B-2Bit-GGUF** model and `llama.cpp`.

## Features
- **Local Inference**: Runs completely on-device.
- **Agentic Capabilities**: Can create files, manage tasks, and set memories.
- **Privacy Focus**: No data leaves your device.
- **Unique UI**: Layered interface with a background file system and swipeable chat.

## Project Structure
- `EliAI/`: Source code (SwiftUI views, Core services).
- `build.sh`: Script to compile the IPA.
- `ExportOptions.plist`: Config for IPA export.

## How to Build (Requires macOS)

Since you are on Windows, you will need to transfer this folder to a Mac (or use a cloud CI/CD service like GitHub Actions) to build the IPA file.

1.  **Transfer** the entire `EliAI Gemini` folder to a Mac.
2.  **Open Terminal** and navigate to the folder.
3.  **Generate Xcode Project**:
    ```bash
    swift package generate-xcodeproj
    ```
    *Note: If permissions are denied, run `chmod +x build.sh`.*
4.  **Run Build Script**:
    ```bash
    ./build.sh
    ```
5.  **Sideload**: The `.ipa` file will be in the `build/` directory. Sideload it to your iPhone 15 using **AltStore** or **SideStore**.

## First Run
1.  Open the app.
2.  The app will automatically download the **HY-1.8B-2Bit-GGUF** model (~600MB) on the first launch.
3.  Once the indicator turns **Green**, you can start chatting!

## Usage
- **Swipe Up/Down**: Toggle between the Chat and the File System background.
- **Tap Background**: Interact with files (temporarily opaque).
- **Agent Tools**: Ask the AI to "Create a task to buy milk" or "Save a note about my meeting".
