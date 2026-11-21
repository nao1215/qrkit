//// SVG renderer.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Render `rows` as an SVG document: `module_size` px per module, a quiet
/// zone of `margin` modules, dark modules filled with `dark_color`, and a
/// background rectangle in `light_color` unless it is `None`. The width is
/// taken from the first row.
pub fn render(
  rows: List(List(Bool)),
  module_size module_size: Int,
  margin margin: Int,
  dark_color dark_color: String,
  light_color light_color: Option(String),
) -> String {
  let width = case rows {
    [first, ..] -> list.length(first)
    [] -> 0
  }
  let total_width = { width + margin * 2 } * module_size
  let total_height = { list.length(rows) + margin * 2 } * module_size
  let background_tag = case light_color {
    Some(light_color) ->
      "<rect width=\""
      <> int.to_string(total_width)
      <> "\" height=\""
      <> int.to_string(total_height)
      <> "\" fill=\""
      <> escape_attribute(light_color)
      <> "\"/>"
    None -> ""
  }
  let path_data = path_data(rows, module_size, margin, 0, [])
  "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 "
  <> int.to_string(total_width)
  <> " "
  <> int.to_string(total_height)
  <> "\" shape-rendering=\"crispEdges\">"
  <> background_tag
  <> "<path fill=\""
  <> escape_attribute(dark_color)
  <> "\" d=\""
  <> path_data
  <> "\"/></svg>"
}

/// Escape an attribute value to prevent breaking out of the surrounding
/// `"..."` quote pair when callers pass user-controlled CSS strings.
fn escape_attribute(value: String) -> String {
  value
  |> string.replace(each: "&", with: "&amp;")
  |> string.replace(each: "<", with: "&lt;")
  |> string.replace(each: ">", with: "&gt;")
  |> string.replace(each: "\"", with: "&quot;")
  |> string.replace(each: "'", with: "&#39;")
}

fn path_data(
  rows: List(List(Bool)),
  module_size: Int,
  margin: Int,
  row_index: Int,
  acc: List(String),
) -> String {
  case rows {
    [] -> acc |> list.reverse |> string.join(with: "")
    [row, ..rest] ->
      path_data(rest, module_size, margin, row_index + 1, [
        row_path(row, row_index, module_size, margin, 0, []),
        ..acc
      ])
  }
}

fn row_path(
  row: List(Bool),
  row_index: Int,
  module_size: Int,
  margin: Int,
  col_index: Int,
  acc: List(String),
) -> String {
  case row {
    [] -> acc |> list.reverse |> string.join(with: "")
    [True, ..rest] -> {
      let run = dark_run_length(rest, 1)
      let x = { col_index + margin } * module_size
      let y = { row_index + margin } * module_size
      let width = run * module_size
      let path =
        "M"
        <> int.to_string(x)
        <> " "
        <> int.to_string(y)
        <> "h"
        <> int.to_string(width)
        <> "v"
        <> int.to_string(module_size)
        <> "H"
        <> int.to_string(x)
        <> "z"
      row_path(
        list.drop(row, run),
        row_index,
        module_size,
        margin,
        col_index + run,
        [path, ..acc],
      )
    }
    [False, ..rest] ->
      row_path(rest, row_index, module_size, margin, col_index + 1, acc)
  }
}

fn dark_run_length(row: List(Bool), count: Int) -> Int {
  case row {
    [True, ..rest] -> dark_run_length(rest, count + 1)
    _ -> count
  }
}
