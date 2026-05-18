# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Added

- `qrkit/render/ascii`: `AsciiOptions` opaque type plus `default_options/0`, `with_margin/2`, `with_inverse_option/2`, `to_string_with/2`, and `to_string_compact_with/2` — mirroring the builder-style options shape `qrkit/render/svg` already exposes (`svg.default_options |> svg.with_margin(2)`). The new functions let terminal callers tighten the quiet zone for debug dumps, fixture diffs, and inline-doc panels without giving up the ISO/IEC 18004 4-module default for camera-scannable output. Existing `to_string/1`, `with_inverse/1`, and `to_string_compact/1` keep the 4-module default and are unchanged at the API level. (#8)

## [0.1.0] - 2026-05-14

### Changed

- `package_version_test` now reads `gleam.toml` at test time and asserts
  that `qrkit.package_version` returns the version pinned there. Releases
  that bump only `gleam.toml` without `src/qrkit.gleam`'s constant
  (or vice versa) now fail CI instead of shipping a runtime-visible
  version that disagrees with Hex metadata. `CONTRIBUTING.md`'s release
  checklist was updated to call this out. (#2)

- `qrkit/content` now escapes vCard / iCalendar text fields consistently
  and uses proper URI percent-encoding for `mailto:` query parameters, so
  reserved characters in user data no longer produce malformed payloads.
  (#1)

- `qrkit.with_exact_version/2` is now the preferred public API for exact
  version pinning. `qrkit.with_min_version/2` remains available as a
  compatibility alias, but its documentation now explicitly states that it
  pins the version exactly rather than setting a lower bound. (#4)

- **Breaking**: `qrkit.module_at/3` now returns
  `Result(Bool, qrkit.MatrixAccessError)` instead of silently treating
  out-of-bounds coordinates as light modules. Builder ECI validation is now
  explicit as well: invalid designators return
  `Error(InvalidEciDesignator(..))`, and non-Standard symbols reject ECI
  with `Error(IncompatibleOptions(..))`. SVG option setters now normalize
  invalid dimensions the same way the PNG renderer already did. (#3)

### Initial

- Bootstrap the repository as a Gleam package with CI, release
  automation, and baseline QR Code primitives.
