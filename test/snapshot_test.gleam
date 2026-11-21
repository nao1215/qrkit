//// Snapshot tests (birdie) for the text renderers. A snapshot changes when the
//// modules of a symbol change (segmentation, masking, padding, error
//// correction) or when a renderer's output changes, and the change has to be
//// reviewed with `gleam run -m birdie` before it is accepted.
////
//// Each snapshot is also decoded, so an accepted snapshot is known to read
//// back to its input, not only to match the previous run.

import gleam/option.{Some}

import birdie
import gleam/string
import qrkit

const sponsor_url = "https://github.com/sponsors/nao1215"

fn build(
  text: String,
  symbol: qrkit.Symbol,
  ecc: qrkit.ErrorCorrection,
) -> qrkit.QrCode {
  let assert Ok(qr) =
    qrkit.encode_with(
      text,
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: symbol,
        error_correction: ecc,
      ),
    )
    as "the snapshot inputs fit their symbols"
  let assert Ok(decoded) = qrkit.decode(qr.rows) as "a snapshot symbol decodes"
  assert decoded.text == text
  qr
}

pub fn standard_qr_compact_terminal_snapshot_test() -> Nil {
  build(sponsor_url, qrkit.Standard, qrkit.Medium)
  |> qrkit.to_terminal(style: qrkit.HalfBlocks, margin: 4)
  |> birdie.snap(title: "standard qr, sponsor url, medium, compact terminal")
}

pub fn standard_qr_mixed_segments_terminal_snapshot_test() -> Nil {
  // Byte, Kanji and Numeric segments in one symbol.
  build("価格は 1234567890 円", qrkit.Standard, qrkit.Quartile)
  |> qrkit.to_terminal(style: qrkit.Blocks, margin: 1)
  |> birdie.snap(title: "standard qr, kanji and digits, quartile, terminal")
}

pub fn micro_qr_terminal_snapshot_test() -> Nil {
  build("01234567", qrkit.Micro, qrkit.Low)
  |> qrkit.to_terminal(style: qrkit.Blocks, margin: 2)
  |> birdie.snap(title: "micro qr, digits, low, terminal")
}

pub fn rmqr_compact_terminal_snapshot_test() -> Nil {
  build(sponsor_url, qrkit.Rectangular, qrkit.Medium)
  |> qrkit.to_terminal(style: qrkit.HalfBlocks, margin: 2)
  |> birdie.snap(title: "rmqr, sponsor url, medium, compact terminal")
}

pub fn svg_snapshot_test() -> Nil {
  // One path command per line so a changed module shows as a changed line.
  build("01234567", qrkit.Micro, qrkit.Low)
  |> qrkit.to_svg(qrkit.ImageOptions(
    module_size: 4,
    margin: 2,
    dark_color: "#111",
    light_color: Some("#fff"),
  ))
  |> string.replace(each: "z", with: "z\n")
  |> birdie.snap(title: "svg, micro qr, digits, low, with background")
}
