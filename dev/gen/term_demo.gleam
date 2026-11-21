//// Render the same QR code three ways for the terminal. Run with
//// `gleam run -m gen/term_demo`.

import gleam/io
import qrkit
import qrkit/render/ascii

pub fn main() -> Nil {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")

  io.println("=== to_string (light terminal) ===")
  io.println(ascii.to_string(qr))

  io.println("")
  io.println("=== with_inverse (dark terminal) ===")
  io.println(ascii.with_inverse(qr))

  io.println("")
  io.println("=== to_string_compact (half height) ===")
  io.println(ascii.to_string_compact(qr))
  Nil
}
