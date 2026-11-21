import qrkit
import qrkit/render/png
import simplifile

pub fn main() -> Nil {
  let url = "https://github.com/sponsors/nao1215"
  let assert Ok(qr) = qrkit.encode(url)
  let bytes = png.to_bit_array(qr, scale: 8, margin: 4)
  let assert Ok(Nil) =
    simplifile.write_bits("docs/images/sponsor-qr.png", bytes)
  Nil
}
