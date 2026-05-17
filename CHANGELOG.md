# Changelog

All notable changes to Ben are tracked in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Nothing yet._

## [0.0.1] - 2026-05-17

First public release.

### Added
- Real-time EN ⇄ DE speech translation via `SFSpeechRecognizer` +
  `Translation` framework, fully on-device.
- Two-column transcript with shared scroll for vertical alignment; active
  row pinned under the status bar.
- One-click direction toggle (`EN ⇄ DE`).
- Input device picker + hardware mic volume slider in a popover.
- Diagnostics pane: mic peak + translation latency, 30 s sliding window
  via `TimelineView`.
- In-app debug log pane (toggleable from View menu); mirrors to `os.log`
  under subsystem `com.local.ben`.
- Transcript export to `.txt` (source / translation / both paired).
- Silence watchdog (1 s) + 5 s soft chunking + 10 s hard cap, never
  mid-word.
- Canonical translation matching on commit (source/translation always
  correspond).
- Wall-clock timestamps to the second.
- Custom app icon.
- Per-concern source layout (`Audio/`, `Speech/`, `Views/`, …).
- MIT LICENSE, CONTRIBUTING, CODE_OF_CONDUCT.
- GitHub Actions CI: builds the `.app` on push and PR.
- Release workflow: tagging `v*` produces a DMG + SHA-256 and publishes a
  GitHub Release with install instructions.
- Issue and PR templates.
- Empty-state hint in the transcript view when there are no committed
  utterances yet.
- GitHub Pages landing at <https://alileza.github.io/ben/>.
