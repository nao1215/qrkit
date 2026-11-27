# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Added

- `doc/interop.md` records how often zxing-cpp and zbar read random symbols qrkit writes and how often qrkit reads segno's, and pull requests now run a small corpus of it. zbar misreads about 30% of non-ASCII Byte data without an ECI as Shift JIS; `eci: Some(26)` avoids this.
- Mutation testing (`dev/mutation.gleam`, built on glance) runs on the modules a pull request changes and weekly on every module, and fails on a survivor that `doc/mutation/baseline.json` does not list.
- Tests for the address part of `email` with 2-, 3- and 4-byte UTF-8, version information against segno, ECI designators of every length, kanji on the edges of both Shift JIS ranges, vCard lines of 75 and 76 octets, and a PNG checked with Python's zlib. `test/fixtures/segno_symbols.tsv` holds segno symbols with each mask, each mode at versions 9, 10, 26 and 27, and 143 Byte symbols without an ECI in Shift JIS, Latin-1 or UTF-8, which qrkit must read as zxing-cpp does.
- Figures drawn by qrkit itself in the README and in the docs of `Symbol` and `ErrorCorrection`.

## [0.8.1] - 2026-11-23

### Fixed

- Standard QR mask selection now scores the 1:1:3:1:1 pattern with the quiet zone counted as light and each occurrence counted once, and scores the dark-module proportion from the exact percentage (45.1% dark used to cost 10 points). The chosen mask now matches zxing's rules: 470 of 470 single-mode symbols in a random corpus are identical to zxing-cpp's encoder, against 227 before. Symbols still decode the same, but their modules and `mask` can change.
- Micro QR mask selection read one module instead of the bottom row, so it often kept a worse mask than ISO/IEC 18004 §7.8.3.2 asks for. The masks now match segno and zxing-cpp.
- With `eci: Some(26)` (UTF-8), kanji are written as UTF-8 Byte data. zxing-cpp read Kanji segments after ECI 26 as garbage, because readers decode Kanji mode with the ECI's character set. This can need a larger version.

## [0.8.0] - 2026-11-22

### Changed

- Breaking: the whole API is now in the `qrkit` module. `qrkit/types`, `qrkit/error`, `qrkit/decode`, `qrkit/content` and `qrkit/render/ascii`, `png` and `svg` are removed, and so are the type aliases that re-exported their types.
- Breaking: `QrCode`, `Decoded`, `VCard` and `CalendarEvent` are plain records and the render options are one `ImageOptions` record, so their getters and `with_*` setters are removed. Read fields directly and update `default_encode_options()` or `default_image_options()` with the record update syntax.
- Breaking: `new`, `with_*` and `build` are replaced by `encode_with(text, EncodeOptions)`. `encode_split` takes labelled `max_version` and `error_correction` arguments and replaces `encode_split_with`.
- Breaking: rendering is `to_terminal(qr, style:, margin:)` with `Blocks`, `InvertedBlocks` or `HalfBlocks`, and `to_svg` and `to_png` with `ImageOptions`. `light_color: None` gives a transparent background. The default SVG dark colour is now `#000000`, the same as PNG.
- Breaking: `IncompatibleOptions(reason)` is replaced by `ErrorCorrectionNotSupported(symbol, error_correction)` and `EciNotSupported(symbol)`. A pinned Micro QR version that cannot hold a character returns `UnsupportedCharacter(at_index, character)`. A rectangular priority on a non-rMQR symbol is ignored instead of rejected.
- Breaking: `MalformedData` no longer carries a reason string.
- Breaking: `WifiSecurity` variants carry the password, so `wifi` no longer takes one for `Open`. Calendar events take `Timed(start, end)` with `gleam/time` timestamps or `AllDay(first, last)` with dates, where `last` is included. `gleam_time` is a new dependency.
- Breaking: `package_version`, `module_at`, `MatrixAccessError`, `error_correction_designator` and `content.url` are removed.
- The minimum `gleam_stdlib` version is now 0.69.0 (was 0.66.0, which was never published), the first release with `int.range`.
- Encoding a large symbol is about 2.5 times faster and PNG output about 6 times faster.

A 0.7.0 program such as

```gleam
qrkit.new("12345")
|> qrkit.with_symbol(types.Micro)
|> qrkit.with_ecc(types.Low)
|> qrkit.build
|> result.map(svg.to_string)
```

is now

```gleam
qrkit.encode_with(
  "12345",
  qrkit.EncodeOptions(
    ..qrkit.default_encode_options(),
    symbol: qrkit.Micro,
    error_correction: qrkit.Low,
  ),
)
|> result.map(qrkit.to_svg(_, qrkit.default_image_options()))
```

### Fixed

- `geo` wrote very small or large coordinates in exponent notation (`geo:1.0e-7,...`). It now writes plain decimals.
- Folded vCard and iCalendar continuation lines were 76 octets long. They are now at most 75, including the leading space.
- A calendar time outside years 1..9999 kept its month and day when the year was clamped. It is now clamped to the first or last second of that range.

- Decoding overflowed the JavaScript stack on a long Numeric or Alphanumeric segment, such as a version 40 symbol of 7089 digits. It now reads them on both targets.

## [0.7.0] - 2026-11-19

### Removed

- Breaking: `qrkit.with_min_version`, an alias of `with_exact_version` whose name suggested a lower bound; call `with_exact_version`.
- Breaking: `qrkit.size` and `qrkit.symbol_size`, which repeated `qrkit.width` and `qrkit.height` (`size` returned only the width of an rMQR symbol).
- Breaking: the `qrkit.Mode` alias. No function takes or returns `types.Mode`, which is now internal.

### Fixed

- `decode.from_rows` did not read an rMQR symbol turned by 90 or 270 degrees or mirrored on its diagonal, that is a grid taller than it is wide, and returned `NotASymbol`. A taller grid is now transposed before the four flips are tried.

### Changed

- GitHub Releases now attach the Hex package tarball, `checksums.txt`, a keyless cosign signature bundle for it and build provenance (`*.intoto.jsonl`). See "Verifying releases" in the README.

## [0.6.0] - 2026-09-29

### Added

- `qrkit/decode` reads Standard QR, Micro QR and rMQR symbols from rows of modules (`decode.from_rows(qrkit.rows(qr))`), with Reed-Solomon error correction (Berlekamp-Massey, Chien search, Forney). It removes a light quiet zone, reads rotated and mirrored symbols, and parses Numeric, Alphanumeric, Byte, Kanji, ECI, Structured Append and FNC1. Byte data follows its ECI; without one it is read as UTF-8, Shift JIS or ISO-8859-1 by zxing's rules. `decode.text`, `symbol`, `version`, `error_correction`, `mask`, `errors_corrected`, `eci` and `structured_append` report what was read; failures are `qrkit/error.DecodeError` (`NotASymbol`, `UnreadableFormatInformation`, `TooManyErrors`, `MalformedData`).
- `qrkit.with_rectangular_priority` chooses how `build` picks among the rMQR sizes that hold the payload: `types.SmallestArea`, `types.ShortestHeight` or `types.NarrowestWidth`. Setting it for Standard QR or Micro QR returns `Error(IncompatibleOptions)`.
- `svg.to_string_with(qr, options)` renders with explicit options. (#31)

### Fixed

- rMQR symbols whose error correction ISO/IEC 23941 Table 8 splits into several Reed-Solomon blocks were encoded with a single block over all data codewords, so readers could not decode them: 35 of the 64 version and level pairs (R7x139-H, R9x139-M, R17x139-M and every larger or H-level size with more than one block). Each block now gets its own error correction and the blocks are interleaved as the standard requires. Checked against zxing-cpp and shogo82148/qrcode.
- Standard QR rejected payloads that fit version 10 or later with `DataExceedsCapacity`, for example `string.repeat("abc123456", 30)` at Low, which fits version 10. Segment headers were counted with the character-count widths of versions 1-9 and then encoded with the wider ones of the chosen version. Each version range (1-9, 10-26, 27-40) is now segmented and measured with its own widths.
- Micro QR and rMQR never used Kanji mode, so kana cost 24 bits per character in Byte mode instead of 13; `"カタカナ"` now fits Micro QR M3 at Medium instead of M4, and fits M4 at Quartile instead of being rejected.

- Micro QR M1, M3-L and M3-M symbols whose last, 4-bit data codeword was padding carried a codeword error from the start: the error correction was computed over a full 0xEC pad byte while the symbol holds only its first four bits. Readers corrected it silently, but one more damaged module made the symbol unreadable. The half codeword is now padded with 0000 as ISO/IEC 18004 7.4.10 requires, and the modules match segno's.

### Changed

- Breaking: `svg.to_string(qr)` renders with `svg.default_options()`, matching `ascii.to_string`; code that passed options calls `svg.to_string_with(qr, options)`. (#31)
- rMQR picks the size with the fewest modules when no exact version is set (`types.SmallestArea`), instead of the lowest one. For example, `"01234567"` at Medium is now R11x27 (297 modules) instead of R7x43 (301). `qrkit.with_rectangular_priority(types.ShortestHeight)` keeps the previous choice.
- Kanji mode covers all 6,879 characters of JIS X 0208 instead of kana, full-width alphanumerics and four punctuation marks, so a kanji takes 13 bits instead of 24 in Byte mode. The table is generated from the WHATWG jis0208 index by `scripts/gen_kanji_table.py`.
- Standard QR, Micro QR and rMQR split the payload into the Numeric, Alphanumeric, Byte and Kanji segments with the fewest bits (ISO/IEC 18004 Annex J) instead of a greedy split for Standard QR and a single mode for Micro QR and rMQR. A symbol is never larger than before, and mixed payloads such as a URL ending in a long number often fit a smaller version. The modules of a symbol can differ from earlier releases for the same input.

## [0.5.0] - 2026-09-10

### Changed

- The minimum Gleam version is now 1.14.0 (was 1.15.0). 1.14.0 builds and tests the package unchanged on both targets, and `gleam_stdlib` 1.0 already requires it. CI tests that floor alongside the latest Gleam 1.x.

## [0.4.0] - 2026-05-22

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
