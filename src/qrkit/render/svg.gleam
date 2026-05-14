//// SVG renderer for qrkit QR codes.

import gleam/int
import gleam/list
import gleam/string
import qrkit

pub opaque type SvgOptions {
  SvgOptions(
    module_size: Int,
    margin: Int,
    dark_color: String,
    light_color: String,
    background: Bool,
  )
}

/// Default SVG rendering options.
pub fn default_options() -> SvgOptions {
  SvgOptions(8, 4, "#111111", "#ffffff", True)
}

/// Set the SVG module size.
pub fn with_module_size(options: SvgOptions, px: Int) -> SvgOptions {
  let SvgOptions(_, margin, dark_color, light_color, background) = options
  SvgOptions(px, margin, dark_color, light_color, background)
}

/// Set the quiet-zone margin in modules.
pub fn with_margin(options: SvgOptions, modules: Int) -> SvgOptions {
  let SvgOptions(module_size, _, dark_color, light_color, background) = options
  SvgOptions(module_size, modules, dark_color, light_color, background)
}

/// Set the dark module colour.
pub fn with_dark_color(options: SvgOptions, css_color: String) -> SvgOptions {
  let SvgOptions(module_size, margin, _, light_color, background) = options
  SvgOptions(module_size, margin, css_color, light_color, background)
}

/// Set the light/background colour.
pub fn with_light_color(options: SvgOptions, css_color: String) -> SvgOptions {
  let SvgOptions(module_size, margin, dark_color, _, background) = options
  SvgOptions(module_size, margin, dark_color, css_color, background)
}

/// Toggle the background rectangle.
pub fn with_background(options: SvgOptions, draw: Bool) -> SvgOptions {
  let SvgOptions(module_size, margin, dark_color, light_color, _) = options
  SvgOptions(module_size, margin, dark_color, light_color, draw)
}

/// Render a QR code as an SVG document string.
pub fn to_string(qr: qrkit.QrCode, options: SvgOptions) -> String {
  let SvgOptions(module_size, margin, dark_color, light_color, background) =
    options
  let total_width = { qrkit.width(qr) + margin * 2 } * module_size
  let total_height = { qrkit.height(qr) + margin * 2 } * module_size
  let background_tag = case background {
    True ->
      "<rect width=\""
      <> int.to_string(total_width)
      <> "\" height=\""
      <> int.to_string(total_height)
      <> "\" fill=\""
      <> escape_attribute(light_color)
      <> "\"/>"
    False -> ""
  }
  let path_data = path_data(qrkit.rows(qr), module_size, margin, 0, [])
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
