# Ben

Real-time English ⇄ German speech translation on macOS. Fully on-device —
no API keys, no model downloads from this app, no network round-trips.

[![build](https://github.com/alileza/ben/actions/workflows/build.yml/badge.svg)](https://github.com/alileza/ben/actions/workflows/build.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![macOS](https://img.shields.io/badge/macOS-15%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://www.swift.org/)

> Pipeline: `AVAudioEngine` → `SFSpeechRecognizer` → `Translation` framework.
> All Apple system frameworks; everything runs locally.

---

## Quick start

```bash
git clone git@github.com:alileza/ben.git
cd ben
./build.sh
open Ben.app
```

First launch will ask for **Microphone** and **Speech Recognition**
permission, and (on first use of a language pair) prompt to download the
on-device translation model.

## Requirements

| Requirement | Notes |
|---|---|
| macOS 15+ (Sequoia / Tahoe) | The Translation framework needs 15 |
| Xcode + Swift 6 toolchain | `swift --version` should report 6.x |
| Dictation enabled | System Settings → Keyboard → Dictation. Without it `SFSpeechRecognizer` errors with "Siri and Dictation are disabled" |
| EN ⇄ DE translation pair | macOS prompts to download on first use |

## Features

- **Two-column transcript** with a shared scroll — source and translation
  rows are always vertically aligned. Active in-progress row is pinned at
  the top under the status bar.
- **One-click direction toggle** (`EN ⇄ DE`).
- **Input device picker + hardware mic volume** in a popover next to the
  start/stop button.
- **Diagnostics pane**: live mic peak, translation latency chart,
  30 s sliding window.
- **Debug log pane**: in-app ring-buffered events, mirrored to `os.log`
  under subsystem `com.local.ben` so `log stream` works too.
- **Transcript export** to `.txt` — source only, translation only, or both
  paired with timestamps.
- **Smart chunking**: pauses commit a new line; long monologues chunk at
  word boundaries after 5 s (10 s hard cap).
- **Canonical translation pairing**: the committed row's source and
  translation always correspond — no race conditions where the displayed
  translation lags behind the recognizer's final text.

## Project layout

```
Sources/Ben/
├── App.swift                @main entry + View-menu commands
├── AppState.swift           Observable shared state + translation queue
├── Models.swift             Direction, PairedRow, MicPoint, LatencyPoint
├── Audio/
│   ├── AudioEngine.swift    AVAudioEngine → AsyncStream
│   └── AudioDevices.swift   CoreAudio HAL enumeration + volume control
├── Speech/
│   └── SpeechEngine.swift   SFSpeechRecognizer with stale-callback guard
├── Export/
│   └── TranscriptExport.swift  .txt save via NSSavePanel
├── Logging/
│   └── DebugLog.swift       Ring buffer + os.log
└── Views/
    ├── ContentView.swift    Root composition + engine driver
    ├── StatusBar.swift      Top bar + pills + popover controls
    ├── Transcript.swift     Two-column transcript + active row
    ├── Diagnostics.swift    Mic + latency charts (Swift Charts)
    └── Debug.swift          Debug log pane
```

The architecture is documented in [BEST_PRACTICES.md](./BEST_PRACTICES.md).

## Watching debug logs

In-app: **View → Show Debug Logs** (⌥⌘D).

In a terminal:

```bash
log stream --predicate 'subsystem == "com.local.ben"' --style compact
```

## Build & regenerate the icon

```bash
swift make-icon.swift   # writes AppIcon.icns + AppIcon.iconset/
./build.sh              # rebuilds the bundle with the new icon
```

If the Dock or Cmd-Tab shows a stale icon after a rebuild:

```bash
killall Dock Finder
```

## Troubleshooting

| Symptom | What to check |
|---|---|
| "Siri and Dictation are disabled" in the debug log | Enable Dictation in System Settings → Keyboard |
| Source pane fills but translation stays empty | Accept the macOS download prompt for the language pair on first use |
| App in `/Applications` doesn't appear in Spotlight or Alfred | Ad-hoc-signed apps in `/Applications` are filtered by Gatekeeper. Run `sudo spctl --add /Applications/Ben.app` or keep the build under your home dir |
| Cmd-Tab shows a stale white-square icon | `killall Dock` to bust the icon cache |
| German is recognized but `onDevice=false` in the log | Your Mac doesn't have on-device German; recognition falls back to the network |

## Limitations

- Speaker labels stay at `S1`; no real diarization.
- On-device speech availability varies by language and Mac model.
- Auto-detect (speak either language without flipping the toggle) is on the
  roadmap, not in the app yet.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). PRs and issues welcome — keep them
small and focused.

## License

MIT. See [LICENSE](./LICENSE).
