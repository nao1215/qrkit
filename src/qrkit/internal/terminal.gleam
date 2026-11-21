//// Terminal renderers: double-width full blocks, or half blocks that put two
//// module rows in one line of text.

import gleam/list
import gleam/string
import qrkit/internal/util

/// Render each module as `dark` or `light`, one line per module row, inside
/// a light quiet zone of `margin` modules.
pub fn blocks(
  rows: List(List(Bool)),
  margin margin: Int,
  dark dark: String,
  light light: String,
) -> String {
  util.pad_rows(rows, margin)
  |> list.map(fn(row) { render_row(row, dark, light) })
  |> string.join(with: "\n")
}

/// Render two module rows per line with the half block characters, inside a
/// light quiet zone of `margin` modules.
pub fn half_blocks(rows: List(List(Bool)), margin margin: Int) -> String {
  util.pad_rows(rows, margin)
  |> compact_lines([])
  |> string.join(with: "\n")
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
