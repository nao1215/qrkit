//// Snapshot tests (birdie) for the text renderers. A snapshot changes when the
//// modules of a symbol change (segmentation, masking, padding, error
//// correction) or when a renderer's output changes, and the change has to be
//// reviewed with `gleam run -m birdie` before it is accepted.
////
//// Each snapshot is also decoded, so an accepted snapshot is known to read
//// back to its input, not only to match the previous run.

import birdie
import gleam/string
import qrkit
import qrkit/decode
import qrkit/render/ascii
import qrkit/render/svg
import qrkit/types

const sponsor_url = "https://github.com/sponsors/nao1215"

fn build(
  text: String,
  symbol: types.Symbol,
  ecc: types.ErrorCorrection,
) -> qrkit.QrCode {
  let assert Ok(qr) =
    qrkit.new(text)
    |> qrkit.with_symbol(symbol)
    |> qrkit.with_ecc(ecc)
    |> qrkit.build
    as "the snapshot inputs fit their symbols"
  let assert Ok(decoded) = decode.from_rows(qrkit.rows(qr))
    as "a snapshot symbol decodes"
  assert decode.text(decoded) == text
  qr
}

pub fn standard_qr_compact_terminal_snapshot_test() -> Nil {
  build(sponsor_url, types.Standard, types.Medium)
  |> ascii.to_string_compact
  |> birdie.snap(title: "standard qr, sponsor url, medium, compact terminal")
}

pub fn standard_qr_mixed_segments_terminal_snapshot_test() -> Nil {
  // Byte, Kanji and Numeric segments in one symbol.
  build("価格は 1234567890 円", types.Standard, types.Quartile)
  |> ascii.to_string_with(ascii.default_options() |> ascii.with_margin(1))
  |> birdie.snap(title: "standard qr, kanji and digits, quartile, terminal")
}

pub fn micro_qr_terminal_snapshot_test() -> Nil {
  build("01234567", types.Micro, types.Low)
  |> ascii.to_string_with(ascii.default_options() |> ascii.with_margin(2))
  |> birdie.snap(title: "micro qr, digits, low, terminal")
}

pub fn rmqr_compact_terminal_snapshot_test() -> Nil {
  build(sponsor_url, types.Rectangular, types.Medium)
  |> ascii.to_string_compact_with(
    ascii.default_options() |> ascii.with_margin(2),
  )
  |> birdie.snap(title: "rmqr, sponsor url, medium, compact terminal")
}

pub fn svg_snapshot_test() -> Nil {
  // One path command per line so a changed module shows as a changed line.
  build("01234567", types.Micro, types.Low)
  |> svg.to_string_with(
    svg.default_options()
    |> svg.with_module_size(4)
    |> svg.with_margin(2)
    |> svg.with_dark_color("#111")
    |> svg.with_light_color("#fff")
    |> svg.with_background(True),
  )
  |> string.replace(each: "z", with: "z\n")
  |> birdie.snap(title: "svg, micro qr, digits, low, with background")
}
