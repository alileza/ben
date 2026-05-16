# Ben

A native macOS app for real-time speech translation between English and German.
Uses Apple's on-device speech recognition (`SFSpeechRecognizer`) and the
on-device Translation framework. Fully offline once the language packs are
installed by macOS itself; no Hugging Face, no API keys, no model downloads
from this app.

![status](https://img.shields.io/badge/macOS-15%2B-blue) ![swift](https://img.shields.io/badge/swift-6-orange)

## What it does

- Captures mic audio, streams it to `SFSpeechRecognizer`.
- Each finalized utterance is translated by the macOS Translation framework.
- Two-column UI: source on the left, translation on the right, vertically
  aligned (one shared scroll view; the active in-progress line pinned at the
  top under the status bar).
- One-click direction toggle (`EN ⇄ DE`), input device picker, hardware mic
  volume slider.
- Optional diagnostics pane (mic peak + translation latency, 30 s sliding
  window) and debug log pane, both toggled from the View menu.

## Requirements

- macOS 15 (Sequoia) or later
- Xcode + Swift toolchain (`swift --version` should report Swift 6.x)
- **Dictation must be enabled** — System Settings → Keyboard → Dictation. The
  Apple speech recognizer returns "Siri and Dictation are disabled" otherwise.
- Optional but useful: download the EN ⇄ DE translation pair when macOS prompts
  the first time you run it.

## Build & run

```bash
./build.sh                     # → Ben.app
open Ben.app
```

On first launch macOS will prompt for **microphone** and **speech recognition**
permission. Both are required.

To regenerate the app icon:

```bash
swift make-icon.swift          # → AppIcon.icns + AppIcon.iconset/
./build.sh                     # rebuilds the bundle with the new icon
```

If Cmd-Tab / Dock still show a stale icon after a rebuild:

```bash
killall Dock Finder
```

## Watch debug logs from the terminal

The app writes every event to `os.log` under subsystem `com.local.ben`:

```bash
log stream --predicate 'subsystem == "com.local.ben"' --style compact
```

Same events show inline in the app when you enable **View → Show Debug Logs**
(⌥⌘D).

## Project layout

```
swift/
├── Package.swift          # SPM manifest (Swift 6, language mode 5)
├── Info.plist             # bundle config + permission usage strings
├── build.sh               # compile + bundle + ad-hoc sign
├── make-icon.swift        # generates AppIcon.icns
└── Sources/Ben/
    ├── BenApp.swift           # @main App + menu commands + shared types
    ├── ContentView.swift      # SwiftUI root + AppState + status bar + panes
    ├── DiagnosticsPane.swift  # mic-peak / latency charts (30 s sliding)
    ├── DebugLog.swift         # in-app ring buffer + os.log forwarding
    ├── AudioEngine.swift      # AVAudioEngine wrapper, AsyncStream output
    ├── AudioDevices.swift     # CoreAudio HAL enumeration + volume
    └── SpeechEngine.swift     # SFSpeechRecognizer wrapper
```

## Known limitations

- Speaker labels stay at `S1`; the app doesn't do diarization.
- macOS's on-device German speech recognition isn't supported on every Mac.
  The debug log will show `onDevice=false` if it falls back to the network
  path (which works while online but isn't truly offline).
- The Translation framework can refuse to prepare a language pair until you
  accept the macOS download sheet. The app surfaces this as
  "translation not available — accept the download prompt".

## Architecture notes

- No Combine. AsyncStream + `.task(id:)` + structured concurrency throughout.
- Single shared `AppState` (`@Observable` on `MainActor`) owned at the App level.
- Engines (`AudioEngine`, `SpeechEngine`) are non-actor classes that publish
  via AsyncStreams; lifecycle is driven by a single `.task(id:)` on the root
  view with `withTaskCancellationHandler` for cleanup.
- Translations re-bind a fresh `AsyncStream` continuation on every
  `.translationTask` activation — necessary because `AsyncStream` is
  single-iterator and direction-change cancels the previous task body.
