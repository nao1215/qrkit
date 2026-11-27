//// Generators shared by the property tests and the nightly interop corpus.

import metamon/generator
import qrkit

/// Strings mixing ASCII, digits, kana, kanji, Latin-1 letters, an emoji and
/// newlines, so every encoding mode and segment boundary is exercised.
pub fn text() -> generator.Generator(String) {
  let char =
    generator.frequency([
      #(4, generator.character(of: generator.PrintableAscii)),
      #(3, generator.character(of: generator.Digits)),
      #(
        2,
        generator.element_of([
          "あ", "カ", "漢", "字", "東", "京", "。", "Ａ", "é", "ß", "😀", "\n", " ",
        ]),
      ),
    ])
  generator.string_from(
    characters: char,
    length: generator.range(from: 1, to: 40),
  )
}

pub fn symbol() -> generator.Generator(qrkit.Symbol) {
  generator.element_of([qrkit.Standard, qrkit.Micro, qrkit.Rectangular])
}

pub fn ecc() -> generator.Generator(qrkit.ErrorCorrection) {
  generator.element_of([qrkit.Low, qrkit.Medium, qrkit.Quartile, qrkit.High])
}
