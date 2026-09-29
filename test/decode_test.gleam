//// Tests for `qrkit/decode`: round trips through qrkit's own encoder,
//// symbols written by another encoder (segno 1.6, shown in each fixture's
//// comment), orientation and quiet zone handling, and error correction.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import qrkit
import qrkit/decode
import qrkit/error
import qrkit/internal/standard
import qrkit/types

fn rows_of(lines: List(String)) -> List(List(Bool)) {
  list.map(lines, fn(line) {
    string.to_graphemes(line) |> list.map(fn(c) { c == "1" })
  })
}

fn round_trip(
  text: String,
  symbol: types.Symbol,
  ecc: types.ErrorCorrection,
) -> decode.Decoded {
  let assert Ok(qr) =
    qrkit.new(text)
    |> qrkit.with_symbol(symbol)
    |> qrkit.with_ecc(ecc)
    |> qrkit.build
  let assert Ok(decoded) = decode.from_rows(qrkit.rows(qr))
  decoded
}

pub fn round_trips_every_symbol_family_test() -> Nil {
  let cases = [
    #("https://github.com/sponsors/nao1215", types.Standard, types.Medium),
    #("東京都千代田区丸の内 1-1", types.Standard, types.High),
    #("😀 emoji and é", types.Standard, types.Low),
    #(string.repeat("0123456789", 50), types.Standard, types.Quartile),
    #("12345", types.Micro, types.Low),
    #("QRKIT", types.Micro, types.Medium),
    #("カタカナ", types.Micro, types.Quartile),
    #("品番ABC-12345 数量10", types.Rectangular, types.Medium),
    #(string.repeat("rMQR ", 8), types.Rectangular, types.High),
  ]
  list.each(cases, fn(case_) {
    let #(text, symbol, ecc) = case_
    let decoded = round_trip(text, symbol, ecc)
    decode.text(decoded) |> should.equal(text)
    decode.symbol(decoded) |> should.equal(symbol)
    decode.error_correction(decoded) |> should.equal(ecc)
    decode.errors_corrected(decoded) |> should.equal(0)
  })
}

pub fn reports_version_and_mask_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let assert Ok(decoded) = decode.from_rows(qrkit.rows(qr))
  decode.version(decoded) |> should.equal(qrkit.version(qr))
  decode.mask(decoded) |> should.equal(qrkit.mask(qr))
}

pub fn reads_the_eci_designator_test() -> Nil {
  let assert Ok(qr) = qrkit.new("Grüße") |> qrkit.with_eci(26) |> qrkit.build
  let assert Ok(decoded) = decode.from_rows(qrkit.rows(qr))
  decode.text(decoded) |> should.equal("Grüße")
  decode.eci(decoded) |> should.equal(Some(26))
}

pub fn reads_structured_append_parts_test() -> Nil {
  let payload = string.repeat("Structured Append ", 8)
  let assert Ok(parts) = qrkit.encode_split(payload, 2)
  let decoded =
    list.map(parts, fn(qr) {
      let assert Ok(d) = decode.from_rows(qrkit.rows(qr))
      d
    })
  list.length(decoded) |> should.equal(list.length(parts))
  list.index_map(decoded, fn(d, i) {
    let assert Some(header) = decode.structured_append(d)
    header.position |> should.equal(i)
    header.total |> should.equal(list.length(parts))
  })
  list.map(decoded, decode.text) |> string.concat |> should.equal(payload)
}

pub fn single_symbol_has_no_structured_append_test() -> Nil {
  let decoded = round_trip("HELLO", types.Standard, types.Medium)
  decode.structured_append(decoded) |> should.equal(None)
  decode.eci(decoded) |> should.equal(None)
}

pub fn strips_the_quiet_zone_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("quiet zone")
  let rows = qrkit.rows(qr)
  let width = list.length(rows) + 8
  let pad = fn(row) {
    list.flatten([list.repeat(False, 4), row, list.repeat(False, 4)])
  }
  let blank = list.repeat(list.repeat(False, width), 4)
  let padded = list.flatten([blank, list.map(rows, pad), blank])
  let assert Ok(decoded) = decode.from_rows(padded)
  decode.text(decoded) |> should.equal("quiet zone")
}

pub fn reads_rotated_and_mirrored_symbols_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("turned around")
  let rows = qrkit.rows(qr)
  let rotate = fn(r) { list.transpose(r) |> list.map(list.reverse) }
  [
    rotate(rows),
    rotate(rotate(rows)),
    rotate(rotate(rotate(rows))),
    list.transpose(rows),
    list.map(rows, list.reverse),
  ]
  |> list.each(fn(variant) {
    let assert Ok(decoded) = decode.from_rows(variant)
    decode.text(decoded) |> should.equal("turned around")
  })

  let assert Ok(rect) =
    qrkit.new("upside down")
    |> qrkit.with_symbol(types.Rectangular)
    |> qrkit.build
  let assert Ok(decoded) =
    decode.from_rows(qrkit.rows(rect) |> list.reverse |> list.map(list.reverse))
  decode.text(decoded) |> should.equal("upside down")
}

/// Flip one bit in each of the first `count` codewords of a version 1
/// symbol, following the placement order.
fn damage_codewords(qr: qrkit.QrCode, count: Int) -> List(List(Bool)) {
  let targets =
    standard.data_module_positions(qrkit.version(qr))
    |> list.sized_chunk(8)
    |> list.take(count)
    |> list.filter_map(list.first)
  list.index_map(qrkit.rows(qr), fn(row, r) {
    list.index_map(row, fn(dark, c) {
      case list.contains(targets, #(r, c)) {
        True -> !dark
        False -> dark
      }
    })
  })
}

pub fn corrects_up_to_half_the_error_correction_codewords_test() -> Nil {
  // Version 1-H has 17 error correction codewords: 8 errors are corrected.
  let assert Ok(qr) =
    qrkit.new("HELLO")
    |> qrkit.with_ecc(types.High)
    |> qrkit.with_exact_version(1)
    |> qrkit.build
  let assert Ok(decoded) = decode.from_rows(damage_codewords(qr, 8))
  decode.text(decoded) |> should.equal("HELLO")
  decode.errors_corrected(decoded) |> should.equal(8)
}

pub fn too_many_errors_is_reported_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("HELLO")
    |> qrkit.with_ecc(types.Low)
    |> qrkit.with_exact_version(1)
    |> qrkit.build
  // Version 1-L has 7 error correction codewords; 10 damaged codewords are
  // past what it can correct.
  decode.from_rows(damage_codewords(qr, 10))
  |> should.equal(Error(error.TooManyErrors))
}

pub fn rejects_sizes_that_match_no_symbol_test() -> Nil {
  let grid = list.repeat(list.repeat(True, 20), 20)
  decode.from_rows(grid) |> should.equal(Error(error.NotASymbol(20, 20)))
  decode.from_rows([[True, True], [True]])
  |> should.equal(Error(error.NotASymbol(2, 2)))
  decode.from_rows([]) |> should.equal(Error(error.NotASymbol(0, 0)))
}

pub fn unreadable_format_information_test() -> Nil {
  // A 21x21 grid of dark modules is Standard QR sized, but neither format
  // copy is near a valid codeword in any orientation.
  decode.from_rows(list.repeat(list.repeat(True, 21), 21))
  |> should.equal(Error(error.UnreadableFormatInformation))
}

pub fn micro_qr_half_codeword_padding_carries_no_error_test() -> Nil {
  // M1, M3-L and M3-M end with a 4-bit data codeword. When it is padding it
  // must be 0000; the encoder used to compute the error correction over a
  // full 0xEC pad byte, so every such symbol started with one codeword error
  // and a single damaged module made it unreadable.
  [
    #("705", types.Low),
    #("1", types.Low),
    #("HELLO", types.Low),
    #("ABC12", types.Medium),
  ]
  |> list.each(fn(case_) {
    let decoded = round_trip(case_.0, types.Micro, case_.1)
    decode.text(decoded) |> should.equal(case_.0)
    decode.errors_corrected(decoded) |> should.equal(0)
  })
}

pub fn micro_qr_m1_matches_segno_test() -> Nil {
  // segno.make("705", version="M1", mask=3, micro=True): the same modules.
  let assert Ok(qr) =
    qrkit.new("705")
    |> qrkit.with_symbol(types.Micro)
    |> qrkit.with_ecc(types.Low)
    |> qrkit.build
  qrkit.mask(qr) |> should.equal(3)
  qrkit.rows(qr)
  |> should.equal(
    rows_of([
      "11111110101", "10000010011", "10111010001", "10111010110", "10111010101",
      "10000010110", "11111110001", "00000000010", "11001011011", "01111100101",
      "10000010010",
    ]),
  )
}

// --- Symbols written by segno 1.6 ---------------------------------------

pub fn segno_iso_8859_1_byte_mode_test() -> Nil {
  // segno.make("héllo wörld", error="M"): Byte mode in ISO-8859-1, no ECI.
  let assert Ok(decoded) = decode.from_rows(rows_of(segno_latin1))
  decode.text(decoded) |> should.equal("héllo wörld")
}

pub fn segno_shift_jis_byte_mode_test() -> Nil {
  // segno.make("カナ漢字abc", encoding="shift_jis", mode="byte"): Byte mode
  // in Shift JIS, no ECI.
  let assert Ok(decoded) = decode.from_rows(rows_of(segno_shift_jis))
  decode.text(decoded) |> should.equal("カナ漢字abc")
}

pub fn segno_kanji_mode_test() -> Nil {
  // segno.make("東京タワー", error="M"): Kanji mode.
  let assert Ok(decoded) = decode.from_rows(rows_of(segno_kanji))
  decode.text(decoded) |> should.equal("東京タワー")
}

pub fn segno_micro_qr_test() -> Nil {
  // segno.make("QRKIT", micro=True): M2-M, Alphanumeric mode.
  let assert Ok(decoded) = decode.from_rows(rows_of(segno_micro))
  decode.text(decoded) |> should.equal("QRKIT")
  decode.symbol(decoded) |> should.equal(types.Micro)
  decode.version(decoded) |> should.equal(2)
}

const segno_latin1: List(String) = [
  "111111101101001111111",
  "100000100101101000001",
  "101110100000101011101",
  "101110100111001011101",
  "101110101000101011101",
  "100000101000001000001",
  "111111101010101111111",
  "000000000111000000000",
  "011111110000000110001",
  "001111000101110010001",
  "100111111111101011111",
  "001000001110110011100",
  "010001111110011000001",
  "000000001111100011001",
  "111111101001001000110",
  "100000101101110101111",
  "101110101011001100001",
  "101110101110111111000",
  "101110101100100100100",
  "100000101110110011100",
  "111111100111101010010",
]

const segno_shift_jis: List(String) = [
  "111111101001101111111",
  "100000100111001000001",
  "101110100001001011101",
  "101110100010101011101",
  "101110101100101011101",
  "100000101111001000001",
  "111111101010101111111",
  "000000000100000000000",
  "011111110011100110001",
  "100101000001101000000",
  "101100101010001110010",
  "010111001110010110011",
  "100010110111101010100",
  "000000001000100100100",
  "111111101001010111001",
  "100000101011110011111",
  "101110101110101010001",
  "101110101010100010000",
  "101110101010101111100",
  "100000101011010110000",
  "111111100010101110110",
]

const segno_kanji: List(String) = [
  "111111101110101111111",
  "100000101110001000001",
  "101110101001001011101",
  "101110101011101011101",
  "101110101111101011101",
  "100000100111001000001",
  "111111101010101111111",
  "000000001011100000000",
  "011010110110101011111",
  "010101000001001101011",
  "010100101011011011111",
  "111010000101111100111",
  "001111101101101011010",
  "000000001110010010011",
  "111111101100001101011",
  "100000100100010101100",
  "101110101001001100111",
  "101110100100001001010",
  "101110101110100011001",
  "100000101010001101010",
  "111111100000101101000",
]

const segno_micro: List(String) = [
  "1111111010101",
  "1000001000111",
  "1011101000100",
  "1011101010011",
  "1011101001010",
  "1000001001000",
  "1111111010111",
  "0000000000000",
  "1110001010111",
  "0111100101011",
  "1010100110111",
  "0111101000000",
  "1101111101110",
]
