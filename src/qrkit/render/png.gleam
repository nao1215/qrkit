//// Pure Gleam PNG renderer for qrkit QR codes.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import qrkit

const png_signature = [137, 80, 78, 71, 13, 10, 26, 10]

const crc32_polynomial = 0xEDB88320

const adler32_modulus = 65_521

/// Rendering options for [`to_bit_array_with`](#to_bit_array_with).
///
/// Mirrors the shape of `qrkit/render/svg`'s `SvgOptions`. The
/// colour fields accept CSS-style hex strings (`#rgb`, `#rrggbb`, or
/// `#rrggbbaa`); unparseable values fall back to the default colour
/// rather than rejecting the call, so callers can keep the surface
/// non-fallible.
pub opaque type PngOptions {
  PngOptions(
    module_size: Int,
    margin: Int,
    dark_color: String,
    light_color: String,
    background: Bool,
  )
}

/// Default PNG rendering options: 8×8 px modules, 4-module quiet
/// zone, black on white, background on. Mirrors
/// [`qrkit/render/svg`](./svg.html)'s defaults.
pub fn default_options() -> PngOptions {
  PngOptions(8, 4, "#000000", "#ffffff", True)
}

/// Set the PNG module size in pixels.
///
/// Values less than 1 are normalised to 1 to keep the rendered
/// output usable.
pub fn with_module_size(options: PngOptions, px: Int) -> PngOptions {
  PngOptions(..options, module_size: positive_or(px, default: 1))
}

/// Set the quiet-zone margin in modules.
///
/// Negative values are normalised to 0.
pub fn with_margin(options: PngOptions, modules: Int) -> PngOptions {
  PngOptions(..options, margin: non_negative_or(modules, default: 0))
}

/// Set the dark module colour. Accepts `#rgb`, `#rrggbb`, or
/// `#rrggbbaa` — same syntax as the SVG renderer. Unparseable
/// strings keep the previous value rather than failing the call.
pub fn with_dark_color(options: PngOptions, css_color: String) -> PngOptions {
  PngOptions(..options, dark_color: css_color)
}

/// Set the light / background colour. Accepts the same hex syntax as
/// [`with_dark_color`](#with_dark_color).
pub fn with_light_color(options: PngOptions, css_color: String) -> PngOptions {
  PngOptions(..options, light_color: css_color)
}

/// Toggle whether the light/background pixels are drawn opaquely.
///
/// When `False`, the light palette entry is marked transparent via a
/// `tRNS` chunk so the QR code can be composited over an existing
/// background.
pub fn with_background(options: PngOptions, draw: Bool) -> PngOptions {
  PngOptions(..options, background: draw)
}

/// Render a QR code as PNG bytes using the options builder.
///
/// Equivalent to [`to_bit_array`](#to_bit_array) when called with
/// [`default_options`](#default_options) overridden only by
/// [`with_module_size`](#with_module_size) and
/// [`with_margin`](#with_margin); the colour and background knobs
/// add the surface not previously reachable through the positional
/// entry point.
pub fn to_bit_array_with(qr: qrkit.QrCode, options: PngOptions) -> BitArray {
  let PngOptions(module_size, margin, dark_color, light_color, background) =
    options
  let actual_scale = positive_or(module_size, default: 1)
  let actual_margin = non_negative_or(margin, default: 0)
  let pixels =
    qrkit.rows(qr)
    |> pad_rows(actual_margin)
    |> scale_rows(actual_scale)
  let width = pixels_width(pixels)
  let height = list.length(pixels)
  let image_data = scanlines(pixels, [])
  let ihdr =
    list.append(
      u32_bytes(width),
      list.append(u32_bytes(height), [1, 3, 0, 0, 0]),
    )
  let #(dr, dg, db) = parse_css_rgb(dark_color, default: #(0, 0, 0))
  let #(lr, lg, lb) = parse_css_rgb(light_color, default: #(255, 255, 255))
  let plte = [dr, dg, db, lr, lg, lb]
  let idat = zlib_store(image_data)
  // tRNS chunk: palette alpha. Index 0 (dark) stays opaque at 255;
  // index 1 (light) is made transparent when background == False.
  let trns_data = case background {
    True -> []
    False -> [255, 0]
  }
  let trns_chunk = case trns_data {
    [] -> []
    bytes -> chunk(type_bytes: [116, 82, 78, 83], data_bytes: bytes)
  }

  list.append(
    png_signature,
    list.append(
      chunk(type_bytes: [73, 72, 68, 82], data_bytes: ihdr),
      list.append(
        chunk(type_bytes: [80, 76, 84, 69], data_bytes: plte),
        list.append(
          trns_chunk,
          list.append(
            chunk(type_bytes: [73, 68, 65, 84], data_bytes: idat),
            chunk(type_bytes: [73, 69, 78, 68], data_bytes: []),
          ),
        ),
      ),
    ),
  )
  |> byte_list_to_bit_array
}

/// Render a QR code as PNG bytes.
///
/// `scale` values less than 1 are normalised to 1, and negative `margin`
/// values are normalised to 0. Thin wrapper around
/// [`to_bit_array_with`](#to_bit_array_with) using the default
/// black-on-white palette.
pub fn to_bit_array(
  qr: qrkit.QrCode,
  scale scale: Int,
  margin margin: Int,
) -> BitArray {
  to_bit_array_with(
    qr,
    default_options()
      |> with_module_size(scale)
      |> with_margin(margin),
  )
}

fn parse_css_rgb(
  css: String,
  default default: #(Int, Int, Int),
) -> #(Int, Int, Int) {
  case string.starts_with(css, "#") {
    False -> default
    True -> {
      let hex = string.drop_start(css, 1)
      case string.length(hex) {
        3 -> parse_short_hex(hex, default)
        6 -> parse_long_hex(hex, default)
        8 -> parse_long_hex(string.slice(hex, 0, 6), default)
        _ -> default
      }
    }
  }
}

fn parse_short_hex(hex: String, default: #(Int, Int, Int)) -> #(Int, Int, Int) {
  let r = string.slice(hex, 0, 1)
  let g = string.slice(hex, 1, 1)
  let b = string.slice(hex, 2, 1)
  case parse_hex_byte(r <> r), parse_hex_byte(g <> g), parse_hex_byte(b <> b) {
    Ok(rv), Ok(gv), Ok(bv) -> #(rv, gv, bv)
    _, _, _ -> default
  }
}

fn parse_long_hex(hex: String, default: #(Int, Int, Int)) -> #(Int, Int, Int) {
  let r = string.slice(hex, 0, 2)
  let g = string.slice(hex, 2, 2)
  let b = string.slice(hex, 4, 2)
  case parse_hex_byte(r), parse_hex_byte(g), parse_hex_byte(b) {
    Ok(rv), Ok(gv), Ok(bv) -> #(rv, gv, bv)
    _, _, _ -> default
  }
}

fn parse_hex_byte(s: String) -> Result(Int, Nil) {
  int.base_parse(s, 16)
}

fn pad_rows(rows: List(List(Bool)), margin: Int) -> List(List(Bool)) {
  let width = case rows {
    [first, ..] -> list.length(first)
    [] -> 0
  }
  let padding = list.repeat(False, width + margin * 2)
  let body =
    rows
    |> list.map(fn(row) {
      list.append(
        list.repeat(False, margin),
        list.append(row, list.repeat(False, margin)),
      )
    })

  list.append(
    list.repeat(padding, margin),
    list.append(body, list.repeat(padding, margin)),
  )
}

fn scale_rows(rows: List(List(Bool)), scale: Int) -> List(List(Bool)) {
  rows
  |> list.flat_map(fn(row) {
    let scaled = scale_row(row, scale, [])
    list.repeat(scaled, scale)
  })
}

fn scale_row(row: List(Bool), scale: Int, acc: List(Bool)) -> List(Bool) {
  case row {
    [] -> list.reverse(acc)
    [value, ..rest] -> scale_row(rest, scale, prepend_repeat(value, scale, acc))
  }
}

fn prepend_repeat(value: a, count: Int, acc: List(a)) -> List(a) {
  case count <= 0 {
    True -> acc
    False -> prepend_repeat(value, count - 1, [value, ..acc])
  }
}

fn pixels_width(rows: List(List(Bool))) -> Int {
  case rows {
    [first, ..] -> list.length(first)
    [] -> 0
  }
}

fn scanlines(rows: List(List(Bool)), acc: List(Int)) -> List(Int) {
  case rows {
    [] -> list.reverse(acc)
    [row, ..rest] -> scanlines(rest, prepend_reversed(pack_scanline(row), acc))
  }
}

fn pack_scanline(row: List(Bool)) -> List(Int) {
  [0, ..pack_bits(row, 0, 0, [])]
}

fn pack_bits(
  pixels: List(Bool),
  current: Int,
  bit_count: Int,
  acc: List(Int),
) -> List(Int) {
  case pixels {
    [] ->
      case bit_count == 0 {
        True -> list.reverse(acc)
        False -> list.reverse([finish_byte(current, bit_count), ..acc])
      }
    [pixel, ..rest] -> {
      let next = current * 2 + pixel_bit(pixel)
      let next_count = bit_count + 1
      case next_count == 8 {
        True -> pack_bits(rest, 0, 0, [next, ..acc])
        False -> pack_bits(rest, next, next_count, acc)
      }
    }
  }
}

fn pixel_bit(pixel: Bool) -> Int {
  case pixel {
    True -> 0
    False -> 1
  }
}

fn finish_byte(current: Int, bit_count: Int) -> Int {
  let padding_bits = 8 - bit_count
  current * power_of_two(padding_bits) + { power_of_two(padding_bits) - 1 }
}

fn zlib_store(data: List(Int)) -> List(Int) {
  let checksum = adler32(data)
  list.append([120, 1], deflate_store_blocks(data))
  |> list.append(u32_bytes(checksum))
}

fn deflate_store_blocks(data: List(Int)) -> List(Int) {
  do_deflate_store_blocks(data, [])
}

fn do_deflate_store_blocks(data: List(Int), acc: List(Int)) -> List(Int) {
  case data {
    [] -> list.reverse(acc)
    _ -> {
      let #(chunk_bytes, rest) = take_bytes(data, 65_535, [])
      let final = case rest {
        [] -> 1
        _ -> 0
      }
      let length = list.length(chunk_bytes)
      let complement = 65_535 - length
      let next = [
        final,
        low_byte(length),
        high_byte(length),
        low_byte(complement),
        high_byte(complement),
        ..chunk_bytes
      ]
      do_deflate_store_blocks(rest, prepend_reversed(next, acc))
    }
  }
}

fn take_bytes(
  values: List(Int),
  count: Int,
  acc: List(Int),
) -> #(List(Int), List(Int)) {
  case values, count {
    rest, 0 -> #(list.reverse(acc), rest)
    [value, ..rest], _ -> take_bytes(rest, count - 1, [value, ..acc])
    [], _ -> #(list.reverse(acc), [])
  }
}

fn chunk(
  type_bytes type_bytes: List(Int),
  data_bytes data_bytes: List(Int),
) -> List(Int) {
  let crc = crc32(list.append(type_bytes, data_bytes))
  list.append(
    u32_bytes(list.length(data_bytes)),
    list.append(type_bytes, list.append(data_bytes, u32_bytes(crc))),
  )
}

fn crc32(bytes: List(Int)) -> Int {
  do_crc32(bytes, 0xFFFF_FFFF)
  |> int.bitwise_exclusive_or(0xFFFF_FFFF)
}

fn do_crc32(bytes: List(Int), crc: Int) -> Int {
  case bytes {
    [] -> crc
    [byte, ..rest] ->
      do_crc32(rest, crc32_byte(int.bitwise_exclusive_or(crc, byte), 8))
  }
}

fn crc32_byte(crc: Int, remaining: Int) -> Int {
  case remaining <= 0 {
    True -> crc
    False -> {
      let next = case int.bitwise_and(crc, 1) == 1 {
        True ->
          int.bitwise_exclusive_or(
            int.bitwise_shift_right(crc, 1),
            crc32_polynomial,
          )
        False -> int.bitwise_shift_right(crc, 1)
      }
      crc32_byte(next, remaining - 1)
    }
  }
}

fn adler32(bytes: List(Int)) -> Int {
  do_adler32(bytes, 1, 0)
}

fn do_adler32(bytes: List(Int), s1: Int, s2: Int) -> Int {
  case bytes {
    [] -> s2 * 65_536 + s1
    [byte, ..rest] -> {
      let next_s1 = { s1 + byte } % adler32_modulus
      let next_s2 = { s2 + next_s1 } % adler32_modulus
      do_adler32(rest, next_s1, next_s2)
    }
  }
}

fn byte_list_to_bit_array(bytes: List(Int)) -> BitArray {
  bytes
  |> list.map(fn(byte) { <<byte>> })
  |> bit_array.concat
}

fn prepend_reversed(values: List(a), acc: List(a)) -> List(a) {
  case values {
    [] -> acc
    [value, ..rest] -> prepend_reversed(rest, [value, ..acc])
  }
}

fn positive_or(value: Int, default default: Int) -> Int {
  case value > 0 {
    True -> value
    False -> default
  }
}

fn non_negative_or(value: Int, default default: Int) -> Int {
  case value >= 0 {
    True -> value
    False -> default
  }
}

fn u32_bytes(value: Int) -> List(Int) {
  [
    int.bitwise_and(int.bitwise_shift_right(value, 24), 0xFF),
    int.bitwise_and(int.bitwise_shift_right(value, 16), 0xFF),
    int.bitwise_and(int.bitwise_shift_right(value, 8), 0xFF),
    int.bitwise_and(value, 0xFF),
  ]
}

fn low_byte(value: Int) -> Int {
  int.bitwise_and(value, 0xFF)
}

fn high_byte(value: Int) -> Int {
  int.bitwise_and(int.bitwise_shift_right(value, 8), 0xFF)
}

fn power_of_two(exponent: Int) -> Int {
  case exponent <= 0 {
    True -> 1
    False -> 2 * power_of_two(exponent - 1)
  }
}
