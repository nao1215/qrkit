//// Draw the figures in the README and the doc comments with qrkit itself:
//// `gleam run -m gen/doc_images` rewrites docs/images/symbols.svg and
//// docs/images/error-correction.svg. CI regenerates them and fails when the
//// committed files differ, so a change to the encoder shows up here.

import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import qrkit
import simplifile

const module_size: Int = 5

const margin: Int = 2

const label_height: Int = 44

const gap: Int = 28

pub fn main() -> Nil {
  let options = qrkit.default_encode_options()
  write("docs/images/symbols.svg", "12345678", [
    #("Standard QR", qrkit.EncodeOptions(..options, symbol: qrkit.Standard)),
    #(
      "Micro QR",
      qrkit.EncodeOptions(
        ..options,
        symbol: qrkit.Micro,
        error_correction: qrkit.Low,
      ),
    ),
    #("rMQR", qrkit.EncodeOptions(..options, symbol: qrkit.Rectangular)),
  ])
  write(
    "docs/images/error-correction.svg",
    "https://hexdocs.pm/qrkit/",
    [
      #("Low, 7%", qrkit.Low),
      #("Medium, 15%", qrkit.Medium),
      #("Quartile, 25%", qrkit.Quartile),
      #("High, 30%", qrkit.High),
    ]
      |> list.map(fn(level) {
        #(level.0, qrkit.EncodeOptions(..options, error_correction: level.1))
      }),
  )
}

/// Lays the symbols out left to right, each with its name and size below.
fn write(
  path: String,
  text: String,
  symbols: List(#(String, qrkit.EncodeOptions)),
) -> Nil {
  let codes =
    list.map(symbols, fn(symbol) {
      let assert Ok(qr) = qrkit.encode_with(text, symbol.1)
      #(symbol.0, qr)
    })
  let height =
    list.fold(codes, 0, fn(acc, code) { int.max(acc, pixels(code.1.height)) })
  let #(parts, width) =
    list.fold(codes, #([], 0), fn(acc, code) {
      let #(parts, x) = acc
      let #(name, qr) = code
      let image =
        qrkit.to_svg(
          qr,
          qrkit.ImageOptions(
            module_size:,
            margin:,
            dark_color: "#000000",
            light_color: Some("#ffffff"),
          ),
        )
        |> string.replace(
          "<svg xmlns=\"http://www.w3.org/2000/svg\" ",
          "<svg x=\""
            <> int.to_string(x)
            <> "\" y=\"0\" width=\""
            <> int.to_string(pixels(qr.width))
            <> "\" height=\""
            <> int.to_string(pixels(qr.height))
            <> "\" ",
        )
      let size =
        int.to_string(qr.width)
        <> " × "
        <> int.to_string(qr.height)
        <> " modules"
      let labels =
        label(x, height + 18, name, "name")
        <> label(x, height + 36, size, "size")
      #([labels, image, ..parts], x + pixels(qr.width) + gap)
    })
  let svg =
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\""
    <> int.to_string(width - gap)
    <> "\" height=\""
    <> int.to_string(height + label_height)
    <> "\" font-family=\"-apple-system,Segoe UI,Helvetica,Arial,sans-serif\">"
    <> "<style>text{fill:#1f2328}.size{fill:#57606a}"
    <> "@media (prefers-color-scheme:dark){text{fill:#e6edf3}.size{fill:#8b949e}}</style>"
    <> string.concat(list.reverse(parts))
    <> "</svg>\n"
  let assert Ok(Nil) = simplifile.write(path, svg)
  Nil
}

/// The size in pixels of `modules` modules and the quiet zone on both sides.
fn pixels(modules: Int) -> Int {
  { modules + 2 * margin } * module_size
}

fn label(x: Int, y: Int, text: String, class: String) -> String {
  let size = case class {
    "name" -> "14"
    _ -> "12"
  }
  "<text class=\""
  <> class
  <> "\" x=\""
  <> int.to_string(x)
  <> "\" y=\""
  <> int.to_string(y)
  <> "\" font-size=\""
  <> size
  <> "\">"
  <> text
  <> "</text>"
}
