//// Render the same QR code three ways for the terminal. Run with
//// `gleam run -m gen/term_demo`.

import gleam/io
import qrkit

pub fn main() -> Nil {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")

  io.println("=== to_string (light terminal) ===")
  io.println(qrkit.to_terminal(qr, style: qrkit.Blocks, margin: 4))

  io.println("")
  io.println("=== with_inverse (dark terminal) ===")
  io.println(qrkit.to_terminal(qr, style: qrkit.InvertedBlocks, margin: 4))

  io.println("")
  io.println("=== to_string_compact (half height) ===")
  io.println(qrkit.to_terminal(qr, style: qrkit.HalfBlocks, margin: 4))
  Nil
}
