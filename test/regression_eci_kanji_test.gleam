//// Kanji mode writes Shift JIS values. A reader that honours an ECI
//// applies its character set to them: zxing-cpp read Kanji segments after
//// ECI 26 (UTF-8) as garbage. Under ECI 26, kanji are written as UTF-8
//// Byte data instead. Other designators keep Kanji mode, which qrkit's
//// own decoder reads whatever the ECI.

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

pub fn other_ecis_keep_kanji_mode_test() {
  assert encode("漢字東", 20).version == 1
  let latin1 = encode("漢字東", 3)
  assert latin1.version == 1
  let assert Ok(decoded) = qrkit.decode(latin1.rows)
  assert decoded.text == "漢字東"
}
