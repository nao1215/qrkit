//// Generators shared by the property tests and the nightly interop corpus.

import metamon/generator
import metamon/generator/range
import qrkit/types

/// Strings mixing ASCII, digits, kana, kanji, Latin-1 letters, an emoji and
/// newlines, so every encoding mode and segment boundary is exercised.
pub fn text() -> generator.Generator(String) {
  let char =
    generator.frequency([
      #(4, generator.ascii_printable()),
      #(3, generator.ascii_digit()),
      #(
        2,
        generator.element_of([
          "あ", "カ", "漢", "字", "東", "京", "。", "Ａ", "é", "ß", "😀", "\n", " ",
        ]),
      ),
    ])
  generator.string(char, range.constant(1, 40))
}

pub fn symbol() -> generator.Generator(types.Symbol) {
  generator.element_of([types.Standard, types.Micro, types.Rectangular])
}

pub fn ecc() -> generator.Generator(types.ErrorCorrection) {
  generator.element_of([types.Low, types.Medium, types.Quartile, types.High])
}
