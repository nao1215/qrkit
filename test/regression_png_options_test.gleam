//// Regression coverage for issue #28: PNG renderer used to expose
//// only `to_bit_array(qr, scale:, margin:)` while SVG / ASCII had
//// `default_options + with_*` builders. Now mirrors them.

import gleam/bit_array
import gleam/option.{None, Some}
import gleeunit/should
import qrkit

pub fn default_options_round_trips_with_legacy_entry_point_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("https://example.com/")
  let bytes_a =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(
        ..qrkit.default_image_options(),
        module_size: 4,
        margin: 2,
      ),
    )
  let bytes_b =
    qr
    |> qrkit.to_png(
      qrkit.ImageOptions(
        ..qrkit.default_image_options(),
        module_size: 4,
        margin: 2,
      ),
    )
  { bytes_a == bytes_b } |> should.be_true
}

pub fn dark_color_changes_output_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("https://example.com/")
  let neutral = qrkit.to_png(qr, qrkit.default_image_options())
  let neon =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(..qrkit.default_image_options(), dark_color: "#22d3ee"),
    )
  { neutral == neon } |> should.be_false
}

pub fn light_color_changes_output_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("hello")
  let default_light = qrkit.to_png(qr, qrkit.default_image_options())
  let dark_bg =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(
        ..qrkit.default_image_options(),
        light_color: Some("#020617"),
      ),
    )
  { default_light == dark_bg } |> should.be_false
}

pub fn background_off_yields_valid_png_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("hello")
  let bytes =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(..qrkit.default_image_options(), light_color: None),
    )
  let assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest:bytes>> = bytes
  { bit_array.byte_size(bytes) > 0 } |> should.be_true
}

pub fn background_off_differs_from_default_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("hello")
  let with_bg = qrkit.to_png(qr, qrkit.default_image_options())
  let without_bg =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(..qrkit.default_image_options(), light_color: None),
    )
  { with_bg == without_bg } |> should.be_false
}

pub fn legacy_to_bit_array_still_compiles_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("hello")
  let bytes =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(
        ..qrkit.default_image_options(),
        module_size: 4,
        margin: 2,
      ),
    )
  { bit_array.byte_size(bytes) > 0 } |> should.be_true
}

pub fn short_hex_color_accepted_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("x")
  let long =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(..qrkit.default_image_options(), dark_color: "#ff0000"),
    )
  let short =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(..qrkit.default_image_options(), dark_color: "#f00"),
    )
  { long == short } |> should.be_true
}
