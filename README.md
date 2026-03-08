# EchoType

[English](./README.md) | [中文](./README.zh.md)

EchoType is a native offline speech-to-text menubar app for macOS.

It lets you start recording with a global hotkey, transcribes speech into text locally, copies the result to the clipboard, and can automatically paste it into the current input field when the required permissions are granted.

## Features

- Start or stop recording with a global hotkey in one step (default: `⌥ ⌘ Space`, configurable directly in Settings)
- Fully local offline transcription with `WhisperKit` and `Qwen3-ASR (speech-swift / MLX)`
- Two text injection modes: clipboard only, or clipboard plus auto-paste with automatic fallback
- Settings page includes hotkey editing, permission guidance, model install/remove, and language hints
- Temporary audio files are not kept by default, but can be preserved in Settings if needed

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

## Release Packaging

Manual packaging:

```bash
scripts/package.sh \
  --version 1.0.0 \
  --app-name EchoType \
  --binary-name echotype \
  --bundle-id com.smoose.echotype
```

Upload to GitHub Releases locally (recommended to avoid differences in cloud build environments):

```bash
scripts/release.sh \
  --version 1.0.0 \
  --repo smoosex/echotype \
  --tap-repo smoosex/homebrew-tap
```

Notes:

- The script reads local artifacts from `dist/` and uploads them to the GitHub Release for the matching tag
- It also generates `dist/echotype.rb` from the local DMG and uploads it
- `--tap-repo` is optional. If omitted, only Release assets are uploaded and the Homebrew tap is not updated
- If `--tap-repo` is provided, the script syncs via SSH using `git@github.com:<owner>/<repo>.git`, so make sure your GitHub SSH key is configured first

## Maintainer Test Environment

The current release workflow is validated on the maintainer's local machine. Verified environment:

- macOS Tahoe 26.3
- Apple Silicon (`arm64`)
- Xcode 26.3 + Metal Toolchain
- Homebrew (used for cask install/validation)

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
- Raw recordings are not persisted by default
- Logs are used for diagnostics and do not record raw audio content
