//// Regression coverage for issue #28: PNG renderer used to expose
//// only `to_bit_array(qr, scale:, margin:)` while SVG / ASCII had
//// `default_options + with_*` builders. Now mirrors them.

import gleam/bit_array
import gleeunit/should
import qrkit
import qrkit/render/png

pub fn default_options_round_trips_with_legacy_entry_point_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("https://example.com/")
  let bytes_a = png.to_bit_array(qr, scale: 4, margin: 2)
  let bytes_b =
    qr
    |> png.to_bit_array_with(
      png.default_options()
      |> png.with_module_size(4)
      |> png.with_margin(2),
    )
  { bytes_a == bytes_b } |> should.be_true
}

pub fn dark_color_changes_output_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("https://example.com/")
  let neutral = png.to_bit_array_with(qr, png.default_options())
  let neon =
    png.to_bit_array_with(
      qr,
      png.default_options() |> png.with_dark_color("#22d3ee"),
    )
  { neutral == neon } |> should.be_false
}

pub fn light_color_changes_output_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("hello")
  let default_light = png.to_bit_array_with(qr, png.default_options())
  let dark_bg =
    png.to_bit_array_with(
      qr,
      png.default_options() |> png.with_light_color("#020617"),
    )
  { default_light == dark_bg } |> should.be_false
}

pub fn background_off_yields_valid_png_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("hello")
  let bytes =
    png.to_bit_array_with(
      qr,
      png.default_options() |> png.with_background(False),
    )
  let assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest:bytes>> = bytes
  { bit_array.byte_size(bytes) > 0 } |> should.be_true
}

pub fn background_off_differs_from_default_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("hello")
  let with_bg = png.to_bit_array_with(qr, png.default_options())
  let without_bg =
    png.to_bit_array_with(
      qr,
      png.default_options() |> png.with_background(False),
    )
  { with_bg == without_bg } |> should.be_false
}

pub fn legacy_to_bit_array_still_compiles_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("hello")
  let bytes = png.to_bit_array(qr, scale: 4, margin: 2)
  { bit_array.byte_size(bytes) > 0 } |> should.be_true
}

pub fn short_hex_color_accepted_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("x")
  let long =
    png.to_bit_array_with(
      qr,
      png.default_options() |> png.with_dark_color("#ff0000"),
    )
  let short =
    png.to_bit_array_with(
      qr,
      png.default_options() |> png.with_dark_color("#f00"),
    )
  { long == short } |> should.be_true
}
