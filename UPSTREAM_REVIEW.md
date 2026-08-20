# Upstream review log

This file records which public Keyboop source tags have been reviewed for the personal build.
The app never downloads or installs upstream binaries.

## v0.4.1 — baseline

- Source commit: `321d56238b8710a85f4c4812a3759fffce45868a`
- Accepted: upstream source used as the initial personal-build baseline.
- Personal changes: native scrollbar behavior, wrapping and “What’s new” layout, mode-selector
  background pill, display-scoped menu-bar alignment, and the read-only release monitor.
- Upstream binary used: no.

## Review procedure

1. Fetch the exact public tag; do not review an untagged binary announcement.
2. Compare `v<current baseline>...v<new version>` and inspect permissions, network access,
   dependencies, input handling, and the complete changelog.
3. Merge the whole tag only when all changes are accepted. Otherwise port selected changes manually;
   upstream release commits commonly contain several features at once.
4. Build and test locally, record accepted/rejected changes here, then update
   `KeyboopUpstreamBaselineVersion` and the app version in `build-app.sh`.
