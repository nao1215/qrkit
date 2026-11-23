//// Kanji mode writes Shift JIS values. A reader that honours an ECI
//// designator other than Shift JIS (20) applies that character set to
//// them: zxing-cpp read Kanji segments after ECI 26 (UTF-8) as garbage.
//// So with such an ECI, kanji are written as UTF-8 Byte data instead.

import gleam/option.{Some}
import qrkit

fn encode(text: String, eci: Int) -> qrkit.QrCode {
  let assert Ok(qr) =
    qrkit.encode_with(
      text,
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.High,
        eci: Some(eci),
      ),
    )
  qr
}

pub fn utf8_eci_writes_kanji_as_bytes_test() {
  // Three kanji fit version 1-H in Kanji mode (63 bits with the ECI
  // header) but need version 2 as nine UTF-8 bytes (96 bits).
  let qr = encode("漢字東", 26)
  assert qr.version == 2
  let assert Ok(decoded) = qrkit.decode(qr.rows)
  assert decoded.text == "漢字東"
  assert decoded.eci == Some(26)
}

pub fn shift_jis_eci_keeps_kanji_mode_test() {
  assert encode("漢字東", 20).version == 1
}
