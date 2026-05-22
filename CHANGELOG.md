# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Added

- `qrkit/render/png` now exposes the same options-builder shape as `qrkit/render/svg` and `qrkit/render/ascii`: `default_options()`, `with_module_size`, `with_margin`, `with_dark_color`, `with_light_color`, `with_background`, and `to_bit_array_with(qr, options)`. The existing `to_bit_array(qr, scale:, margin:)` is preserved as a thin wrapper over the new path. Colour fields accept `#rgb`, `#rrggbb`, and `#rrggbbaa` strings (the alpha component is read but currently honoured only via the `with_background(False)` toggle, which marks the light palette entry transparent through a `tRNS` chunk); unparseable strings keep the previous value rather than failing the call, mirroring the SVG renderer's lenient parsing. Closes the parity gap left by #8. (#28)

## [0.3.0] - 2026-05-21

### Fixed

- README: the Sponsor QR image now uses an absolute `raw.githubusercontent.com` URL instead of the relative `docs/images/sponsor-qr.png` path so it renders both on GitHub and on the Hex package page (relative paths in the README cannot be resolved against the published package archive, which omits the `docs/images/` directory). (#23)
- `DataExceedsCapacity(bits_needed, bits_available)` now carries informative non-zero fields in the Micro QR `find_version`, rMQR `find_version`, and Standard `encode_split` bailout paths. The three "no symbol in this family fits" code paths previously returned `DataExceedsCapacity(0, 0)`, undermining the error type's documented purpose of telling callers how far over the ceiling their payload is; they now report the encoded-bit count vs the largest symbol's capacity (M4, R17×139, and 16 shards × max-version respectively), matching the Standard QR path's existing behaviour. (#22)
- `qrkit/content.email` now keeps the addr-spec `@` separator (and the RFC 6068 §2 `some-delims` set: `!`, `$`, `'`, `(`, `)`, `*`, `+`, `;`, `:`, `,`) literal in the `to` field instead of percent-encoding everything via `uri.percent_encode`. The `to` field gets a narrower encoder that only escapes characters that would actually break URI parsing in this position (space, `?`, `&`, `#`, `<`, `>`, control bytes, non-ASCII); `subject` / `body` keep the wider RFC 3986 encoding. The previous behaviour produced `mailto:user%40example.com?...`, breaking canonical-form matching in some Android QR-handler whitelists. (#21)

## [0.2.0] - 2026-05-18

### Added

- `qrkit/render/ascii`: `AsciiOptions` opaque type plus `default_options/0`, `with_margin/2`, `with_inverse_option/2`, `to_string_with/2`, and `to_string_compact_with/2` — mirroring the builder-style options shape `qrkit/render/svg` already exposes (`svg.default_options |> svg.with_margin(2)`). The new functions let terminal callers tighten the quiet zone for debug dumps, fixture diffs, and inline-doc panels without giving up the ISO/IEC 18004 4-module default for camera-scannable output. Existing `to_string/1`, `with_inverse/1`, and `to_string_compact/1` keep the 4-module default and are unchanged at the API level. (#8)

### Fixed

- `qrkit/content`: comprehensive RFC compliance pass for the iCalendar and vCard renderers (issues #9–#17).
  - `vcard_to_string` and `event_to_string` now terminate lines with CRLF (`\r\n`) per RFC 5545 §3.1 / RFC 2426 §2.1, not LF-only — strict consumers (Apple iOS Calendar in MIME contexts, Outlook drag-and-drop, `python-icalendar`, `node-vcard`) accept the output. (#12)
  - Both renderers fold long content lines at 75 octets with `CRLF<space>` continuation per RFC 5545 §3.1 / RFC 2426 §2.6. Folding is grapheme-aware so multi-byte UTF-8 sequences are never split. (#13)
  - `escape_ical` / `escape_vcard` strip raw `\r` and `NUL` from TEXT values (RFC 5545 §3.3.11 / RFC 2426 §2.4.2 forbid raw control characters; CR in particular emulated CRLF and broke the document). (#11)
  - `event_to_string` now emits the RFC-required `PRODID` (VCALENDAR §3.7.3), `UID`, and `DTSTAMP` (VEVENT §3.6.1). `UID` is a deterministic synthesis of the event's title hash + start + end so the same event produces the same UID across runs; `DTSTAMP` defaults to `start_unix` since no clock is available in a pure rendering function. (#14)
  - `vcard_to_string` always emits the RFC 2426 MANDATORY `N` and `FN` properties (§3.1.1 / §3.1.2) — when the caller did not call `with_name`, both are emitted with empty values (`N:;;;;` and `FN:`) so the structure is still spec-conformant. (#15)
  - `event_to_string` in `all_day` mode now bumps `DTEND` to `start + 1 day` when the caller passed `end_unix == start_unix`, matching RFC 5545 §3.6.1's non-inclusive-end requirement for DATE-valued events. (#16)
  - `event_to_string` handles pre-epoch `unix` values correctly by floor-dividing into days / seconds-of-day (Gleam's `/` and `%` truncate toward zero, which had let negative sub-day components leak into the formatted output). (#9)
  - `event_to_string` clamps year to `[1, 9999]` so values beyond Y10K cannot break the RFC 5545 fixed-width `YYYYMMDDTHHMMSSZ` format. (#10)
  - Final BEGIN/END boundary line is now terminated with CRLF (RFC 5545 §3.1 / RFC 2426 §2.1 require *every* content line — including the last — to end with CRLF).
  - `content.email` now percent-encodes the `to` addr-spec along with `subject` and `body`, so reserved characters (`?`, `&`, `#`, space) in `to` no longer produce a malformed `mailto:` URI. (#17)

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
