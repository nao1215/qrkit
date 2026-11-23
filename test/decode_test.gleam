//// Tests for `qrkit/decode`: round trips through qrkit's own encoder,
//// symbols written by another encoder (segno 1.6, shown in each fixture's
//// comment), orientation and quiet zone handling, and error correction.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import qrkit
import qrkit/internal/standard
import simplifile

fn rows_of(lines: List(String)) -> List(List(Bool)) {
  list.map(lines, fn(line) {
    string.to_graphemes(line) |> list.map(fn(c) { c == "1" })
  })
}

fn round_trip(
  text: String,
  symbol: qrkit.Symbol,
  ecc: qrkit.ErrorCorrection,
) -> qrkit.Decoded {
  let assert Ok(qr) =
    qrkit.encode_with(
      text,
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: symbol,
        error_correction: ecc,
      ),
    )
  let assert Ok(decoded) = qrkit.decode(qr.rows)
  decoded
}

pub fn round_trips_every_symbol_family_test() -> Nil {
  let cases = [
    #("https://github.com/sponsors/nao1215", qrkit.Standard, qrkit.Medium),
    #("東京都千代田区丸の内 1-1", qrkit.Standard, qrkit.High),
    #("😀 emoji and é", qrkit.Standard, qrkit.Low),
    #(string.repeat("0123456789", 50), qrkit.Standard, qrkit.Quartile),
    #("12345", qrkit.Micro, qrkit.Low),
    #("QRKIT", qrkit.Micro, qrkit.Medium),
    #("カタカナ", qrkit.Micro, qrkit.Quartile),
    #("品番ABC-12345 数量10", qrkit.Rectangular, qrkit.Medium),
    #(string.repeat("rMQR ", 8), qrkit.Rectangular, qrkit.High),
  ]
  list.each(cases, fn(case_) {
    let #(text, symbol, ecc) = case_
    let decoded = round_trip(text, symbol, ecc)
    decoded.text |> should.equal(text)
    decoded.symbol |> should.equal(symbol)
    decoded.error_correction |> should.equal(ecc)
    decoded.errors_corrected |> should.equal(0)
  })
}

pub fn reports_version_and_mask_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let assert Ok(decoded) = qrkit.decode(qr.rows)
  decoded.version |> should.equal(qr.version)
  decoded.mask |> should.equal(qr.mask)
}

pub fn reads_a_full_version_40_numeric_symbol_test() -> Nil {
  // One Numeric segment of 7089 digits: reading it must not grow the
  // JavaScript stack with the segment length.
  let digits = string.repeat("7", 7089)
  let assert Ok(qr) =
    qrkit.encode_with(
      digits,
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.Low,
      ),
    )
  let assert Ok(decoded) = qrkit.decode(qr.rows)
  decoded.text |> should.equal(digits)
}

pub fn reads_the_eci_designator_test() -> Nil {
  let assert Ok(qr) =
    qrkit.encode_with(
      "Grüße",
      qrkit.EncodeOptions(..qrkit.default_encode_options(), eci: Some(26)),
    )
  let assert Ok(decoded) = qrkit.decode(qr.rows)
  decoded.text |> should.equal("Grüße")
  decoded.eci |> should.equal(Some(26))
}

pub fn reads_structured_append_parts_test() -> Nil {
  let payload = string.repeat("Structured Append ", 8)
  let assert Ok(parts) =
    qrkit.encode_split(payload, max_version: 2, error_correction: qrkit.Medium)
  let decoded =
    list.map(parts, fn(qr) {
      let assert Ok(d) = qrkit.decode(qr.rows)
      d
    })
  list.length(decoded) |> should.equal(list.length(parts))
  list.index_map(decoded, fn(d, i) {
    let assert Some(header) = d.structured_append
    header.position |> should.equal(i)
    header.total |> should.equal(list.length(parts))
  })
  list.map(decoded, fn(d) { d.text }) |> string.concat |> should.equal(payload)
}

pub fn replaces_unmapped_kanji_in_structured_append_test() -> Nil {
  let assert Ok(fixture) =
    simplifile.read("test/fixtures/interop_sequence_invalid_kanji.tsv")
  let assert [_, _, matrix] = string.split(string.trim(fixture), "\t")
  let assert Ok(decoded) = qrkit.decode(rows_of(string.split(matrix, "/")))
  decoded.text |> should.equal("\u{FFFD}")
  let assert Some(header) = decoded.structured_append
  header.position |> should.equal(1)
  header.total |> should.equal(2)
}

pub fn single_symbol_has_no_structured_append_test() -> Nil {
  let decoded = round_trip("HELLO", qrkit.Standard, qrkit.Medium)
  decoded.structured_append |> should.equal(None)
  decoded.eci |> should.equal(None)
}

pub fn strips_the_quiet_zone_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("quiet zone")
  let rows = qr.rows
  let width = list.length(rows) + 8
  let pad = fn(row) {
    list.flatten([list.repeat(False, 4), row, list.repeat(False, 4)])
  }
  let blank = list.repeat(list.repeat(False, width), 4)
  let padded = list.flatten([blank, list.map(rows, pad), blank])
  let assert Ok(decoded) = qrkit.decode(padded)
  decoded.text |> should.equal("quiet zone")
}

pub fn reads_rotated_and_mirrored_symbols_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("turned around")
  let rows = qr.rows
  let rotate = fn(r) { list.transpose(r) |> list.map(list.reverse) }
  [
    rotate(rows),
    rotate(rotate(rows)),
    rotate(rotate(rotate(rows))),
    list.transpose(rows),
    list.map(rows, list.reverse),
  ]
  |> list.each(fn(variant) {
    let assert Ok(decoded) = qrkit.decode(variant)
    decoded.text |> should.equal("turned around")
  })

  let assert Ok(rect) =
    qrkit.encode_with(
      "upside down",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Rectangular,
      ),
    )
  let assert Ok(decoded) =
    qrkit.decode(rect.rows |> list.reverse |> list.map(list.reverse))
  decoded.text |> should.equal("upside down")
}

pub fn reads_rmqr_turned_on_its_side_test() -> Nil {
  let assert Ok(rect) =
    qrkit.encode_with(
      "standing up",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Rectangular,
      ),
    )
  let rows = rect.rows
  let rotate = fn(r) { list.transpose(r) |> list.map(list.reverse) }
  [
    rotate(rows),
    rotate(rotate(rotate(rows))),
    list.transpose(rows),
    rotate(list.transpose(rows)) |> rotate |> rotate,
  ]
  |> list.each(fn(variant) {
    let assert Ok(decoded) = qrkit.decode(variant)
    decoded.text |> should.equal("standing up")
    decoded.symbol |> should.equal(qrkit.Rectangular)
  })
}

/// Flip one bit in each of the first `count` codewords of a version 1
/// symbol, following the placement order.
fn damage_codewords(qr: qrkit.QrCode, count: Int) -> List(List(Bool)) {
  let targets =
    standard.data_module_positions(qr.version)
    |> list.sized_chunk(8)
    |> list.take(count)
    |> list.filter_map(list.first)
  list.index_map(qr.rows, fn(row, r) {
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
    qrkit.encode_with(
      "HELLO",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.High,
        version: Some(1),
      ),
    )
  let assert Ok(decoded) = qrkit.decode(damage_codewords(qr, 8))
  decoded.text |> should.equal("HELLO")
  decoded.errors_corrected |> should.equal(8)
}

pub fn too_many_errors_is_reported_test() -> Nil {
  let assert Ok(qr) =
    qrkit.encode_with(
      "HELLO",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.Low,
        version: Some(1),
      ),
    )
  // Version 1-L has 7 error correction codewords; 10 damaged codewords are
  // past what it can correct.
  qrkit.decode(damage_codewords(qr, 10))
  |> should.equal(Error(qrkit.TooManyErrors))
}

pub fn rejects_sizes_that_match_no_symbol_test() -> Nil {
  let grid = list.repeat(list.repeat(True, 20), 20)
  qrkit.decode(grid) |> should.equal(Error(qrkit.NotASymbol(20, 20)))
  qrkit.decode([[True, True], [True]])
  |> should.equal(Error(qrkit.NotASymbol(2, 2)))
  qrkit.decode([]) |> should.equal(Error(qrkit.NotASymbol(0, 0)))
}

pub fn unreadable_format_information_test() -> Nil {
  // A 21x21 grid of dark modules is Standard QR sized, but neither format
  // copy is near a valid codeword in any orientation.
  qrkit.decode(list.repeat(list.repeat(True, 21), 21))
  |> should.equal(Error(qrkit.UnreadableFormatInformation))
}

pub fn micro_qr_half_codeword_padding_carries_no_error_test() -> Nil {
  // M1, M3-L and M3-M end with a 4-bit data codeword. When it is padding it
  // must be 0000; the encoder used to compute the error correction over a
  // full 0xEC pad byte, so every such symbol started with one codeword error
  // and a single damaged module made it unreadable.
  [
    #("705", qrkit.Low),
    #("1", qrkit.Low),
    #("HELLO", qrkit.Low),
    #("ABC12", qrkit.Medium),
  ]
  |> list.each(fn(case_) {
    let decoded = round_trip(case_.0, qrkit.Micro, case_.1)
    decoded.text |> should.equal(case_.0)
    decoded.errors_corrected |> should.equal(0)
  })
}

pub fn micro_qr_m1_matches_segno_test() -> Nil {
  // segno.make("705", version="M1", micro=True) and zxing-cpp both pick
  // mask 1 and write the same modules.
  let assert Ok(qr) =
    qrkit.encode_with(
      "705",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        error_correction: qrkit.Low,
      ),
    )
  qr.mask |> should.equal(1)
  qr.rows
  |> should.equal(
    rows_of([
      "11111110101", "10000010000", "10111010111", "10111010011", "10111010001",
      "10000010100", "11111110111", "00000000110", "11000001010", "01001010011",
      "11111101101",
    ]),
  )
}

// --- Symbols written by segno 1.6 ---------------------------------------

pub fn segno_iso_8859_1_byte_mode_test() -> Nil {
  // segno.make("héllo wörld", error="M"): Byte mode in ISO-8859-1, no ECI.
  let assert Ok(decoded) = qrkit.decode(rows_of(segno_latin1))
  decoded.text |> should.equal("héllo wörld")
}

pub fn segno_shift_jis_byte_mode_test() -> Nil {
  // segno.make("カナ漢字abc", encoding="shift_jis", mode="byte"): Byte mode
  // in Shift JIS, no ECI.
  let assert Ok(decoded) = qrkit.decode(rows_of(segno_shift_jis))
  decoded.text |> should.equal("カナ漢字abc")
}

pub fn segno_kanji_mode_test() -> Nil {
  // segno.make("東京タワー", error="M"): Kanji mode.
  let assert Ok(decoded) = qrkit.decode(rows_of(segno_kanji))
  decoded.text |> should.equal("東京タワー")
}

pub fn segno_micro_qr_test() -> Nil {
  // segno.make("QRKIT", micro=True): M2-M, Alphanumeric mode.
  let assert Ok(decoded) = qrkit.decode(rows_of(segno_micro))
  decoded.text |> should.equal("QRKIT")
  decoded.symbol |> should.equal(qrkit.Micro)
  decoded.version |> should.equal(2)
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
