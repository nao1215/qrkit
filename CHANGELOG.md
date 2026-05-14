# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

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
