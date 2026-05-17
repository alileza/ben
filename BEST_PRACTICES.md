# Best Practices for Building Native macOS Apps

A focused, opinionated reference distilled from shipping Ben — a SwiftUI app
on macOS 15+ that combines `AVAudioEngine`, `SFSpeechRecognizer`, and the
Translation framework. Not exhaustive; just the things that actually bit us.

Use these as defaults, not laws. Read the [SwiftUI Proverbs](https://gist.github.com/) too.

---

## State & Observation

- **One `@Observable` model at the app level.** Owned via `@State` on `App`
  and passed into the root view. Don't create state types just to wrap other
  state types. Don't use `class FooViewModel: ObservableObject` if you're on
  iOS 17+ / macOS 14+ — `@Observable` replaces it, and you'll observe at
  property granularity instead of object granularity.
- **Push observation down, not up.** A status pill that reads `state.status`
  should be its own `View` so only that pill re-renders on status changes.
  In Ben, breaking `StatusBar`, `TranscriptPane`, `DebugPane`, and
  `DiagnosticsPane` into separate structs is what keeps the body fast.
- **`@ObservationIgnored` for plumbing.** Continuations, queues, internal
  bookkeeping — none of these should trigger a view re-render. Mark them and
  move on. Example from Ben: `pendingResponses: [UUID: …]` is plumbing for
  request/response translation; storing it as observed would be wrong.
- **State location follows responsibility.** UI-only flags (`showDebug`,
  `showDiagnostics`) live in `AppState`. View-local ephemera (`@State var
  hovered`) lives in the view. Engines (`AudioEngine`, `SpeechEngine`) own
  their own state and expose AsyncStreams; they aren't observable models.

---

## Concurrency

- **AsyncStream + `.task(id:)` over Combine.** New code shouldn't mix the two.
  Lifecycle: tie engines to `.task(id: state.runId)` so toggling a flag
  cancels the entire engine pipeline through structured concurrency.
- **Pair `withTaskGroup` with `withTaskCancellationHandler`** when you need
  cleanup on cancellation. The `onCancel` closure runs synchronously when
  the parent task is cancelled — perfect for `audio.stop()`/`speech.cancel()`.
- **Beware single-iterator AsyncStream.** Each `stream` exposes at most one
  iterator; once cancelled, a second consumer gets an immediately-finished
  stream. If a SwiftUI lifecycle modifier (e.g. `.translationTask`)
  restarts and tries to read again, recreate the stream. In Ben, the
  translator binds a fresh `AsyncStream` on every `.translationTask`
  activation.
- **Guard async callbacks against stale state.** Apple frameworks fire
  callbacks on background threads after you've moved on. Tag the callback's
  context (e.g. with the request instance it belongs to) and ignore stale
  invocations:
  ```swift
  recognizer.recognitionTask(with: req) { [weak self, weak req] result, error in
      guard let self, let req, self.currentRequest === req else { return }
      // …
  }
  ```
  Without this, the old task's error callback runs against the new task's
  state and you get bugs that look like "everything works for one cycle
  and then breaks".
- **`@MainActor` is correctness, not perf.** Put it on state and views (which
  already need it). Don't drag it onto engines or services that touch system
  APIs at audio-thread priority. Audio buffers come off the audio thread —
  serialize them via an AsyncStream and let consumers hop to `@MainActor` if
  needed.
- **Don't start unstructured `Task { … }` you can't track.** Use `.task(id:)`
  for view-tied work. Reach for unstructured `Task` only when the work must
  outlive the view, and store the handle so you can cancel it (e.g. Ben's
  `silenceWatchdog` is a `Task<Void, Never>?` so it can be cancelled when a
  new transcript arrives).

---

## View Composition

- **Extract a view the moment the type-checker complains.** Swift's "the
  compiler is unable to type-check this expression in reasonable time"
  error is your cue to split that screen-sized `body` into two smaller
  views. Bonus: the smaller views observe less and re-render less.
- **No `AnyView`.** If you're tempted to store a view in a property, return
  different view types from a function, or build a "routing" abstraction,
  use generics or `@ViewBuilder` instead. `AnyView` collapses structural
  identity, kills SwiftUI's diffing, and is almost always a sign of bad
  shape.
- **Compose pixel-tweaks with modifiers, layout with primitives.** Reach for
  `Layout` (or `GeometryReader` as a last resort) only when stack/grid
  can't express what you want. Most "I need GeometryReader" problems are
  solved by `containerRelativeFrame`, `onGeometryChange`, or `visualEffect`
  on macOS 14+.
- **Smaller views also help hot reloading & previews.** A 30-line view
  body previews in `#Preview` cheaply; a 300-line one needs an entire mock
  environment.

---

## Window & App Setup

- **`Info.plist` keys you'll forget:** `CFBundleIdentifier` (LaunchServices
  identity — keep it stable across rebuilds or you'll thrash permissions),
  `CFBundleExecutable` (must match the binary name in `Contents/MacOS/`),
  `CFBundlePackageType=APPL`, `LSMinimumSystemVersion`, `CFBundleIconFile`.
- **Privacy usage strings are required, not optional.** If you call any
  permission-gated API and your `Info.plist` is missing the matching
  `NS…UsageDescription`, the system silently denies. For mic + speech:
  `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`.
- **Pin a stable bundle ID for ad-hoc-signed builds.** Permission grants are
  keyed on the bundle ID. If your build script regenerates a random ID, the
  user gets a fresh permission prompt every launch.
- **Add commands to existing menus, don't create new top-level menus.**
  `CommandGroup(after: .sidebar) { … }` adds to the existing **View** menu.
  `CommandMenu("View") { … }` looks like it adds *to* the View menu, but
  in fact creates a second top-level "View" menu that macOS suppresses.
- **Bind Commands from an Observable model via `@Bindable`** at the App
  level. Commands aren't Views; they don't auto-subscribe to `@State`.
  Wrap your commands in a `Commands` struct that holds a `@Bindable`
  reference to the app state.

---

## Permissions & Code Signing

- **Ad-hoc signing works for local development**, with caveats:
  - Gatekeeper rejects ad-hoc-signed apps in `/Applications` and they
    disappear from Spotlight/Alfred/Cmd-Tab. Either keep the build under
    your home dir, or `sudo spctl --add /Applications/YourApp.app`.
  - Ad-hoc signed apps are eligible for entitlements via `--entitlements`,
    which is how you unlock e.g. `com.apple.security.device.audio-input`.
- **Code-sign every rebuild.** Re-signing is fast (`codesign --force --sign -
  --options runtime …`) and keeps LaunchServices happy. If you skip it after
  modifying `Contents/MacOS/<binary>`, the bundle's seal mismatches the
  manifest and macOS may refuse to launch with no obvious error.
- **Permissions are bundle-scoped, not user-scoped.** A change to bundle ID
  or executable name effectively gives you a "new app" — fresh permission
  prompts. Resist the urge to rename.
- **Quarantine ≠ Gatekeeper.** Apps downloaded from the internet get
  `com.apple.quarantine`; copies from your own machine usually don't.
  Gatekeeper still independently rejects ad-hoc signatures regardless.
  Diagnose with `spctl --assess --verbose path/to/App.app` — the verbose
  flag tells you *why* it was rejected.

---

## Logging & Diagnostics

- **Use `os.log` (`Logger`) for everything.** Free, fast, structured,
  privacy-aware, and tailable from the terminal:
  ```bash
  log stream --predicate 'subsystem == "com.your.app"' --style compact
  ```
  Avoid `print` — it goes nowhere on a released build and doesn't carry
  category/subsystem context.
- **Have an in-app log ring buffer** for the times you can't keep a terminal
  handy. The DebugPane in Ben is a `@Observable` `[Entry]` capped at 400,
  also forwarding every line to `Logger`. Users debugging on their own
  machine can toggle it from a menu without leaving the app.
- **Surface errors to state, not just logs.** When something fails silently
  (translate prep failing, permission denied), set a visible field
  (`state.status = "translation not available — accept the download
  prompt"`). Users don't read logs; they read the UI.
- **Don't swallow recoverable errors.** When `SFSpeechRecognizer` reports
  "No speech detected" during a long pause, auto-restart the task. Logging
  the error and dying leaves the app silently broken in a way no user can
  recover from without a quit/relaunch.

---

## Apple Framework Gotchas

### `AVAudioEngine`

- The input format from `inputNode.outputFormat(forBus: 0)` is the
  *hardware* format. macOS mics are commonly 44.1 kHz or 48 kHz. Don't
  reformat unnecessarily — frameworks like Speech convert internally.
- To select an input device: `engine.inputNode.auAudioUnit.setDeviceID(id)`,
  but **before** `installTap` and `engine.start()`. Changing devices
  mid-run requires a full stop/configure/start cycle.
- The tap callback runs on an audio-thread; don't touch UI or actors there.
  Yield to an `AsyncStream` and consume on a `@MainActor` task.

### `SFSpeechRecognizer`

- **Dictation must be enabled** in System Settings → Keyboard → Dictation,
  or every recognition task errors with "Siri and Dictation are disabled".
  This catches everyone the first time.
- `supportsOnDeviceRecognition` is locale-specific. English is usually on
  device; smaller locales may fall back to the network without warning.
  Surface this in your debug log.
- `result.isFinal` rarely fires on its own in continuous-listen mode.
  Implement a silence-watchdog timer that calls `request.endAudio()` after
  a quiet period to force a final. Otherwise the "active" line just grows
  forever.
- Old recognition-task callbacks fire **after** you cancel the task and
  start a new one. See the stale-callback guard pattern above.

### Translation framework (macOS 15+)

- `TranslationSession` is delivered via `.translationTask(_:perform:)`. The
  body runs once per configuration; changing the config restarts it.
- **Call `try await session.prepareTranslation()` first.** It triggers the
  download sheet for the language pair if missing. Without it, `translate(_)`
  fails silently when the pair isn't installed.
- The session is meant to be SwiftUI-scoped. For non-view code that needs
  translations, hold an `AsyncStream` of request objects bound to AppState
  at activation time; the body iterates the stream and writes results back.
  Don't try to expose `TranslationSession` outside the closure.
- Translation latency varies (50–500 ms). For commit semantics where source
  and translation must match, use a request/response pattern with awaitable
  completions — don't trust whichever async result happens to land last.

---

## Build & Distribution

- **Use Swift Package Manager for the build, even for an app bundle.** SPM
  produces a binary; a tiny `build.sh` wraps it in `App.app/Contents/{MacOS,
  Resources}/` with `Info.plist`. You avoid the entire `.xcodeproj` /
  `.pbxproj` mess for personal-scale projects.
- **Set `swiftLanguageMode(.v5)` if you're hitting strict-concurrency rage.**
  Swift 6's strict concurrency is great for new code but disastrous when
  integrating older frameworks (`AVAudioPCMBuffer` isn't Sendable, etc.).
  Drop to `.v5` per-target; opt in later.
- **Generate icons from Swift.** A 100-line script with Core Graphics
  produces all 10 `.iconset` sizes and pipes to `iconutil`. Beats opening
  Sketch or maintaining a `.icns` source.
- **Ship a `.gitignore` that excludes `.build/`, `.swiftpm/`,
  `*.iconset/`, and the built `.app/`.** Each can be regenerated; they
  bloat the repo and confuse diffs.

---

## When to Reach for UIKit/AppKit

- SwiftUI doesn't have everything. `NSSavePanel`, `NSOpenPanel`, and a few
  audio/video controls are still AppKit-only. Wrap them at a leaf, behind a
  SwiftUI-shaped API, so the rest of the app doesn't learn about it.
- Don't reach for `NSViewRepresentable` for a control SwiftUI *almost*
  has. Try the SwiftUI version first, measure its perf, fall back only
  when there's a concrete deficit.

---

## When Something Looks Haunted

- **State resetting unexpectedly** → identity bug. Check for `if`/`else`
  branches, `AnyView`, or conditional modifier order. SwiftUI tears down
  views with different structural identity.
- **Two-way binding desync** → check that you're using `Binding(get:set:)`
  consistently and not assigning to a stale `@State` from outside.
- **A change doesn't propagate** → `@State` of an `@Observable` class
  reads the class instance. Subviews receive it. Property mutations within
  re-render. But assigning a new instance to the `@State` doesn't update
  subviews already holding the old reference. Lift the new instance to a
  parent and use `.id(...)` to force a rebuild if you really need it.
- **An async callback corrupts state** → stale callback. Tag the callback's
  context and discard mismatches.
- **App vanished from Spotlight** → Gatekeeper rejected the ad-hoc signature.
  `spctl --assess --verbose` will confirm.

---

## Mantra

> Clear is better than clever. Ship the app.
