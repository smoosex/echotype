# EchoType

![EchoType Demo](./assets/demo.png)

[English](./README.md) | [中文](./README.zh.md)

EchoType is a native offline speech-to-text menubar app for macOS.

It lets you start recording with a global hotkey, transcribes speech into text locally, copies the result to the clipboard, and can automatically paste it into the current input field when the required permissions are granted.

## Features

- Start or stop recording with a global hotkey in one step (default: `⌥ ⌘ Space`, configurable directly in Settings)
- Fully local offline transcription with `WhisperKit` and `Qwen3-ASR (speech-swift / MLX)`
- Two text injection modes: clipboard only, or clipboard plus auto-paste with automatic fallback
- Settings page includes hotkey editing, permission guidance, model install/remove, and language hints

Auto-paste note: when `Clipboard + Auto Paste` is enabled, EchoType pastes into whichever app is frontmost at transcription completion time. The transcribed text is also placed on the macOS clipboard before the paste shortcut is sent.

## System Requirements

- macOS 14+
- Apple Silicon (M1 or newer)
- Microphone permission is required for recording
- Accessibility permission is optional for auto-paste; clipboard copy still works without it

## Installation

### Option A: Homebrew (Recommended)

```bash
brew tap smoosex/tap
brew install --cask echotype
```

Or install in one line:

```bash
brew install --cask smoosex/tap/echotype
```

### Option B: GitHub Releases (DMG)

1. Download `EchoType-<version>.dmg`
2. Open it and drag `EchoType.app` into `Applications`
3. Launch the app and grant the requested permissions on first run

Note: the public build currently ships with ad-hoc signed executables and resource bundles. Developer ID signing and notarization are not enabled yet. After downloading or updating the app, run the following command, then re-grant microphone and accessibility permissions. For accessibility permission, you may need to remove the old entry first and then authorize it again.

```bash
sudo xattr -dr com.apple.quarantine "/Applications/EchoType.app"
```

## First Launch

1. On first launch, EchoType opens the Welcome Guide automatically so you can complete microphone/accessibility permission setup and read the usage notes
2. You can enable `Don't show this guide again` so it will not appear on startup in the future. You can still reopen it from the `Welcome Guide` menu
3. Click `Start Using EchoType` to open the Settings page automatically
4. In the `General` tab, click the hotkey recorder field and press your preferred shortcut directly. If registration fails, EchoType shows the reason and falls back to the default `⌥⌘Space`
5. In the `Models` tab, choose and install a model
6. Return to the main app, press the hotkey to start recording, then press it again to stop and wait for transcription

## Models

- `WhisperKit`: for Whisper models
- `speech-swift`: for Qwen3-ASR models (Apple Silicon GPU / MLX)

Engine projects used in EchoType:

- Whisper models are powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit)
- Qwen3-ASR models are powered by [speech-swift](https://github.com/soniqo/speech-swift)

Currently available models:

- `Whisper Tiny`
- `Whisper Base`
- `Whisper Large v3`
- `Qwen3-ASR 0.6B`
- `Qwen3-ASR 1.7B`

After installation, EchoType automatically switches to the corresponding engine based on the selected model.

## Local Development

```bash
swift build
scripts/build_mlx_metallib.sh debug
swift run
```

Note: `speech-swift` depends on `mlx.metallib`. After the first local development build, run `scripts/build_mlx_metallib.sh debug` once.
If your system currently uses only Command Line Tools, install the full Xcode app first, then run `xcodebuild -downloadComponent MetalToolchain`.

## Complete Uninstall

```bash
scripts/uninstall.sh
```

Common options:

```bash
scripts/uninstall.sh --dry-run
scripts/uninstall.sh --yes
```

## Privacy

- Audio and transcription text are not uploaded to external services by default
- Logs are used for diagnostics and do not record raw audio content
