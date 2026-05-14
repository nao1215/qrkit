import gleam/bit_array
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import qrkit
import qrkit/content
import qrkit/error
import qrkit/internal/reed_solomon
import qrkit/render/ascii
import qrkit/render/png
import qrkit/render/svg

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_version_test() -> Nil {
  qrkit.package_version()
  |> should.equal("0.1.0")
}

pub fn encode_returns_square_symbol_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  qrkit.width(qr)
  |> should.equal(qrkit.height(qr))
}

pub fn builder_accepts_explicit_ecc_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("https://nao1215.dev")
    |> qrkit.with_ecc(error.Quartile)
    |> qrkit.build()

  qrkit.error_correction(qr)
  |> should.equal(error.Quartile)
}

pub fn empty_input_is_rejected_test() -> Nil {
  qrkit.encode("")
  |> should.equal(Error(error.EmptyInput))
}

pub fn wifi_content_helper_test() -> Nil {
  content.wifi(
    ssid: "MyAP",
    password: "secret",
    security: content.Wpa2,
    hidden: False,
  )
  |> should.equal("WIFI:T:WPA2;S:MyAP;P:secret;;")
}

pub fn vcard_content_helper_test() -> Nil {
  content.vcard()
  |> content.with_name("Nao")
  |> content.with_phone("+81-90-0000-0000")
  |> content.with_email("nao@example.com")
  |> content.vcard_to_string()
  |> should.equal(
    "BEGIN:VCARD\nVERSION:3.0\nN:Nao\nFN:Nao\nTEL:+81-90-0000-0000\nEMAIL:nao@example.com\nEND:VCARD",
  )
}

pub fn ascii_renderer_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  ascii.to_string(qr)
  |> string.is_empty
  |> should.be_false
}

pub fn svg_renderer_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let xml = svg.to_string(qr, svg.default_options())
  string.starts_with(xml, "<svg")
  |> should.equal(True)

  string.contains(does: xml, contain: "path")
  |> should.equal(True)
}

pub fn hello_world_has_finder_patterns_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  should.equal(qrkit.version(qr), 1)
  should.equal(qrkit.module_at(qr, 0, 0), True)
  should.equal(qrkit.module_at(qr, 6, 0), True)
  should.equal(qrkit.module_at(qr, 0, 6), True)
  should.equal(qrkit.module_at(qr, 20, 0), True)
  should.equal(qrkit.module_at(qr, 0, 20), True)
}

pub fn hello_world_matches_reference_matrix_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "111111100010101111111",
    "100000101110001000001",
    "101110100010101011101",
    "101110100010101011101",
    "101110101011101011101",
    "100000100111001000001",
    "111111101010101111111",
    "000000000000000000000",
    "101010100100100010010",
    "011110001001000010001",
    "000111111101001011000",
    "111101011001110101110",
    "010011110101001110101",
    "000000001010001000101",
    "111111100000100101100",
    "100000100110001101000",
    "101110101100101111111",
    "101110100011010100010",
    "101110101111011101001",
    "100000100001110001011",
    "111111101101011100001",
  ])
}

pub fn numeric_reference_matrix_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_ecc(error.Medium)
    |> qrkit.build()

  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "111111100011101111111",
    "100000101110001000001",
    "101110100110001011101",
    "101110100101101011101",
    "101110101101101011101",
    "100000100001001000001",
    "111111101010101111111",
    "000000000000000000000",
    "101010100010100010010",
    "110100001011010100010",
    "000110111011011101110",
    "110011010101110110010",
    "001001110111011100001",
    "000000001010001000010",
    "111111100000100010001",
    "100000100010001001011",
    "101110101110101011101",
    "101110100101010101110",
    "101110101101011100101",
    "100000100001110111000",
    "111111101001011100101",
  ])
}

pub fn mask_selection_reference_matrix_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("A")
  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "111111101101001111111",
    "100000101100101000001",
    "101110100011101011101",
    "101110101010001011101",
    "101110100011001011101",
    "100000100101101000001",
    "111111101010101111111",
    "000000001001100000000",
    "101101110001101001011",
    "110110000111111001000",
    "100110110101000001101",
    "010101000001001111110",
    "111111110110100100110",
    "000000001001001001011",
    "111111101111100101011",
    "100000101100000110100",
    "101110100110111110001",
    "101110101101001111110",
    "101110101100101100000",
    "100000100110010100100",
    "111111101100010010010",
  ])
}

pub fn micro_qr_m2_produces_13x13_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_symbol(error.Micro)
    |> qrkit.with_ecc(error.Medium)
    |> qrkit.build()

  qrkit.width(qr)
  |> should.equal(13)
  qrkit.height(qr)
  |> should.equal(13)
  qrkit.symbol(qr)
  |> should.equal(error.Micro)
}

pub fn micro_qr_m1_half_codeword_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("01234")
    |> qrkit.with_symbol(error.Micro)
    |> qrkit.with_min_version(1)
    |> qrkit.with_ecc(error.Low)
    |> qrkit.build()

  qrkit.width(qr)
  |> should.equal(11)
  qrkit.height(qr)
  |> should.equal(11)
  qrkit.module_at(qr, 0, 0)
  |> should.equal(True)
}

pub fn micro_qr_m2_low_matches_iso_annex_i_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_symbol(error.Micro)
    |> qrkit.with_ecc(error.Low)
    |> qrkit.build()

  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "1111111010101",
    "1000001011101",
    "1011101001101",
    "1011101001111",
    "1011101011100",
    "1000001010001",
    "1111111001111",
    "0000000001100",
    "1101000010001",
    "0110101010101",
    "1110011111110",
    "0001010000110",
    "1110100110111",
  ])
}

pub fn structured_append_short_input_test() -> Nil {
  let assert Ok(shards) = qrkit.encode_split("HI", 40)

  shards
  |> list.length
  |> should.equal(1)
}

pub fn structured_append_long_input_splits_test() -> Nil {
  let assert Ok(shards) = qrkit.encode_split(string.repeat("0123456789", 8), 2)

  { list.length(shards) >= 2 }
  |> should.be_true
}

pub fn structured_append_max_version_too_small_test() -> Nil {
  qrkit.encode_split(string.repeat("0123456789", 60), 1)
  |> result_is_data_too_long
  |> should.be_true
}

fn result_is_data_too_long(result: Result(a, error.EncodeError)) -> Bool {
  case result {
    Error(error.DataExceedsCapacity(_, _)) -> True
    _ -> False
  }
}

pub fn rmqr_r7x43_default_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_symbol(error.Rectangular)
    |> qrkit.with_ecc(error.Medium)
    |> qrkit.build()

  qrkit.width(qr)
  |> should.equal(43)
  qrkit.height(qr)
  |> should.equal(7)
  qrkit.symbol(qr)
  |> should.equal(error.Rectangular)
  qrkit.module_at(qr, 0, 0)
  |> should.equal(True)
}

pub fn rmqr_rejects_low_ecc_test() -> Nil {
  qrkit.new("HELLO")
  |> qrkit.with_symbol(error.Rectangular)
  |> qrkit.with_ecc(error.Low)
  |> qrkit.build()
  |> result_is_incompatible
  |> should.be_true
}

pub fn rmqr_rejects_quartile_ecc_test() -> Nil {
  qrkit.new("HELLO")
  |> qrkit.with_symbol(error.Rectangular)
  |> qrkit.with_ecc(error.Quartile)
  |> qrkit.build()
  |> result_is_incompatible
  |> should.be_true
}

pub fn rmqr_large_size_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new(string.repeat("0123456789", 6))
    |> qrkit.with_symbol(error.Rectangular)
    |> qrkit.with_ecc(error.Medium)
    |> qrkit.build()

  { qrkit.width(qr) > 27 }
  |> should.be_true
  { qrkit.height(qr) >= 7 && qrkit.height(qr) <= 17 }
  |> should.be_true
}

pub fn micro_qr_m1_rejects_high_ecc_test() -> Nil {
  qrkit.new("12345")
  |> qrkit.with_symbol(error.Micro)
  |> qrkit.with_ecc(error.High)
  |> qrkit.build()
  |> result_is_incompatible
  |> should.be_true
}

fn result_is_incompatible(result: Result(a, error.EncodeError)) -> Bool {
  case result {
    Error(error.IncompatibleOptions(_)) -> True
    _ -> False
  }
}

pub fn reed_solomon_v1_q_iso_vector_test() -> Nil {
  // ISO/IEC 18004 §I.2 - HELLO WORLD at version 1, ECC level Q.
  // Data: 16 codewords padded with 0xEC 0x11 repeating.
  // Expected EC codewords: 10 bytes per Annex I.
  reed_solomon.encode(
    [
      0x20, 0x5B, 0x0B, 0x78, 0xD1, 0x72, 0xDC, 0x4D, 0x43, 0x40, 0xEC, 0x11,
      0xEC, 0x11, 0xEC, 0x11,
    ],
    10,
  )
  |> should.equal([0xC4, 0x23, 0x27, 0x77, 0xEB, 0xD7, 0xE7, 0xE2, 0x5D, 0x17])
}

pub fn reed_solomon_v1_m_iso_vector_test() -> Nil {
  // ISO/IEC 18004 §I.2 - HELLO WORLD at version 1, ECC level M.
  reed_solomon.encode(
    [
      0x20,
      0x5B,
      0x0B,
      0x78,
      0xD1,
      0x72,
      0xDC,
      0x4D,
      0x43,
      0x40,
      0xEC,
      0x11,
      0xEC,
    ],
    13,
  )
  |> should.equal([
    0xA8, 0x48, 0x16, 0x52, 0xD9, 0x36, 0x9C, 0x00, 0x2E, 0x0F, 0xB4, 0x7A, 0x10,
  ])
}

pub fn reed_solomon_generator_polynomial_test() -> Nil {
  // ISO/IEC 18004 §A.2 - generator polynomial of degree 7.
  reed_solomon.generator_polynomial(7)
  |> should.equal([1, 127, 122, 154, 164, 11, 68, 117])
}

pub fn png_renderer_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let image = png.to_bit_array(qr, scale: 2, margin: 4)

  { bit_array.byte_size(image) > 0 }
  |> should.be_true

  let assert Ok(signature) = bit_array.slice(image, at: 0, take: 8)
  signature
  |> should.equal(<<137, 80, 78, 71, 13, 10, 26, 10>>)

  let assert Ok(dimensions) = bit_array.slice(image, at: 16, take: 8)
  dimensions
  |> should.equal(<<0, 0, 0, 58, 0, 0, 0, 58>>)
}

fn rows_to_strings(rows: List(List(Bool))) -> List(String) {
  rows
  |> list.map(fn(row) {
    row
    |> list.map(fn(value) {
      case value {
        True -> "1"
        False -> "0"
      }
    })
    |> string.join(with: "")
  })
}
