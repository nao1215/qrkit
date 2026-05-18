//// Terminal renderers for qrkit QR codes.
////
//// Default callers use [`to_string`](#to_string),
//// [`with_inverse`](#with_inverse), and
//// [`to_string_compact`](#to_string_compact) which keep the
//// ISO/IEC 18004 4-module quiet zone. Callers that need a tighter
//// margin (debug dumps, fixture diffs, README terminal panels)
//// build an [`AsciiOptions`](#AsciiOptions) via
//// [`default_options`](#default_options) /
//// [`with_margin`](#with_margin) / [`with_inverse_option`](#with_inverse_option)
//// and render through [`to_string_with`](#to_string_with) or
//// [`to_string_compact_with`](#to_string_compact_with).

import gleam/list
import gleam/string
import qrkit

const default_quiet_zone = 4

/// Render options for the terminal renderers. Build with
/// [`default_options`](#default_options) and the `with_*` setters.
/// `pub opaque` so the renderer can grow knobs (background colour,
/// glyph set, ...) without breaking callers.
pub opaque type AsciiOptions {
  AsciiOptions(margin: Int, inverse: Bool)
}

/// Default rendering options: 4-module quiet zone (ISO/IEC 18004),
/// non-inverted colours.
pub fn default_options() -> AsciiOptions {
  AsciiOptions(margin: default_quiet_zone, inverse: False)
}

/// Override the quiet zone in modules. Values below 0 are clamped
/// to 0. The 4-module default is the ISO/IEC 18004 minimum for
/// reliable scannability — tightening it is appropriate for
/// debug / fixture / inline-doc output, not for QR codes intended
/// to be scanned from a camera.
pub fn with_margin(options: AsciiOptions, modules: Int) -> AsciiOptions {
  let AsciiOptions(_, inverse) = options
  let clamped = case modules < 0 {
    True -> 0
    False -> modules
  }
  AsciiOptions(margin: clamped, inverse: inverse)
}

/// Toggle inverted rendering (dark cells render as spaces, light
/// cells as blocks).
pub fn with_inverse_option(options: AsciiOptions, inverse: Bool) -> AsciiOptions {
  let AsciiOptions(margin, _) = options
  AsciiOptions(margin: margin, inverse: inverse)
}

/// Render the QR code using double-width full blocks. Uses the
/// ISO/IEC 18004 default 4-module quiet zone. See
/// [`to_string_with`](#to_string_with) when a different margin is
/// needed.
pub fn to_string(qr: qrkit.QrCode) -> String {
  render(qr, dark: "██", light: "  ", margin: default_quiet_zone)
}

/// Render the QR code with inverted colours and the default
/// 4-module quiet zone.
pub fn with_inverse(qr: qrkit.QrCode) -> String {
  render(qr, dark: "  ", light: "██", margin: default_quiet_zone)
}

/// Render using double-width full blocks with caller-supplied
/// [`AsciiOptions`](#AsciiOptions). The `inverse` setting on the
/// options flips dark / light glyphs identically to
/// [`with_inverse`](#with_inverse).
pub fn to_string_with(qr: qrkit.QrCode, options: AsciiOptions) -> String {
  let AsciiOptions(margin, inverse) = options
  case inverse {
    True -> render(qr, dark: "  ", light: "██", margin: margin)
    False -> render(qr, dark: "██", light: "  ", margin: margin)
  }
}

/// Render the QR code using Unicode half blocks to halve the height,
/// keeping the default 4-module quiet zone. See
/// [`to_string_compact_with`](#to_string_compact_with) for a
/// caller-controlled margin.
pub fn to_string_compact(qr: qrkit.QrCode) -> String {
  let padded = pad_rows(qrkit.rows(qr), default_quiet_zone)
  compact_lines(padded, [])
  |> string.join(with: "\n")
}

/// Render the QR code using Unicode half blocks with a caller-
/// supplied margin. The `inverse` setting on
/// [`AsciiOptions`](#AsciiOptions) is currently ignored for the
/// half-block renderer — the compact form's glyph set already
/// encodes both top and bottom modules per character cell.
pub fn to_string_compact_with(qr: qrkit.QrCode, options: AsciiOptions) -> String {
  let AsciiOptions(margin, _inverse) = options
  let padded = pad_rows(qrkit.rows(qr), margin)
  compact_lines(padded, [])
  |> string.join(with: "\n")
}

fn render(
  qr: qrkit.QrCode,
  dark dark: String,
  light light: String,
  margin margin: Int,
) -> String {
  let rows = pad_rows(qrkit.rows(qr), margin)
  rows
  |> list.map(fn(row) { render_row(row, dark, light) })
  |> string.join(with: "\n")
}

fn pad_rows(rows: List(List(Bool)), margin: Int) -> List(List(Bool)) {
  let width = case rows {
    [first, ..] -> list.length(first)
    [] -> 0
  }
  let padded_row = list.repeat(False, width + margin * 2)
  let body =
    rows
    |> list.map(fn(row) {
      list.append(
        list.repeat(False, margin),
        list.append(row, list.repeat(False, margin)),
      )
    })
  list.append(
    list.repeat(padded_row, margin),
    list.append(body, list.repeat(padded_row, margin)),
  )
}

fn render_row(row: List(Bool), dark: String, light: String) -> String {
  row
  |> list.map(fn(value) {
    case value {
      True -> dark
      False -> light
    }
  })
  |> string.join(with: "")
}

fn compact_lines(rows: List(List(Bool)), acc: List(String)) -> List(String) {
  case rows {
    [top, bottom, ..rest] ->
      compact_lines(rest, [compact_row(top, bottom), ..acc])
    [top] ->
      compact_lines([], [
        compact_row(top, list.repeat(False, list.length(top))),
        ..acc
      ])
    [] -> list.reverse(acc)
  }
}

fn compact_row(top: List(Bool), bottom: List(Bool)) -> String {
  list.map2(top, bottom, fn(top_value, bottom_value) {
    case top_value, bottom_value {
      True, True -> "█"
      True, False -> "▀"
      False, True -> "▄"
      False, False -> " "
    }
  })
  |> string.join(with: "")
}
