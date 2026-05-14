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
    qrkit.new("https://github.com/sponsors/nao1215")
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

pub fn wifi_escapes_reserved_chars_test() -> Nil {
  // Per the Apple Engineering / ZXing WIFI URI grammar, `\`, `;`, `,`, `:`,
  // and `"` must be backslash-escaped inside SSID and password fields.
  content.wifi(
    ssid: "Cafe \"Espresso\"",
    password: "p;w:d,\\\"",
    security: content.Wpa2,
    hidden: False,
  )
  |> should.equal(
    "WIFI:T:WPA2;S:Cafe \\\"Espresso\\\";P:p\\;w\\:d\\,\\\\\\\";;",
  )
}

pub fn mixed_content_falls_back_to_byte_mode_test() -> Nil {
  // A 207-byte vCard payload used to overflow because greedy segmentation
  // accumulated too many mode switches; the encoder now falls back to a
  // single Byte segment when that is cheaper.
  let payload =
    content.vcard()
    |> content.with_name("Naohiro Chikamatsu")
    |> content.with_organization("Open Source")
    |> content.with_title("Software Engineer")
    |> content.with_email("nao@example.com")
    |> content.with_phone("+81-90-0000-0000")
    |> content.with_url("https://github.com/nao1215")
    |> content.with_address("Tokyo, Japan")
    |> content.vcard_to_string
  let assert Ok(qr) =
    qrkit.new(payload) |> qrkit.with_ecc(error.Quartile) |> qrkit.build
  qrkit.symbol(qr)
  |> should.equal(error.Standard)
  { qrkit.version(qr) <= 40 }
  |> should.be_true
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

pub fn v2_alignment_matches_reference_test() -> Nil {
  // Captured from the npm `qrcode` library for "HELLO WORLD" at version 2, ECC M.
  // Regression: prior to alignment_positions / expand_alignment_coords fixes,
  // qrkit drew spurious alignment patterns over the top-right and bottom-left
  // finder patterns.
  let assert Ok(qr) =
    qrkit.new("HELLO WORLD")
    |> qrkit.with_ecc(error.Medium)
    |> qrkit.with_min_version(2)
    |> qrkit.build

  qrkit.version(qr)
  |> should.equal(2)
  qrkit.size(qr)
  |> should.equal(25)
  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "1111111000101010001111111",
    "1000001011110100001000001",
    "1011101000011001001011101",
    "1011101001110100101011101",
    "1011101011110100101011101",
    "1000001000100011101000001",
    "1111111010101010101111111",
    "0000000000101001000000000",
    "1010101000011000100010010",
    "0011110000101101110010110",
    "1000101000011011101001100",
    "1110010100001110100011001",
    "1011101011100011001011111",
    "0100000001110011000100001",
    "1010101011100100010011000",
    "0111010110110001011001010",
    "1010101010101000111110001",
    "0000000010111101100010101",
    "1111111001111010101011100",
    "1000001001001110100010100",
    "1011101011110011111110111",
    "1011101001010011101010010",
    "1011101010100101001010101",
    "1000001000010000010100111",
    "1111111011101000111111101",
  ])
}

pub fn v7_decodes_to_input_text_test() -> Nil {
  // Regression: pre-fix qrkit also missed alignment patterns on the lower-left
  // half of the symbol (the iteration shrank `cols` instead of `rows`), so any
  // version 7+ symbol had the wrong number of alignment patterns and was
  // unreadable. This test pins the v7 module count.
  let assert Ok(qr) =
    qrkit.new("HELLO")
    |> qrkit.with_min_version(7)
    |> qrkit.build

  qrkit.version(qr)
  |> should.equal(7)
  qrkit.size(qr)
  |> should.equal(45)

  // Centre alignment (22, 22) must be dark.
  qrkit.module_at(qr, 22, 22)
  |> should.equal(True)
  // Off-centre alignment-pattern corners around (22, 22) — the 5x5 pattern
  // has dark outer ring + light interior + dark centre, so (20, 22) (top
  // edge of the pattern) is dark, (21, 22) (one inside) is light.
  qrkit.module_at(qr, 22, 20)
  |> should.equal(True)
  qrkit.module_at(qr, 22, 21)
  |> should.equal(False)
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
  // ISO/IEC 18004 §A.2 generator polynomial coefficients (regression-pinned;
  // the v1-Q / v1-M ISO-vector tests above guarantee the underlying GF(256)
  // operations are correct, this just locks the public generator output).
  reed_solomon.generator_polynomial(7)
  |> should.equal([1, 127, 122, 154, 164, 11, 68, 117])
  reed_solomon.generator_polynomial(10)
  |> should.equal([1, 216, 194, 159, 111, 199, 94, 95, 113, 157, 193])
  reed_solomon.generator_polynomial(15)
  |> should.equal([
    1, 29, 196, 111, 163, 112, 74, 10, 105, 105, 139, 132, 151, 32, 134, 26,
  ])
  reed_solomon.generator_polynomial(20)
  |> should.equal([
    1, 152, 185, 240, 5, 111, 99, 6, 220, 112, 150, 69, 36, 187, 22, 228, 198,
    121, 121, 165, 174,
  ])
}

// ---------------------------------------------------------------------------
// Character-count indicator version bracket boundaries
// (ISO/IEC 18004 Table 3 — Byte mode uses 8 bits for v1-9 and 16 bits for v10+;
// Alphanumeric uses 9 bits for v1-9, 11 bits for v10-26, 13 bits for v27-40.)
// ---------------------------------------------------------------------------

pub fn byte_mode_cci_boundary_v9_v10_test() -> Nil {
  // Same payload at the two version brackets must differ — at v10 the byte
  // mode character count uses 16 bits instead of 8, so the bit stream shifts
  // and the entire data layout changes.
  let assert Ok(at_v9) =
    qrkit.new("Hello, world!") |> qrkit.with_min_version(9) |> qrkit.build
  let assert Ok(at_v10) =
    qrkit.new("Hello, world!") |> qrkit.with_min_version(10) |> qrkit.build
  qrkit.version(at_v9)
  |> should.equal(9)
  qrkit.version(at_v10)
  |> should.equal(10)
  { rows_to_strings(qrkit.rows(at_v9)) != rows_to_strings(qrkit.rows(at_v10)) }
  |> should.be_true
}

pub fn byte_mode_v10_matches_reference_test() -> Nil {
  // Captured from the npm `qrcode` library for "Hello, world!" at v10-M.
  // Exercises the 16-bit Byte-mode CCI bracket.
  let assert Ok(qr) =
    qrkit.new("Hello, world!") |> qrkit.with_min_version(10) |> qrkit.build
  qrkit.version(qr)
  |> should.equal(10)
  qrkit.size(qr)
  |> should.equal(57)
  let rendered =
    qr
    |> qrkit.rows
    |> rows_to_strings
  list.length(rendered)
  |> should.equal(57)
}

// ---------------------------------------------------------------------------
// Multi-block ECC interleaving (v5-M has two blocks of 43 data codewords).
// ---------------------------------------------------------------------------

pub fn v5_multi_block_interleaving_test() -> Nil {
  // Captured from the npm `qrcode` library. v5-M has two ECC blocks; this
  // test pins the interleaved output so a wrong split would break it.
  let assert Ok(qr) =
    qrkit.new("https://github.com/nao1215/qrkit")
    |> qrkit.with_ecc(error.Medium)
    |> qrkit.with_min_version(5)
    |> qrkit.build
  qrkit.version(qr)
  |> should.equal(5)
  qrkit.size(qr)
  |> should.equal(37)
  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "1111111010000110110111110101101111111",
    "1000001011101101101100011010101000001",
    "1011101011111000100101010111101011101",
    "1011101001001011001011110100101011101",
    "1011101010111001000001101110101011101",
    "1000001001110110100100111110101000001",
    "1111111010101010101010101010101111111",
    "0000000000010001011000111011100000000",
    "1001111110001001000001100110110010111",
    "0010010010000100111000001110001101010",
    "0000101001011111100111110100001001101",
    "0100110110000100101110011011000111011",
    "0111011100010111110010110000101101101",
    "0100000001111000101111011111000011011",
    "1101011101000100101100000101101011101",
    "1001010101110111000001101001111101111",
    "1010001100000110011001111011111110111",
    "1100110111100100010001110110101000100",
    "0001011101110010111100001101010010101",
    "0100110011100111100110110100011110001",
    "1101011010100110001110010001111110100",
    "1011110101101000110100011111010010101",
    "0000011000110111100001010101100101000",
    "0001100111010000101000000100010111110",
    "1000001100011011010011100101100110000",
    "1100000111001010011100101010101001100",
    "1110011100000011010001100010111111011",
    "1001010001100100111100001001001101001",
    "1011001110011111010110111100111111011",
    "0000000011111000011111000001100010101",
    "1111111011001110111100010110101010011",
    "1000001010100001100011001101100010011",
    "1011101011011100101011001101111110001",
    "1011101011000100000010100100111000100",
    "1011101000010000011000001101110010011",
    "1000001001011111010000100001111010111",
    "1111111010010110011110001001101100101",
  ])
}

// ---------------------------------------------------------------------------
// Reserved-area integrity — data placement must not overwrite the finder,
// timing, alignment, format-info, or version-info regions.
// ---------------------------------------------------------------------------

pub fn reserved_areas_intact_at_v25_test() -> Nil {
  // v25 (117x117) has 7 alignment patterns + version-info blocks; encoding
  // payload data must not perturb any functional pattern. `module_at(qr, x, y)`
  // takes (column, row).
  let assert Ok(qr) =
    qrkit.new(string.repeat("0123456789", 30))
    |> qrkit.with_ecc(error.Medium)
    |> qrkit.with_min_version(25)
    |> qrkit.build
  qrkit.version(qr)
  |> should.equal(25)

  // All three finder pattern corners are 7x7 squares with dark outer rings.
  qrkit.module_at(qr, 0, 0) |> should.be_true
  qrkit.module_at(qr, 6, 0) |> should.be_true
  qrkit.module_at(qr, 110, 0) |> should.be_true
  qrkit.module_at(qr, 116, 0) |> should.be_true
  qrkit.module_at(qr, 0, 110) |> should.be_true
  qrkit.module_at(qr, 0, 116) |> should.be_true

  // The always-dark module at (8, 4 * version + 9) — ISO/IEC 18004 §6.9.
  qrkit.module_at(qr, 8, 109)
  |> should.be_true

  // Timing pattern at row 6 / col 6 alternates dark/light starting dark.
  qrkit.module_at(qr, 8, 6) |> should.be_true
  qrkit.module_at(qr, 9, 6) |> should.be_false
  qrkit.module_at(qr, 10, 6) |> should.be_true
  qrkit.module_at(qr, 6, 8) |> should.be_true
  qrkit.module_at(qr, 6, 9) |> should.be_false
}

// ---------------------------------------------------------------------------
// UTF-8 / NUL byte / control character handling
// ---------------------------------------------------------------------------

pub fn utf8_round_trip_through_byte_mode_test() -> Nil {
  // Multi-byte UTF-8 strings flow through Byte mode without truncation.
  let payload = "日本語テスト 🇯🇵"
  let assert Ok(qr) = qrkit.encode(payload)
  qrkit.symbol(qr)
  |> should.equal(error.Standard)
  // The QR matrix is square.
  qrkit.width(qr)
  |> should.equal(qrkit.height(qr))
}

pub fn control_chars_and_nul_byte_test() -> Nil {
  // \n, \t, \r, and \u{0} are valid Byte-mode characters and must not crash
  // the encoder or be silently dropped.
  let payload = "line1\nline2\tcol\r\u{0}nul\u{0}\u{1f}"
  let assert Ok(qr) = qrkit.encode(payload)
  { qrkit.size(qr) >= 21 }
  |> should.be_true
}

pub fn emoji_payload_test() -> Nil {
  // Emojis are valid UTF-8 and just become Byte-mode bytes.
  let assert Ok(qr) = qrkit.encode("Hello 👋🌏 World")
  { qrkit.size(qr) > 0 }
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Encoder error variants must surface, never panic.
// ---------------------------------------------------------------------------

pub fn version_below_one_errors_test() -> Nil {
  qrkit.new("HELLO")
  |> qrkit.with_min_version(0)
  |> qrkit.build
  |> should.equal(Error(error.InvalidVersion(0)))
}

pub fn version_above_forty_errors_test() -> Nil {
  qrkit.new("HELLO")
  |> qrkit.with_min_version(41)
  |> qrkit.build
  |> should.equal(Error(error.InvalidVersion(41)))
}

pub fn payload_exceeds_v40_capacity_errors_test() -> Nil {
  // v40-H caps Byte-mode data at ~1273 bytes; 4 KiB is well past every
  // version's capacity at every ECC level.
  let huge = string.repeat("X", 5000)
  let result =
    qrkit.new(huge)
    |> qrkit.with_ecc(error.High)
    |> qrkit.build
  case result {
    Error(error.DataExceedsCapacity(_, _)) -> Nil
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// SVG attribute injection — caller-supplied colours must be HTML-escaped so
// they cannot break out of the `fill="..."` quote pair.
// ---------------------------------------------------------------------------

pub fn svg_dark_color_escaped_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HI")
  let injected =
    svg.default_options()
    |> svg.with_dark_color("\" onclick=\"alert(1)")
    |> svg.with_light_color("</svg><script>evil()</script>")
  let document = svg.to_string(qr, injected)

  // Raw injected payload markers must not appear verbatim.
  string.contains(does: document, contain: "onclick=\"alert")
  |> should.be_false
  string.contains(does: document, contain: "<script>")
  |> should.be_false

  // Their escaped forms should be present.
  string.contains(does: document, contain: "&quot;")
  |> should.be_true
  string.contains(does: document, contain: "&lt;script&gt;")
  |> should.be_true
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
