//// Terminal renderers for qrkit QR codes.

import gleam/list
import gleam/string
import qrkit

const quiet_zone = 4

/// Render the QR code using double-width full blocks.
pub fn to_string(qr: qrkit.QrCode) -> String {
  render(qr, dark: "██", light: "  ")
}

/// Render the QR code with inverted colours.
pub fn with_inverse(qr: qrkit.QrCode) -> String {
  render(qr, dark: "  ", light: "██")
}

/// Render the QR code using Unicode half blocks to halve the height.
pub fn to_string_compact(qr: qrkit.QrCode) -> String {
  let padded = pad_rows(qrkit.rows(qr))
  compact_lines(padded, [])
  |> string.join(with: "\n")
}

fn render(qr: qrkit.QrCode, dark dark: String, light light: String) -> String {
  let rows = pad_rows(qrkit.rows(qr))
  rows
  |> list.map(fn(row) { render_row(row, dark, light) })
  |> string.join(with: "\n")
}

fn pad_rows(rows: List(List(Bool))) -> List(List(Bool)) {
  let width = case rows {
    [first, ..] -> list.length(first)
    [] -> 0
  }
  let padded_row = list.repeat(False, width + quiet_zone * 2)
  let body =
    rows
    |> list.map(fn(row) {
      list.append(
        list.repeat(False, quiet_zone),
        list.append(row, list.repeat(False, quiet_zone)),
      )
    })
  list.append(
    list.repeat(padded_row, quiet_zone),
    list.append(body, list.repeat(padded_row, quiet_zone)),
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
