# Upstream review log

This file records which public Keyboop source tags have been reviewed for the personal build.
The app never downloads or installs upstream binaries.

## v0.4.1 — baseline

- Source commit: `321d56238b8710a85f4c4812a3759fffce45868a`
- Accepted: upstream source used as the initial personal-build baseline.
- Personal changes: native scrollbar behavior, wrapping and “What’s new” layout, mode-selector
  background pill, display-scoped menu-bar alignment, and the read-only release monitor.
- Upstream binary used: no.

## v0.4.10 — merged on `port/upstream-0.4.10` (2026-11-06)

- Source commit: `fb9bdde4eb8f13a486974cf102a8bec9d607e5d2` (tag `v0.4.10`), merged into `personal/main`.
- Unlike step 3 of the procedure below, the whole tag was merged, then unwanted features were
  switched off at their entry points with `ReleaseFeatures` flags. Their code stays in the tree,
  so future upstream merges stay clean.
- Upstream binary used: no.

### Accepted

- Engine, dictation and layout-detection fixes (Engine, EventTap, LayoutDetector, TypoFix,
  TextReplacer, VoiceController, VoiceDictionary, WhisperBridge/WhisperPrompt, Parakeet `String?`
  failure result, unload-after-dictation, VoiceOutputCase, DoubleSpacePeriod, NumericTypoRule,
  InputLatency, LayoutCycle and others).
- Secure-input fixes: SecureInputProbe, SecureInputPolicy, RivalTapWatch.
- Persistent 🌐 guard: `PersistentResourceGuard.start()` at launch, ResourceGuard/Protocol,
  GlobeGuard `finishNormally()` at termination.
- Single-instance lock now fails closed: `O_CLOEXEC | O_NOFOLLOW`, mode 0600, and a `flock` errno
  check. Comments rewritten without Sparkle.
- `build-app.sh` safety: canonical build target, exact-path process classifier, and a final
  blocking-process check before the bundle is replaced. `-framework IOKit` added.
- FeedbackWindow width fix (`syncTextWidth`, `autoresizingMask = []`). It replaces the personal
  fix, so the duplicate personal code was dropped.
- ModePicker (UIControls): upstream `inkColor` layering plus the blurred halo. Its `inkColor(0.07)`
  over the window color is the same opaque blend as the personal `opaqueTrackInk`, which was
  removed.
- Menu bar: upstream's 18 pt brand-mark canvas and its 0.5 pt flag drop.

### Kept personal (conflict resolutions)

- `UpdaterController.swift`: personal version as-is (read-only release monitor, no Sparkle, no
  auto-install).
- `build-app.sh`: personal for both hunks (arm64-only, no Sparkle/universal pass, “Keyboop Personal”
  `ru.keyboop.app.personal`, personal signing). Version and `KeyboopUpstreamBaselineVersion` set
  to 0.4.10. `NSAudioCaptureUsageDescription` dropped.
- `SettingsWindow.swift`: native scrollbar behavior kept (`autohidesScrollers` only). Upstream's
  forced `.legacy` scroller style was rejected.
- `MenuBarController.swift`: display-scoped alignment kept and combined with upstream's numbers.
  `.original` (macOS 26 or a notched screen) now matches upstream exactly: no brand-mark drop,
  0.5 pt flag drop, no title baseline shift. `.preLiquidGlassNotchless` (macOS < 26, no notch)
  keeps the personal values: 0.5 pt image drop and −1 pt title baseline. **To verify:** the
  0.5 pt brand-mark value was measured on the old 15 pt mark. It needs a fresh live-menu-bar
  screenshot on the M1 Air with upstream's 18 pt canvas.
- FluidAudio: `ModelHub.offlineMode` everywhere. Upstream's `DownloadUtils.enforceOffline`
  (ParakeetEngine, StreamingEouEngine) does not appear in the merged tree. WhisperBridge does not
  use it.

### Rejected (switched off in `ReleaseFeatures`)

- `callRecorder`: hidden ⌥-click call recording (system audio + mic). The menu-bar ⌥-click,
  `onToggleCallRecording` wiring and launch-time `recoverUnfinishedSessions()` are gated.
- `clipboardHistory`: clipboard capture into history. `clipboardHistoryEnabled` always reads
  false, `ClipboardWatcher.apply()` is not called at launch, and the settings section is hidden.
- `audioImport`: audio-file import into history. The import button is hidden, drag-and-drop is
  rejected (`AudioDrop.url` → nil, no `onDrop`), and `canImport()` returns false.
- `feedbackAttachments`: screenshot/video upload to `keyboop.com/api/feedback/attachment`. The
  attach row is hidden, the chooser is a no-op, and no attachment is declared on send. Text
  feedback still goes to `keyboop.com/api/feedback`, as before.
- Slap: already off via `ReleaseFeatures.slap`.
- Sparkle, universal/x86_64 build, `LSMinimumSystemVersionByArchitecture`, upstream bundle ID.

### Build check

- Compiled and linked arm64 with the Xcode toolchain (`-target arm64-apple-macos14.0`).
- The only FluidAudio prebuilt available locally was upstream's older build (`DownloadUtils` API).
  So the check used a throwaway shim, outside the repo, that maps `ModelHub.offlineMode` to it.
  Apart from those `ModelHub` symbol errors, the merged sources compile cleanly.
- Not done here: a signed `build-app.sh` run against the personal FluidAudio prebuilt and personal
  signing keychain, and a live launch.

## Review procedure

1. Fetch the exact public tag; do not review an untagged binary announcement.
2. Compare `v<current baseline>...v<new version>` and inspect permissions, network access,
   dependencies, input handling, and the complete changelog.
3. Merge the whole tag only when all changes are accepted. Otherwise port selected changes manually;
   upstream release commits commonly contain several features at once.
4. Build and test locally, record accepted/rejected changes here, then update
   `KeyboopUpstreamBaselineVersion` and the app version in `build-app.sh`.
