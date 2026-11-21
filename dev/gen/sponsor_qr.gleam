import qrkit
import simplifile

pub fn main() -> Nil {
  let url = "https://github.com/sponsors/nao1215"
  let assert Ok(qr) = qrkit.encode(url)
  let bytes = qrkit.to_png(qr, qrkit.default_image_options())
  let assert Ok(Nil) =
    simplifile.write_bits("docs/images/sponsor-qr.png", bytes)
  Nil
}
