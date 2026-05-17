# Contributing to Ben

Thanks for taking the time. Ben is a small, focused project — keep PRs small
and focused too.

## Local development

```bash
git clone git@github.com:alileza/ben.git
cd ben
./build.sh
open Ben.app
```

Required on the **host machine**:

- macOS 15 (Sequoia) or later
- Xcode + Swift 6 toolchain
- **Dictation enabled** (System Settings → Keyboard → Dictation) — otherwise
  `SFSpeechRecognizer` returns "Siri and Dictation are disabled" on every
  recognition task. This isn't something the app can fix; it's an OS prereq.
- EN ⇄ DE translation pair installed (macOS will prompt on first use).

## Project layout

```
Sources/Ben/
├── App.swift          @main entry + View-menu commands
├── AppState.swift     @Observable shared state + translation queue
├── Models.swift       Direction, PairedRow, MicPoint, LatencyPoint
├── Audio/             AVAudioEngine + CoreAudio HAL device enumeration
├── Speech/            SFSpeechRecognizer wrapper
├── Export/            Transcript .txt export
├── Logging/           In-app ring-buffer logger + os.log mirror
└── Views/             SwiftUI views (ContentView is the root composition)
```

See [BEST_PRACTICES.md](./BEST_PRACTICES.md) for the design conventions this
project follows (AsyncStream over Combine, granular `@Observable` views,
stale-callback guards, etc.).

## Coding style

- Swift 6 toolchain, language mode 5 (set in `Package.swift`). Don't change
  that without a strong reason — most Apple frameworks aren't Sendable-clean
  yet and the noise drowns real signals.
- 4-space indentation, no tabs.
- Prefer `///` doc comments on types and methods that aren't obvious from
  the signature. Skip inline `//` comments for code that's self-explanatory.
- Reach for `@ViewBuilder` / extracted subviews when a `body` exceeds ~50
  lines or the type-checker complains.
- Avoid `AnyView`. If you think you need it, you probably want generics or
  a small enum.

## Pull requests

- One concern per PR. "Add export to JSON" and "rename `commitLines`" are
  two PRs.
- Build locally first (`./build.sh`). CI runs the same `swift build`.
- Include a brief description: *what changed* and *why*. If the diff is
  obvious from the title, "self-explanatory" is a fine description.
- Update [BEST_PRACTICES.md](./BEST_PRACTICES.md) only if a *pattern*
  changed across the codebase, not for one-off fixes.
- No "Co-Authored-By" / "Generated with" lines in commits.

## Filing issues

- For **bugs**: include macOS version, Swift version (`swift --version`),
  the snippet of `log stream --predicate 'subsystem == "com.local.ben"'`
  output that shows the failure, and exact steps to reproduce.
- For **feature requests**: describe the user problem first, the proposed
  solution second. "I want auto-detect language" is more useful than
  "add `NLLanguageRecognizer` calls in SpeechEngine".

## What I'll probably say no to

- Cross-platform support. Ben is built on Apple's on-device frameworks;
  porting to Linux or Windows would mean rewriting everything that matters.
- Vendor lock to a particular cloud STT/MT provider. The whole point is
  on-device.
- Heavy dependency additions. Today the SPM target has zero third-party
  deps. Keep it that way unless you can justify the maintenance cost.
- New languages without an on-device path on macOS. If `SFSpeechRecognizer`
  + `TranslationSession` can do it on-device, sure; otherwise no.

## License

By contributing you agree your changes are licensed under the [MIT License](./LICENSE).
