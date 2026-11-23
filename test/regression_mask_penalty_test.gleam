//// Mask selection must follow ISO/IEC 18004 §7.8.3.1 as zxing does: the
//// quiet zone counts as light for the 1:1:3:1:1 rule, and the dark
//// proportion is scored from the exact percentage. Each expected mask
//// below is the one zxing-cpp's encoder picks for the same symbol; its
//// matrix is identical to qrkit's.

import gleam/list
import qrkit

fn mask_of(text: String, level: qrkit.ErrorCorrection) -> Int {
  let assert Ok(qr) =
    qrkit.encode_with(
      text,
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: level,
      ),
    )
  qr.mask
}

pub fn mask_choice_matches_zxing_test() {
  let cases = [
    #("5366102830671", qrkit.Medium, 6),
    #("22", qrkit.High, 5),
    #("o4vkz", qrkit.Quartile, 0),
    #(":", qrkit.Low, 4),
    #("ZG:M", qrkit.High, 1),
    #("D3D6Y3X-", qrkit.Quartile, 3),
    #("pz8id", qrkit.High, 1),
  ]
  list.each(cases, fn(case_) {
    let #(text, level, expected) = case_
    assert mask_of(text, level) == expected
  })
}

fn micro_mask_of(text: String, level: qrkit.ErrorCorrection) -> Int {
  let assert Ok(qr) =
    qrkit.encode_with(
      text,
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        error_correction: level,
      ),
    )
  qr.mask
}

// Micro QR keeps the mask whose right column and bottom row hold the most
// dark modules (§7.8.3.2). The bottom row used to be read as one module.
// The expected masks are zxing-cpp's, whose matrices are identical.
pub fn micro_mask_choice_matches_zxing_test() {
  let cases = [
    #("CG2GH1", qrkit.Medium, 0),
    #("955139", qrkit.Medium, 0),
    #("9 YY", qrkit.Low, 3),
    #("7ZL", qrkit.Medium, 3),
    #("rdysqrvs", qrkit.Low, 2),
    #("910989625", qrkit.Quartile, 1),
    #("26", qrkit.Quartile, 2),
  ]
  list.each(cases, fn(case_) {
    let #(text, level, expected) = case_
    assert micro_mask_of(text, level) == expected
  })
}
